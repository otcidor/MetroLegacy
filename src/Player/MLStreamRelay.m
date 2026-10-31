#import "MLStreamRelay.h"
#import "MLTLSTrustManager.h"
#import <UIKit/UIKit.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>
#import <signal.h>

@interface MLSidxSegment : NSObject
@property (nonatomic, assign) long long startOffset;
@property (nonatomic, assign) long long endOffset;
@property (nonatomic, assign) double duration;
@end

@implementation MLSidxSegment
@end

static const long long MLRelayDefaultChunkSize = 262144; // 256 KB
static NSString *const MLRelayUpstreamUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";

static BOOL MLWriteAll(int fd, const void *buffer, size_t length)
{
	const char *ptr = (const char *)buffer;
	size_t remaining = length;
	while (remaining > 0) {
		ssize_t written = write(fd, ptr, remaining);
		if (written <= 0) {
			if (written < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) {
				usleep(10000); // 10ms
				continue;
			}
			return NO;
		}
		ptr += written;
		remaining -= written;
	}
	return YES;
}

static long long MLParseTotalFromContentRange(NSString *contentRange)
{
	if (!contentRange.length)
		return 0;
	NSRange slash = [contentRange rangeOfString:@"/"];
	if (slash.location != NSNotFound && slash.location + 1 < contentRange.length) {
		NSString *totStr = [contentRange substringFromIndex:slash.location + 1];
		return [totStr longLongValue];
	}
	return 0;
}

static uint32_t MLCrc32Mpeg2(const uint8_t *data, size_t len)
{
	uint32_t crc = 0xFFFFFFFF;
	for (size_t i = 0; i < len; i++) {
		crc ^= ((uint32_t)data[i] << 24);
		for (int b = 0; b < 8; b++) {
			if (crc & 0x80000000)
				crc = (crc << 1) ^ 0x04C11DB7;
			else
				crc = (crc << 1);
		}
	}
	return crc;
}

static void MLMakePat(uint8_t outPkt[188])
{
	memset(outPkt, 0xFF, 188);
	outPkt[0] = 0x47;
	outPkt[1] = 0x40; // payload unit start, PID 0
	outPkt[2] = 0x00;
	outPkt[3] = 0x10; // payload only, cc 0
	uint8_t payload[] = {
		0x00, // pointer field
		0x00, // table_id PAT
		0xB0, 0x0D, // section syntax=1, section_length=13
		0x00, 0x01, // transport_stream_id=1
		0xC1, // version=0, current=1
		0x00, // section 0
		0x00, // last section 0
		0x00, 0x01, // program number 1
		0xE1, 0x00  // PMT PID 0x0100
	};
	memcpy(outPkt + 4, payload, sizeof(payload));
	uint32_t crc = MLCrc32Mpeg2(payload + 1, sizeof(payload) - 1);
	outPkt[4 + sizeof(payload) + 0] = (uint8_t)(crc >> 24);
	outPkt[4 + sizeof(payload) + 1] = (uint8_t)(crc >> 16);
	outPkt[4 + sizeof(payload) + 2] = (uint8_t)(crc >> 8);
	outPkt[4 + sizeof(payload) + 3] = (uint8_t)(crc);
}

static void MLMakePmt(uint8_t outPkt[188])
{
	memset(outPkt, 0xFF, 188);
	outPkt[0] = 0x47;
	outPkt[1] = 0x41; // payload unit start, PID 0x0100
	outPkt[2] = 0x00;
	outPkt[3] = 0x10; // payload only, cc 0
	uint8_t payload[] = {
		0x00, // pointer field
		0x02, // table_id PMT
		0xB0, 0x12, // section syntax=1, section_length=18
		0x00, 0x01, // program number 1
		0xC1, // version=0, current=1
		0x00, // section 0
		0x00, // last section 0
		0xE1, 0x01, // PCR PID 0x0101
		0xF0, 0x00, // program info length 0
		0x0F, // stream type 0x0F (ISO/IEC 13818-7 ADTS AAC audio)
		0xE1, 0x01, // elementary PID 0x0101
		0xF0, 0x00  // ES info length 0
	};
	memcpy(outPkt + 4, payload, sizeof(payload));
	uint32_t crc = MLCrc32Mpeg2(payload + 1, sizeof(payload) - 1);
	outPkt[4 + sizeof(payload) + 0] = (uint8_t)(crc >> 24);
	outPkt[4 + sizeof(payload) + 1] = (uint8_t)(crc >> 16);
	outPkt[4 + sizeof(payload) + 2] = (uint8_t)(crc >> 8);
	outPkt[4 + sizeof(payload) + 3] = (uint8_t)(crc);
}

static NSArray *MLParseSidxSegments(NSData *headerData, uint32_t *outTimescale)
{
	if (!headerData || headerData.length < 32)
		return nil;

	const uint8_t *bytes = (const uint8_t *)headerData.bytes;
	size_t len = headerData.length;

	const uint8_t *sidxPtr = NULL;
	size_t sidxBoxStart = 0;
	for (size_t i = 4; i + 8 <= len; i++) {
		if (bytes[i] == 's' && bytes[i+1] == 'i' && bytes[i+2] == 'd' && bytes[i+3] == 'x') {
			sidxPtr = bytes + i;
			sidxBoxStart = i - 4;
			break;
		}
	}
	if (!sidxPtr || (size_t)(sidxPtr - bytes + 24) > len)
		return nil;

	uint32_t boxSize = ((uint32_t)bytes[sidxBoxStart] << 24) | ((uint32_t)bytes[sidxBoxStart+1] << 16) |
	                   ((uint32_t)bytes[sidxBoxStart+2] << 8) | (uint32_t)bytes[sidxBoxStart+3];
	if (boxSize < 32)
		return nil;

	uint8_t version = sidxPtr[4];
	uint32_t timescale = ((uint32_t)sidxPtr[12] << 24) | ((uint32_t)sidxPtr[13] << 16) |
	                     ((uint32_t)sidxPtr[14] << 8)  | (uint32_t)sidxPtr[15];
	if (timescale == 0) timescale = 44100;
	if (outTimescale) *outTimescale = timescale;

	const uint8_t *cur = sidxPtr + 16;
	uint64_t firstOffset = 0;
	if (version == 0) {
		cur += 4; // earliest_presentation_time
		firstOffset = ((uint32_t)cur[0] << 24) | ((uint32_t)cur[1] << 16) | ((uint32_t)cur[2] << 8) | (uint32_t)cur[3];
		cur += 4;
	} else {
		cur += 8; // earliest_presentation_time
		firstOffset = ((uint64_t)cur[0] << 56) | ((uint64_t)cur[1] << 48) | ((uint64_t)cur[2] << 40) | ((uint64_t)cur[3] << 32) |
		              ((uint64_t)cur[4] << 24) | ((uint64_t)cur[5] << 16) | ((uint64_t)cur[6] << 8)  | (uint64_t)cur[7];
		cur += 8;
	}

	cur += 2; // reserved
	if (cur + 2 > bytes + len) return nil;
	uint16_t refCount = ((uint16_t)cur[0] << 8) | (uint16_t)cur[1];
	cur += 2;

	long long segStart = (long long)(sidxBoxStart + boxSize + firstOffset);
	NSMutableArray *segments = [NSMutableArray arrayWithCapacity:refCount];

	for (uint16_t i = 0; i < refCount; i++) {
		if (cur + 12 > bytes + len) break;
		uint32_t val1 = ((uint32_t)cur[0] << 24) | ((uint32_t)cur[1] << 16) | ((uint32_t)cur[2] << 8) | (uint32_t)cur[3];
		uint32_t refSz = val1 & 0x7FFFFFFF;
		uint32_t subsegDur = ((uint32_t)cur[4] << 24) | ((uint32_t)cur[5] << 16) | ((uint32_t)cur[6] << 8) | (uint32_t)cur[7];
		double dur = (double)subsegDur / (double)timescale;

		MLSidxSegment *seg = [[MLSidxSegment alloc] init];
		seg.startOffset = segStart;
		seg.endOffset = segStart + refSz - 1;
		seg.duration = dur;
		[segments addObject:seg];

		segStart += refSz;
		cur += 12;
	}

	return segments;
}

static NSData *MLExtractAdtsFromMp4Fragment(NSData *fragData, uint32_t timescale, int channels)
{
	if (!fragData || fragData.length < 16)
		return nil;

	const uint8_t *bytes = (const uint8_t *)fragData.bytes;
	size_t len = fragData.length;

	// Locate moof and trun
	const uint8_t *trunPtr = NULL;
	for (size_t i = 0; i + 8 <= len; i++) {
		if (bytes[i] == 't' && bytes[i+1] == 'r' && bytes[i+2] == 'u' && bytes[i+3] == 'n') {
			trunPtr = bytes + i;
			break;
		}
	}
	if (!trunPtr || (size_t)(trunPtr - bytes + 12) > len)
		return nil;

	uint32_t flags = ((uint32_t)trunPtr[5] << 16) | ((uint32_t)trunPtr[6] << 8) | (uint32_t)trunPtr[7];
	uint32_t sampleCount = ((uint32_t)trunPtr[8] << 24) | ((uint32_t)trunPtr[9] << 16) |
	                       ((uint32_t)trunPtr[10] << 8) | (uint32_t)trunPtr[11];

	const uint8_t *cur = trunPtr + 12;
	if (flags & 0x0001) cur += 4; // data_offset
	if (flags & 0x0004) cur += 4; // first_sample_flags
	BOOL hasDur = (flags & 0x0100) != 0;
	BOOL hasSz  = (flags & 0x0200) != 0;
	BOOL hasFlg = (flags & 0x0400) != 0;
	BOOL hasCto = (flags & 0x0800) != 0;

	if (!hasSz || sampleCount == 0 || sampleCount > 5000)
		return nil;

	uint32_t *sampleSizes = malloc(sizeof(uint32_t) * sampleCount);
	if (!sampleSizes)
		return nil;

	for (uint32_t i = 0; i < sampleCount; i++) {
		if (cur + 4 > bytes + len) {
			free(sampleSizes);
			return nil;
		}
		if (hasDur) cur += 4;
		sampleSizes[i] = ((uint32_t)cur[0] << 24) | ((uint32_t)cur[1] << 16) |
		                 ((uint32_t)cur[2] << 8)  | (uint32_t)cur[3];
		cur += 4;
		if (hasFlg) cur += 4;
		if (hasCto) cur += 4;
	}

	// Locate mdat
	const uint8_t *mdatPayload = NULL;
	for (size_t i = 0; i + 8 <= len; i++) {
		if (bytes[i] == 'm' && bytes[i+1] == 'd' && bytes[i+2] == 'a' && bytes[i+3] == 't') {
			mdatPayload = bytes + i + 4; // after 'mdat' header tag (payload starts at i + 4)
			break;
		}
	}
	if (!mdatPayload) {
		free(sampleSizes);
		return nil;
	}

	uint8_t freqIdx = 4; // 44100 Hz default
	if (timescale == 48000) freqIdx = 3;
	else if (timescale == 44100) freqIdx = 4;
	else if (timescale == 32000) freqIdx = 5;
	else if (timescale == 24000) freqIdx = 6;
	else if (timescale == 22050) freqIdx = 7;
	else if (timescale == 16000) freqIdx = 8;
	uint8_t chan = (channels > 0) ? (uint8_t)channels : 2;
	uint8_t profile = 1; // AAC-LC

	NSMutableData *adtsOut = [NSMutableData dataWithCapacity:fragData.length + sampleCount * 7];
	const uint8_t *sampleCur = mdatPayload;

	for (uint32_t i = 0; i < sampleCount; i++) {
		uint32_t sSz = sampleSizes[i];
		if (sampleCur + sSz > bytes + len)
			break;

		uint32_t frameLen = sSz + 7;
		uint8_t adts[7];
		adts[0] = 0xFF;
		adts[1] = 0xF1;
		adts[2] = ((profile & 3) << 6) | ((freqIdx & 0xF) << 2) | ((chan >> 2) & 1);
		adts[3] = ((chan & 3) << 6) | ((frameLen >> 11) & 3);
		adts[4] = (uint8_t)((frameLen >> 3) & 0xFF);
		adts[5] = (uint8_t)(((frameLen & 7) << 5) | 0x1F);
		adts[6] = 0xFC;

		[adtsOut appendBytes:adts length:7];
		[adtsOut appendBytes:sampleCur length:sSz];

		sampleCur += sSz;
	}

	free(sampleSizes);
	return adtsOut;
}

static NSData *MLMuxMp4FragmentToTs(NSData *fragData, uint64_t startPts, uint32_t timescale, int channels)
{
	if (!fragData || fragData.length < 16)
		return nil;

	const uint8_t *bytes = (const uint8_t *)fragData.bytes;
	size_t len = fragData.length;

	// Locate moof and trun
	const uint8_t *trunPtr = NULL;
	for (size_t i = 0; i + 8 <= len; i++) {
		if (bytes[i] == 't' && bytes[i+1] == 'r' && bytes[i+2] == 'u' && bytes[i+3] == 'n') {
			trunPtr = bytes + i;
			break;
		}
	}
	if (!trunPtr || (size_t)(trunPtr - bytes + 12) > len)
		return nil;

	uint32_t flags = ((uint32_t)trunPtr[5] << 16) | ((uint32_t)trunPtr[6] << 8) | (uint32_t)trunPtr[7];
	uint32_t sampleCount = ((uint32_t)trunPtr[8] << 24) | ((uint32_t)trunPtr[9] << 16) |
	                       ((uint32_t)trunPtr[10] << 8) | (uint32_t)trunPtr[11];

	const uint8_t *cur = trunPtr + 12;
	if (flags & 0x0001) cur += 4; // data_offset
	if (flags & 0x0004) cur += 4; // first_sample_flags
	BOOL hasDur = (flags & 0x0100) != 0;
	BOOL hasSz  = (flags & 0x0200) != 0;
	BOOL hasFlg = (flags & 0x0400) != 0;
	BOOL hasCto = (flags & 0x0800) != 0;

	if (!hasSz || sampleCount == 0 || sampleCount > 5000)
		return nil;

	uint32_t *sampleSizes = malloc(sizeof(uint32_t) * sampleCount);
	if (!sampleSizes)
		return nil;

	for (uint32_t i = 0; i < sampleCount; i++) {
		if (cur + 4 > bytes + len) {
			free(sampleSizes);
			return nil;
		}
		if (hasDur) cur += 4;
		sampleSizes[i] = ((uint32_t)cur[0] << 24) | ((uint32_t)cur[1] << 16) |
		                 ((uint32_t)cur[2] << 8)  | (uint32_t)cur[3];
		cur += 4;
		if (hasFlg) cur += 4;
		if (hasCto) cur += 4;
	}

	// Locate mdat
	const uint8_t *mdatPayload = NULL;
	for (size_t i = 0; i + 8 <= len; i++) {
		if (bytes[i] == 'm' && bytes[i+1] == 'd' && bytes[i+2] == 'a' && bytes[i+3] == 't') {
			mdatPayload = bytes + i + 4; // after 'mdat' header tag (payload starts at i + 4)
			break;
		}
	}
	if (!mdatPayload) {
		free(sampleSizes);
		return nil;
	}

	uint8_t freqIdx = 4; // 44100 Hz default
	if (timescale == 48000) freqIdx = 3;
	else if (timescale == 44100) freqIdx = 4;
	else if (timescale == 32000) freqIdx = 5;
	else if (timescale == 24000) freqIdx = 6;
	else if (timescale == 22050) freqIdx = 7;
	else if (timescale == 16000) freqIdx = 8;
	uint8_t chan = (channels > 0) ? (uint8_t)channels : 2;
	uint8_t profile = 1; // AAC-LC

	NSMutableData *tsOut = [NSMutableData dataWithCapacity:sampleCount * 250 + 376];

	uint8_t patPkt[188], pmtPkt[188];
	MLMakePat(patPkt);
	MLMakePmt(pmtPkt);
	[tsOut appendBytes:patPkt length:188];
	[tsOut appendBytes:pmtPkt length:188];

	uint64_t currentPts = startPts;
	uint8_t cc = 0;
	const uint8_t *sampleCur = mdatPayload;

	for (uint32_t i = 0; i < sampleCount; i++) {
		uint32_t sSz = sampleSizes[i];
		if (sampleCur + sSz > bytes + len)
			break;

		uint32_t frameLen = sSz + 7;
		uint8_t adts[7];
		adts[0] = 0xFF;
		adts[1] = 0xF1;
		adts[2] = ((profile & 3) << 6) | ((freqIdx & 0xF) << 2) | ((chan >> 2) & 1);
		adts[3] = ((chan & 3) << 6) | ((frameLen >> 11) & 3);
		adts[4] = (uint8_t)((frameLen >> 3) & 0xFF);
		adts[5] = (uint8_t)(((frameLen & 7) << 5) | 0x1F);
		adts[6] = 0xFC;

		uint32_t pesLen = frameLen + 8;
		if (pesLen > 0xFFFF) pesLen = 0;

		uint64_t pts = currentPts;
		uint8_t b0 = 0x20 | (uint8_t)(((pts >> 29) & 0x0E)) | 1;
		uint8_t b1 = (uint8_t)((pts >> 22) & 0xFF);
		uint8_t b2 = (uint8_t)(((pts >> 14) & 0xFE) | 1);
		uint8_t b3 = (uint8_t)((pts >> 7) & 0xFF);
		uint8_t b4 = (uint8_t)(((pts << 1) & 0xFE) | 1);

		uint8_t pesHdr[14];
		pesHdr[0] = 0x00; pesHdr[1] = 0x00; pesHdr[2] = 0x01; pesHdr[3] = 0xC0;
		pesHdr[4] = (uint8_t)((pesLen >> 8) & 0xFF);
		pesHdr[5] = (uint8_t)(pesLen & 0xFF);
		pesHdr[6] = 0x80;
		pesHdr[7] = 0x80;
		pesHdr[8] = 0x05;
		pesHdr[9] = b0; pesHdr[10] = b1; pesHdr[11] = b2; pesHdr[12] = b3; pesHdr[13] = b4;

		size_t fullPesLen = 14 + 7 + sSz;
		uint8_t *fullPes = malloc(fullPesLen);
		if (!fullPes) break;
		memcpy(fullPes, pesHdr, 14);
		memcpy(fullPes + 14, adts, 7);
		memcpy(fullPes + 21, sampleCur, sSz);

		size_t pesPos = 0;
		BOOL firstPkt = YES;
		while (pesPos < fullPesLen) {
			size_t rem = fullPesLen - pesPos;
			uint8_t tsPkt[188];
			if (rem < 184) {
				size_t stuffLen = 184 - rem;
				tsPkt[0] = 0x47;
				tsPkt[1] = firstPkt ? 0x41 : 0x01;
				tsPkt[2] = 0x01;
				tsPkt[3] = 0x30 | (cc & 0x0F);
				cc = (cc + 1) & 0x0F;
				if (stuffLen == 1) {
					tsPkt[3] = 0x30 | ((cc - 1) & 0x0F);
					tsPkt[4] = 0x00;
					memcpy(tsPkt + 5, fullPes + pesPos, rem);
				} else {
					tsPkt[4] = (uint8_t)(stuffLen - 1);
					tsPkt[5] = 0x00;
					memset(tsPkt + 6, 0xFF, stuffLen - 2);
					memcpy(tsPkt + 4 + stuffLen, fullPes + pesPos, rem);
				}
				[tsOut appendBytes:tsPkt length:188];
				pesPos += rem;
			} else {
				tsPkt[0] = 0x47;
				tsPkt[1] = firstPkt ? 0x41 : 0x01;
				tsPkt[2] = 0x01;
				tsPkt[3] = 0x10 | (cc & 0x0F);
				cc = (cc + 1) & 0x0F;
				memcpy(tsPkt + 4, fullPes + pesPos, 184);
				[tsOut appendBytes:tsPkt length:188];
				pesPos += 184;
			}
			firstPkt = NO;
		}
		free(fullPes);

		currentPts += (1024ULL * 90000ULL) / (timescale > 0 ? timescale : 44100);
		sampleCur += sSz;
	}

	free(sampleSizes);
	return tsOut;
}

@interface MLStreamRelay ()
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign) BOOL isRunning;
@end

@implementation MLStreamRelay
{
	int _serverSocket;
	BOOL _listening;
	BOOL _needsSocketRefresh;
	UIBackgroundTaskIdentifier _bgTask;
	dispatch_queue_t _acceptQueue;
	dispatch_queue_t _workerQueue;
	NSMutableDictionary *_urlMap;
	NSMutableDictionary *_totalLengthMap;
	NSMutableDictionary *_segmentsMap;
	NSMutableDictionary *_playlistMap;
	NSMutableDictionary *_timescaleMap;
	NSMutableDictionary *_durationMap;
	NSMutableDictionary *_finishedMap;
	NSMutableDictionary *_highestSegMap;
	NSLock *_lock;
	NSUInteger _generation;
	NSUInteger _listenerId;
}

+ (instancetype)sharedRelay
{
	static MLStreamRelay *r = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		r = [[MLStreamRelay alloc] init];
	});
	return r;
}

- (id)init
{
	self = [super init];
	if (self) {
		_serverSocket = -1;
		_port = 0;
		_listening = NO;
		_needsSocketRefresh = NO;
		_bgTask = UIBackgroundTaskInvalid;
		_generation = 0;
		_listenerId = 0;
		_lock = [[NSLock alloc] init];
		_urlMap = [[NSMutableDictionary alloc] init];
		_totalLengthMap = [[NSMutableDictionary alloc] init];
		_segmentsMap = [[NSMutableDictionary alloc] init];
		_playlistMap = [[NSMutableDictionary alloc] init];
		_timescaleMap = [[NSMutableDictionary alloc] init];
		_durationMap = [[NSMutableDictionary alloc] init];
		_finishedMap = [[NSMutableDictionary alloc] init];
		_highestSegMap = [[NSMutableDictionary alloc] init];
		_acceptQueue = dispatch_queue_create("win.otcidor.MLStreamRelay.accept", DISPATCH_QUEUE_CONCURRENT);
		_workerQueue = dispatch_queue_create("win.otcidor.MLStreamRelay.worker", DISPATCH_QUEUE_CONCURRENT);

		signal(SIGPIPE, SIG_IGN);

		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		[nc addObserver:self selector:@selector(onAppDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
		[nc addObserver:self selector:@selector(onAppWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
		[nc addObserver:self selector:@selector(onAppWillEnterForeground:) name:UIApplicationDidBecomeActiveNotification object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self stop];
}

- (void)onAppDidEnterBackground:(NSNotification *)note
{
	UIApplication *app = [UIApplication sharedApplication];
	if (_bgTask != UIBackgroundTaskInvalid) {
		[app endBackgroundTask:_bgTask];
		_bgTask = UIBackgroundTaskInvalid;
	}
	__weak MLStreamRelay *wself = self;
	_bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
		MLStreamRelay *s = wself;
		if (s) {
			[s->_lock lock];
			s->_needsSocketRefresh = YES;
			[s->_lock unlock];
			if (s->_bgTask != UIBackgroundTaskInvalid) {
				[[UIApplication sharedApplication] endBackgroundTask:s->_bgTask];
				s->_bgTask = UIBackgroundTaskInvalid;
			}
		}
	}];
}

- (void)onAppWillEnterForeground:(NSNotification *)note
{
	UIApplication *app = [UIApplication sharedApplication];
	if (_bgTask != UIBackgroundTaskInvalid) {
		[app endBackgroundTask:_bgTask];
		_bgTask = UIBackgroundTaskInvalid;
	}
	[self reviveListenerKeepingPort];
}

- (BOOL)stillListeningLocked
{
	if (_serverSocket < 0 || !_listening || _needsSocketRefresh)
		return NO;
	if (fcntl(_serverSocket, F_GETFL) == -1)
		return NO;
	int err = 0;
	socklen_t errLen = sizeof(err);
	if (getsockopt(_serverSocket, SOL_SOCKET, SO_ERROR, &err, &errLen) == 0 && err == 0) {
		return YES;
	}
	return NO;
}

- (BOOL)openPortLocked
{
	if ([self stillListeningLocked]) {
		return YES;
	}

	uint16_t desiredPort = _port;
	_listenerId++;
	if (_serverSocket >= 0) {
		close(_serverSocket);
		_serverSocket = -1;
	}
	_listening = NO;
	self.isRunning = NO;

	int fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0) {
		NSLog(@"[MLStreamRelay] socket() failed: %s", strerror(errno));
		return NO;
	}

	int opt = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#ifdef SO_REUSEPORT
	setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
#endif
	setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));

	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = inet_addr("127.0.0.1");
	addr.sin_port = htons(desiredPort);

	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		addr.sin_port = 0; // ephemeral port fallback
		if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
			NSLog(@"[MLStreamRelay] bind() failed: %s", strerror(errno));
			close(fd);
			return NO;
		}
	}

	if (listen(fd, 32) < 0) {
		NSLog(@"[MLStreamRelay] listen() failed: %s", strerror(errno));
		close(fd);
		return NO;
	}

	socklen_t len = sizeof(addr);
	if (getsockname(fd, (struct sockaddr *)&addr, &len) == 0) {
		self.port = ntohs(addr.sin_port);
	}

	_serverSocket = fd;
	_listening = YES;
	_needsSocketRefresh = NO;
	self.isRunning = YES;
	NSUInteger activeListenerId = _listenerId;
	NSLog(@"[MLStreamRelay] Listening on 127.0.0.1:%u (fd=%d, gen=%lu)", self.port, fd, (unsigned long)activeListenerId);

	__weak MLStreamRelay *wself = self;
	dispatch_async(_acceptQueue, ^{
		[wself acceptLoopWithSocket:fd listenerId:activeListenerId];
	});

	return YES;
}

- (BOOL)start
{
	[_lock lock];
	BOOL ok = [self openPortLocked];
	[_lock unlock];
	return ok;
}

- (BOOL)reviveListenerKeepingPort
{
	[_lock lock];
	BOOL ok = [self openPortLocked];
	[_lock unlock];
	return ok;
}

- (void)stop
{
	[_lock lock];
	_listenerId++;
	_listening = NO;
	_needsSocketRefresh = NO;
	self.isRunning = NO;
	if (_serverSocket >= 0) {
		close(_serverSocket);
		_serverSocket = -1;
	}
	[_urlMap removeAllObjects];
	[_totalLengthMap removeAllObjects];
	[_segmentsMap removeAllObjects];
	[_playlistMap removeAllObjects];
	[_timescaleMap removeAllObjects];
	[_durationMap removeAllObjects];
	[_finishedMap removeAllObjects];
	[_lock unlock];
}

- (NSURL *)relayURLForStreamURL:(NSURL *)remoteStreamURL
{
	if (!remoteStreamURL)
		return nil;

	// Local files (cached or downloaded) can be played directly without loopback proxy on iOS 7+.
	// On iOS 6 (< 7.0f), local DASH fMP4 files cannot be opened by AVPlayer directly (causes -12842),
	// so they must be demuxed and served via stream.aac.
	BOOL isLegacyIOS = ([[[UIDevice currentDevice] systemVersion] floatValue] < 7.0f);
	if (!isLegacyIOS && remoteStreamURL.isFileURL) {
		return remoteStreamURL;
	}

	[self reviveListenerKeepingPort];

	[_lock lock];
	_generation++;
	NSString *streamId = [NSString stringWithFormat:@"%lu", (unsigned long)_generation];
	_urlMap[streamId] = remoteStreamURL;
	[_finishedMap removeObjectForKey:streamId];
	[_highestSegMap removeObjectForKey:streamId];

	// For local downloaded or cached files, pre-populate total length from file attributes
	if (remoteStreamURL.isFileURL) {
		NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[remoteStreamURL path] error:nil];
		if (attrs && [attrs fileSize] > 0) {
			_totalLengthMap[streamId] = @([attrs fileSize]);
		}
	}

	// Keep cache size bounded to prevent memory growth across long playback sessions
	if (_urlMap.count > 12) {
		NSMutableArray *toRemove = [NSMutableArray array];
		for (NSString *key in _urlMap.allKeys) {
			NSUInteger keyGen = (NSUInteger)[key integerValue];
			if (keyGen + 10 < _generation) {
				[toRemove addObject:key];
			}
		}
		for (NSString *oldKey in toRemove) {
			[_urlMap removeObjectForKey:oldKey];
			[_totalLengthMap removeObjectForKey:oldKey];
			[_segmentsMap removeObjectForKey:oldKey];
			[_playlistMap removeObjectForKey:oldKey];
			[_timescaleMap removeObjectForKey:oldKey];
			[_durationMap removeObjectForKey:oldKey];
			[_finishedMap removeObjectForKey:oldKey];
			[_highestSegMap removeObjectForKey:oldKey];
		}
	}
	[_lock unlock];

	NSString *localURL = nil;
	if (isLegacyIOS) {
		localURL = [NSString stringWithFormat:@"http://127.0.0.1:%u/%@/stream.aac", self.port, streamId];
	} else {
		localURL = [NSString stringWithFormat:@"http://127.0.0.1:%u/%@/stream.mp4", self.port, streamId];
	}
	return [NSURL URLWithString:localURL];
}

- (NSURL *)aacRelayURLForStreamURL:(NSURL *)remoteStreamURL
{
	if (!remoteStreamURL)
		return nil;

	BOOL isLegacyIOS = ([[[UIDevice currentDevice] systemVersion] floatValue] < 7.0f);
	if (!isLegacyIOS && remoteStreamURL.isFileURL) {
		return remoteStreamURL;
	}

	[self reviveListenerKeepingPort];

	[_lock lock];
	_generation++;
	NSString *streamId = [NSString stringWithFormat:@"%lu", (unsigned long)_generation];
	_urlMap[streamId] = remoteStreamURL;
	[_finishedMap removeObjectForKey:streamId];
	[_highestSegMap removeObjectForKey:streamId];

	if (remoteStreamURL.isFileURL) {
		NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[remoteStreamURL path] error:nil];
		if (attrs && [attrs fileSize] > 0) {
			_totalLengthMap[streamId] = @([attrs fileSize]);
		}
	}

	if (_urlMap.count > 12) {
		NSMutableArray *toRemove = [NSMutableArray array];
		for (NSString *key in _urlMap.allKeys) {
			NSUInteger keyGen = (NSUInteger)[key integerValue];
			if (keyGen + 10 < _generation) {
				[toRemove addObject:key];
			}
		}
		for (NSString *oldKey in toRemove) {
			[_urlMap removeObjectForKey:oldKey];
			[_totalLengthMap removeObjectForKey:oldKey];
			[_segmentsMap removeObjectForKey:oldKey];
			[_playlistMap removeObjectForKey:oldKey];
			[_timescaleMap removeObjectForKey:oldKey];
			[_finishedMap removeObjectForKey:oldKey];
			[_highestSegMap removeObjectForKey:oldKey];
		}
	}
	[_lock unlock];

	NSString *localURL = [NSString stringWithFormat:@"http://127.0.0.1:%u/%@/stream.aac", self.port, streamId];
	return [NSURL URLWithString:localURL];
}

- (void)acceptLoopWithSocket:(int)listenFD listenerId:(NSUInteger)myListenerId
{
	while (listenFD >= 0) {
		[_lock lock];
		BOOL active = (_listening && _serverSocket == listenFD && _listenerId == myListenerId);
		[_lock unlock];
		if (!active)
			break;

		struct sockaddr_in clientAddr;
		socklen_t clientLen = sizeof(clientAddr);
		int clientFD = accept(listenFD, (struct sockaddr *)&clientAddr, &clientLen);
		if (clientFD < 0) {
			int err = errno;
			[_lock lock];
			BOOL stillCurrent = (_listening && _serverSocket == listenFD && _listenerId == myListenerId);
			[_lock unlock];
			if (!stillCurrent)
				break;
			if (err == EINTR || err == EAGAIN || err == EWOULDBLOCK) {
				usleep(50000);
				continue;
			}
			// Socket was reclaimed/defuncted by iOS kernel during background suspension
			NSLog(@"[MLStreamRelay] accept(fd=%d) failed (%d: %s), reviving listener...", listenFD, err, strerror(err));
			BOOL shouldRevive = NO;
			[_lock lock];
			if (_serverSocket == listenFD && _listenerId == myListenerId) {
				close(_serverSocket);
				_serverSocket = -1;
				_listening = NO;
				self.isRunning = NO;
				shouldRevive = YES;
			}
			[_lock unlock];
			if (shouldRevive) {
				[self reviveListenerKeepingPort];
			}
			break;
		}

		int noSigPipe = 1;
		setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));

		struct timeval rcvTv;
		rcvTv.tv_sec = 30;
		rcvTv.tv_usec = 0;
		setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &rcvTv, sizeof(rcvTv));

		struct timeval sndTv;
		sndTv.tv_sec = 120;
		sndTv.tv_usec = 0;
		setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &sndTv, sizeof(sndTv));

		__weak MLStreamRelay *wself = self;
		dispatch_async(_workerQueue, ^{
			[wself handleClient:clientFD];
		});
	}
}

- (NSData *)fetchRangeStart:(long long)start
                        end:(long long)end
                    fromURL:(NSURL *)remoteURL
               httpResponse:(NSHTTPURLResponse **)outResp
{
	if ([remoteURL isFileURL]) {
		NSString *filePath = [remoteURL path];
		NSFileManager *fm = [NSFileManager defaultManager];
		NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:nil];
		long long totalSize = (long long)[attrs fileSize];
		if (totalSize <= 0 || start < 0 || start >= totalSize) {
			return nil;
		}
		long long actualEnd = (end >= start && end < totalSize) ? end : (totalSize - 1);
		unsigned long long readLen = (unsigned long long)(actualEnd - start + 1);
		NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:filePath];
		if (!fh) return nil;
		NSData *data = nil;
		@try {
			[fh seekToFileOffset:(unsigned long long)start];
			data = [fh readDataOfLength:(NSUInteger)readLen];
		} @catch (id ex) {
			data = nil;
		}
		[fh closeFile];
		if (outResp && data.length > 0) {
			NSDictionary *headers = @{
				@"Content-Type" : @"audio/mp4",
				@"Content-Length" : [NSString stringWithFormat:@"%lu", (unsigned long)data.length],
				@"Content-Range" : [NSString stringWithFormat:@"bytes %lld-%lld/%lld", start, start + (long long)data.length - 1, totalSize],
				@"Accept-Ranges" : @"bytes"
			};
			*outResp = [[NSHTTPURLResponse alloc] initWithURL:remoteURL
			                                       statusCode:206
			                                      HTTPVersion:@"HTTP/1.1"
			                                     headerFields:headers];
		}
		return data;
	}

	NSHTTPURLResponse *lastResp = nil;

	for (int attempt = 0; attempt < 3; attempt++) {
		if (attempt > 0) {
			usleep(250000);
		}
		NSMutableURLRequest *upReq = [NSMutableURLRequest requestWithURL:remoteURL
		                                                     cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		                                                 timeoutInterval:20.0];
		upReq.HTTPShouldHandleCookies = NO;
		if (end >= start && start >= 0) {
			[upReq setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", start, end] forHTTPHeaderField:@"Range"];
		}
		[upReq setValue:MLRelayUpstreamUserAgent forHTTPHeaderField:@"User-Agent"];

		NSHTTPURLResponse *httpResp = nil;
		NSError *err = nil;
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:upReq returningResponse:&httpResp error:&err];
		lastResp = httpResp;

		NSInteger code = httpResp ? httpResp.statusCode : 0;
		if (data.length > 0 && (code == 200 || code == 206 || code == 0)) {
			if (outResp) {
				*outResp = httpResp;
			}
			return data;
		}

		NSLog(@"[MLStreamRelay] Upstream range %lld-%lld attempt %d failed (HTTP %ld, bytes=%lu, err=%@)",
		      start, end, attempt + 1, (long)code, (unsigned long)data.length, err.localizedDescription);

		if (code == 416) {
			if (end >= start) {
				// Range end was beyond total file size (common on final DASH fragment). Retry requesting from start to EOF.
				NSMutableURLRequest *openReq = [NSMutableURLRequest requestWithURL:remoteURL
				                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
				                                                   timeoutInterval:20.0];
				openReq.HTTPShouldHandleCookies = NO;
				[openReq setValue:[NSString stringWithFormat:@"bytes=%lld-", start] forHTTPHeaderField:@"Range"];
				[openReq setValue:MLRelayUpstreamUserAgent forHTTPHeaderField:@"User-Agent"];
				NSHTTPURLResponse *openResp = nil;
				NSError *openErr = nil;
				NSData *openData = [MLTLSTrustManager sendSynchronousRequest:openReq returningResponse:&openResp error:&openErr];
				if (openData.length > 0 && (openResp.statusCode == 200 || openResp.statusCode == 206 || openResp.statusCode == 0)) {
					if (outResp) *outResp = openResp;
					return openData;
				}
			}
			break;
		}
	}

	if (outResp) {
		*outResp = lastResp;
	}
	return nil;
}

- (void)handleClient:(int)clientFD
{
	char buf[4096];
	ssize_t bytesRead = read(clientFD, buf, sizeof(buf) - 1);
	if (bytesRead <= 0) {
		close(clientFD);
		return;
	}
	buf[bytesRead] = '\0';
	NSString *reqStr = [NSString stringWithCString:buf encoding:NSASCIIStringEncoding];
	if (!reqStr.length) {
		close(clientFD);
		return;
	}

	NSArray *lines = [reqStr componentsSeparatedByString:@"\r\n"];
	if (!lines.count) {
		close(clientFD);
		return;
	}

	NSString *reqLine = lines[0];
	NSArray *parts = [reqLine componentsSeparatedByString:@" "];
	if (parts.count < 2) {
		close(clientFD);
		return;
	}

	NSString *method = parts[0];
	BOOL isHead = [method isEqualToString:@"HEAD"];
	BOOL isGet = [method isEqualToString:@"GET"];
	if (!isGet && !isHead) {
		const char *notAllowed = "HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n";
		MLWriteAll(clientFD, notAllowed, strlen(notAllowed));
		close(clientFD);
		return;
	}

	NSString *rawPath = parts[1];
	NSURL *parsedURL = [NSURL URLWithString:rawPath];
	NSString *path = parsedURL.path ?: rawPath;
	NSRange qPos = [path rangeOfString:@"?"];
	if (qPos.location != NSNotFound) {
		path = [path substringToIndex:qPos.location];
	}

	NSArray *pathComponents = [path componentsSeparatedByString:@"/"];
	NSString *streamId = nil;
	for (NSString *comp in pathComponents) {
		if (comp.length && ![comp hasPrefix:@"stream"] && ![comp hasSuffix:@".mp4"] &&
		    ![comp hasSuffix:@".m3u8"] && ![comp isEqualToString:@"s"] && ![comp hasSuffix:@".ts"] &&
		    ![comp hasSuffix:@".aac"]) {
			streamId = comp;
			break;
		}
	}

	NSURL *remoteURL = nil;
	long long totalLength = 0;
	[_lock lock];
	if (streamId) {
		remoteURL = _urlMap[streamId];
		totalLength = [_totalLengthMap[streamId] longLongValue];
	}
	[_lock unlock];

	if (!remoteURL) {
		const char *notFound = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n";
		MLWriteAll(clientFD, notFound, strlen(notFound));
		close(clientFD);
		return;
	}

	// -------------------------------------------------------------
	// Path 1: HLS M3U8 Playlist Request (/streamId/p.m3u8)
	// -------------------------------------------------------------
	if ([path hasSuffix:@"p.m3u8"]) {
		NSString *cachedPlaylist = nil;
		[_lock lock];
		cachedPlaylist = _playlistMap[streamId];
		[_lock unlock];

		if (!cachedPlaylist.length) {
			NSHTTPURLResponse *httpResp = nil;
			NSData *headerData = [self fetchRangeStart:0 end:65535 fromURL:remoteURL httpResponse:&httpResp];

			// Ensure full sidx box is loaded if it extends beyond 64KB
			if (headerData.length >= 8) {
				const uint8_t *hBytes = (const uint8_t *)headerData.bytes;
				size_t hLen = headerData.length;
				for (size_t i = 4; i + 8 <= hLen; i++) {
					if (hBytes[i] == 's' && hBytes[i+1] == 'i' && hBytes[i+2] == 'd' && hBytes[i+3] == 'x') {
						size_t sBoxStart = i - 4;
						uint32_t bSz = ((uint32_t)hBytes[sBoxStart] << 24) | ((uint32_t)hBytes[sBoxStart+1] << 16) |
						               ((uint32_t)hBytes[sBoxStart+2] << 8) | (uint32_t)hBytes[sBoxStart+3];
						if (bSz >= 32 && sBoxStart + bSz > hLen) {
							long long neededEnd = (long long)(sBoxStart + bSz + 16);
							NSData *fullHeader = [self fetchRangeStart:0 end:neededEnd fromURL:remoteURL httpResponse:&httpResp];
							if (fullHeader.length > headerData.length) {
								headerData = fullHeader;
							}
						}
						break;
					}
				}
			}

			uint32_t timescale = 44100;
			NSArray *segments = MLParseSidxSegments(headerData, &timescale);

			if (segments.count > 0) {
				double maxDur = 10.0;
				double totalAudioDur = 0.0;
				for (MLSidxSegment *s in segments) {
					if (s.duration > maxDur) maxDur = s.duration;
					totalAudioDur += s.duration;
				}
				NSMutableString *m3u8 = [NSMutableString stringWithFormat:
					@"#EXTM3U\n"
					@"#EXT-X-VERSION:3\n"
					@"#EXT-X-INDEPENDENT-SEGMENTS\n"
					@"#EXT-X-TARGETDURATION:%ld\n"
					@"#EXT-X-MEDIA-SEQUENCE:0\n"
					@"#EXT-X-PLAYLIST-TYPE:VOD\n",
					(long)ceil(maxDur)];

				for (NSUInteger i = 0; i < segments.count; i++) {
					MLSidxSegment *s = segments[i];
					[m3u8 appendFormat:@"#EXTINF:%.3f,\n/%@/s/%lu.ts\n", s.duration, streamId, (unsigned long)i];
				}
				[m3u8 appendString:@"#EXT-X-ENDLIST\n"];

				cachedPlaylist = [m3u8 copy];
				NSLog(@"[MLStreamRelay] Generated HLS playlist for %@ with %lu segments, maxDur: %.2f", streamId, (unsigned long)segments.count, maxDur);
				[_lock lock];
				_segmentsMap[streamId] = segments;
				_timescaleMap[streamId] = @(timescale);
				_playlistMap[streamId] = cachedPlaylist;
				if (totalAudioDur > 0.0) {
					_durationMap[streamId] = @(totalAudioDur);
				}
				[_lock unlock];
			} else {
				NSLog(@"[MLStreamRelay] Failed to parse sidx segments for %@ (header bytes: %lu, http: %ld)",
				      streamId, (unsigned long)headerData.length, (long)httpResp.statusCode);
			}
		}

		if (cachedPlaylist.length > 0) {
			NSData *plData = [cachedPlaylist dataUsingEncoding:NSUTF8StringEncoding];
			NSString *respHdr = [NSString stringWithFormat:
				@"HTTP/1.1 200 OK\r\n"
				@"Content-Type: application/vnd.apple.mpegurl\r\n"
				@"Content-Length: %lu\r\n"
				@"Connection: close\r\n\r\n",
				(unsigned long)plData.length];
			NSData *hdrData = [respHdr dataUsingEncoding:NSASCIIStringEncoding];
			MLWriteAll(clientFD, hdrData.bytes, hdrData.length);
			if (!isHead) {
				MLWriteAll(clientFD, plData.bytes, plData.length);
			}
		} else {
			const char *notFound = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n";
			MLWriteAll(clientFD, notFound, strlen(notFound));
		}
		close(clientFD);
		return;
	}

	// -------------------------------------------------------------
	// Path 2: HLS TS Segment Request (/streamId/s/<index>.ts)
	// -------------------------------------------------------------
	if ([path rangeOfString:@"/s/"].location != NSNotFound && [path hasSuffix:@".ts"]) {
		NSInteger segIndex = -1;
		for (NSString *comp in pathComponents) {
			if ([comp hasSuffix:@".ts"]) {
				segIndex = [[comp stringByDeletingPathExtension] integerValue];
				break;
			}
		}

		NSArray *segments = nil;
		uint32_t timescale = 44100;
		[_lock lock];
		segments = _segmentsMap[streamId];
		timescale = [_timescaleMap[streamId] unsignedIntValue] ?: 44100;
		[_lock unlock];

		if (segments && segIndex >= 0 && (NSUInteger)segIndex < segments.count) {
			MLSidxSegment *targetSeg = segments[(NSUInteger)segIndex];
			NSHTTPURLResponse *httpResp = nil;
			NSData *rawFragData = [self fetchRangeStart:targetSeg.startOffset
			                                        end:targetSeg.endOffset
			                                    fromURL:remoteURL
			                               httpResponse:&httpResp];

			double curTime = 0.0;
			for (NSInteger j = 0; j < segIndex; j++) {
				curTime += ((MLSidxSegment *)segments[(NSUInteger)j]).duration;
			}
			uint64_t startPts = (uint64_t)(curTime * 90000.0);

			NSData *tsData = MLMuxMp4FragmentToTs(rawFragData, startPts, timescale, 2);
			if (tsData.length > 0) {
				NSString *respHdr = [NSString stringWithFormat:
					@"HTTP/1.1 200 OK\r\n"
					@"Content-Type: video/mp2t\r\n"
					@"Content-Length: %lu\r\n"
					@"Accept-Ranges: bytes\r\n"
					@"Connection: close\r\n\r\n",
					(unsigned long)tsData.length];
				NSData *hdrData = [respHdr dataUsingEncoding:NSASCIIStringEncoding];
				MLWriteAll(clientFD, hdrData.bytes, hdrData.length);
				if (!isHead) {
					MLWriteAll(clientFD, tsData.bytes, tsData.length);
				}
				NSLog(@"[MLStreamRelay] Served TS segment %ld for %@: %lu bytes", (long)segIndex, streamId, (unsigned long)tsData.length);
				close(clientFD);
				return;
			} else {
				NSLog(@"[MLStreamRelay] Failed to mux TS segment %ld for %@ (raw bytes: %lu, http: %ld)",
				      (long)segIndex, streamId, (unsigned long)rawFragData.length, (long)httpResp.statusCode);
			}
		}

		const char *notFound = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n";
		MLWriteAll(clientFD, notFound, strlen(notFound));
		close(clientFD);
		return;
	}

	// -------------------------------------------------------------
	// Path 2.5: Progressive ADTS AAC Streaming (/streamId/stream.aac) (iOS 6)
	// -------------------------------------------------------------
	if ([path hasSuffix:@"stream.aac"] || [path hasSuffix:@".aac"]) {
		double startSec = 0.0;
		BOOL hasStartSec = NO;
		NSRange qRange = [rawPath rangeOfString:@"startSec="];
		if (qRange.location != NSNotFound) {
			NSString *secStr = [rawPath substringFromIndex:qRange.location + 9];
			NSRange ampRange = [secStr rangeOfString:@"&"];
			if (ampRange.location != NSNotFound) {
				secStr = [secStr substringToIndex:ampRange.location];
			}
			startSec = [secStr doubleValue];
			hasStartSec = YES;
		}

		BOOL isAlreadyFinished = NO;
		[_lock lock];
		isAlreadyFinished = [_finishedMap[streamId] boolValue];
		[_lock unlock];

		if (!hasStartSec && isAlreadyFinished) {
			NSLog(@"[MLStreamRelay] Stream %@ already completed. Serving EOF to prevent looping.", streamId);
			NSString *eofHdr = @"HTTP/1.1 200 OK\r\n"
			                    @"Content-Type: audio/aac\r\n"
			                    @"Content-Length: 0\r\n"
			                    @"Connection: close\r\n\r\n";
			NSData *eofData = [eofHdr dataUsingEncoding:NSASCIIStringEncoding];
			MLWriteAll(clientFD, eofData.bytes, eofData.length);
			shutdown(clientFD, SHUT_WR);
			char drainBuf[256];
			while (read(clientFD, drainBuf, sizeof(drainBuf)) > 0) {}
			close(clientFD);
			return;
		}

		if (hasStartSec) {
			[_lock lock];
			[_finishedMap removeObjectForKey:streamId];
			[_highestSegMap removeObjectForKey:streamId];
			[_lock unlock];
		}

		NSArray *segments = nil;
		uint32_t timescale = 44100;
		[_lock lock];
		segments = _segmentsMap[streamId];
		timescale = [_timescaleMap[streamId] unsignedIntValue] ?: 44100;
		[_lock unlock];

		if (!segments.count) {
			NSHTTPURLResponse *httpResp = nil;
			NSData *headerData = [self fetchRangeStart:0 end:65535 fromURL:remoteURL httpResponse:&httpResp];

			// Ensure full sidx box is loaded if it extends beyond 64KB
			if (headerData.length >= 8) {
				const uint8_t *hBytes = (const uint8_t *)headerData.bytes;
				size_t hLen = headerData.length;
				for (size_t i = 4; i + 8 <= hLen; i++) {
					if (hBytes[i] == 's' && hBytes[i+1] == 'i' && hBytes[i+2] == 'd' && hBytes[i+3] == 'x') {
						size_t sBoxStart = i - 4;
						uint32_t bSz = ((uint32_t)hBytes[sBoxStart] << 24) | ((uint32_t)hBytes[sBoxStart+1] << 16) |
						               ((uint32_t)hBytes[sBoxStart+2] << 8) | (uint32_t)hBytes[sBoxStart+3];
						if (bSz >= 32 && sBoxStart + bSz > hLen) {
							long long neededEnd = (long long)(sBoxStart + bSz + 16);
							NSData *fullHeader = [self fetchRangeStart:0 end:neededEnd fromURL:remoteURL httpResponse:&httpResp];
							if (fullHeader.length > headerData.length) {
								headerData = fullHeader;
							}
						}
						break;
					}
				}
			}

			segments = MLParseSidxSegments(headerData, &timescale);
			if (segments.count > 0) {
				double totalAudioDur = 0.0;
				for (MLSidxSegment *s in segments) {
					totalAudioDur += s.duration;
				}
				[_lock lock];
				_segmentsMap[streamId] = segments;
				_timescaleMap[streamId] = @(timescale);
				if (totalAudioDur > 0.0) {
					_durationMap[streamId] = @(totalAudioDur);
				}
				[_lock unlock];
			}
		}

		if (!segments.count) {
			NSLog(@"[MLStreamRelay] No sidx segments found for AAC stream %@", streamId);
			const char *notFound = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n";
			MLWriteAll(clientFD, notFound, strlen(notFound));
			close(clientFD);
			return;
		}

		NSUInteger startSegIndex = 0;
		if (startSec > 0.0) {
			double accTime = 0.0;
			for (NSUInteger i = 0; i < segments.count; i++) {
				MLSidxSegment *seg = segments[i];
				if (accTime + seg.duration > startSec) {
					startSegIndex = i;
					break;
				}
				accTime += seg.duration;
			}
		}

		NSString *respHdr = @"HTTP/1.1 200 OK\r\n"
		                    @"Content-Type: audio/aac\r\n"
		                    @"Accept-Ranges: none\r\n"
		                    @"Connection: close\r\n\r\n";
		NSData *hdrData = [respHdr dataUsingEncoding:NSASCIIStringEncoding];
		if (!MLWriteAll(clientFD, hdrData.bytes, hdrData.length)) {
			close(clientFD);
			return;
		}
		if (isHead) {
			close(clientFD);
			return;
		}

		NSLog(@"[MLStreamRelay] Streaming progressive ADTS AAC for %@ (startSeg=%lu/%lu, startSec=%.2f)",
		      streamId, (unsigned long)startSegIndex, (unsigned long)segments.count, startSec);

		BOOL successfullyFinished = NO;
		for (NSUInteger i = startSegIndex; i < segments.count; i++) {
			MLSidxSegment *targetSeg = segments[i];
			NSHTTPURLResponse *httpResp = nil;
			NSData *rawFragData = nil;
			for (int fragAttempt = 0; fragAttempt < 3; fragAttempt++) {
				rawFragData = [self fetchRangeStart:targetSeg.startOffset
				                                end:targetSeg.endOffset
				                            fromURL:remoteURL
				                       httpResponse:&httpResp];
				if (rawFragData.length > 0) {
					break;
				}
				usleep(250000);
			}
			if (!rawFragData.length) {
				NSLog(@"[MLStreamRelay] Failed to fetch fragment %lu after 3 attempts for AAC stream %@", (unsigned long)i, streamId);
				break;
			}

			NSData *adtsData = MLExtractAdtsFromMp4Fragment(rawFragData, timescale, 2);
			if (!adtsData.length) {
				NSLog(@"[MLStreamRelay] Failed to extract ADTS from fragment %lu for AAC stream %@", (unsigned long)i, streamId);
				break;
			}

			if (!MLWriteAll(clientFD, adtsData.bytes, adtsData.length)) {
				// Client closed connection (e.g. paused, skipped, or seeked)
				break;
			}

			[_lock lock];
			_highestSegMap[streamId] = @(i);
			[_lock unlock];

			if (i == segments.count - 1) {
				successfullyFinished = YES;
			}
		}

		[_lock lock];
		NSNumber *highestNum = _highestSegMap[streamId];
		if (successfullyFinished || (highestNum && [highestNum unsignedIntegerValue] + 1 >= segments.count)) {
			_finishedMap[streamId] = @YES;
			NSLog(@"[MLStreamRelay] Stream %@ successfully marked finished (%lu segments)", streamId, (unsigned long)segments.count);
		}
		[_lock unlock];

		shutdown(clientFD, SHUT_WR);
		char drainBuf[256];
		while (read(clientFD, drainBuf, sizeof(drainBuf)) > 0) {}
		close(clientFD);
		return;
	}

	// -------------------------------------------------------------
	// Path 3: Progressive MP4 Streaming (/streamId/stream.mp4) (iOS 7+)
	// -------------------------------------------------------------
	long long rangeStart = 0;
	long long rangeEnd = -1;

	for (NSString *line in lines) {
		if ([line hasPrefix:@"Range:"] || [line hasPrefix:@"range:"]) {
			NSRange bytesRange = [line rangeOfString:@"bytes="];
			if (bytesRange.location != NSNotFound) {
				NSString *val = [line substringFromIndex:bytesRange.location + bytesRange.length];
				NSArray *rngParts = [val componentsSeparatedByString:@"-"];
				if (rngParts.count > 0 && [rngParts[0] length]) {
					rangeStart = [rngParts[0] longLongValue];
				}
				if (rngParts.count > 1 && [rngParts[1] length]) {
					rangeEnd = [rngParts[1] longLongValue];
				}
			}
			break;
		}
	}

	if (totalLength == 0) {
		NSHTTPURLResponse *httpResp = nil;
		NSData *probeData = [self fetchRangeStart:0 end:1 fromURL:remoteURL httpResponse:&httpResp];
		if (probeData.length > 0 && httpResp) {
			NSString *cr = [httpResp.allHeaderFields objectForKey:@"Content-Range"] ?: [httpResp.allHeaderFields objectForKey:@"content-range"];
			long long parsedTotal = MLParseTotalFromContentRange(cr);
			if (parsedTotal > 0) {
				[_lock lock];
				_totalLengthMap[streamId] = @(parsedTotal);
				totalLength = parsedTotal;
				[_lock unlock];
			}
		} else {
			const char *badGateway = "HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n";
			MLWriteAll(clientFD, badGateway, strlen(badGateway));
			close(clientFD);
			return;
		}
	}

	NSString *contentType = @"audio/mp4";

	if (isHead) {
		NSString *respHdr = [NSString stringWithFormat:
			@"HTTP/1.1 200 OK\r\n"
			@"Content-Type: %@\r\n"
			@"Content-Length: %lld\r\n"
			@"Accept-Ranges: bytes\r\n"
			@"Connection: close\r\n\r\n",
			contentType,
			totalLength];
		NSData *hdrData = [respHdr dataUsingEncoding:NSASCIIStringEncoding];
		MLWriteAll(clientFD, hdrData.bytes, hdrData.length);
		close(clientFD);
		return;
	}

	long long fetchStart = rangeStart;
	long long fetchEnd = rangeEnd;
	if (fetchEnd < 0) {
		fetchEnd = (totalLength > 0) ? (totalLength - 1) : -1;
	}
	if (totalLength > 0 && fetchEnd >= totalLength) {
		fetchEnd = totalLength - 1;
	}

	long long expectedLength = (fetchEnd >= fetchStart) ? (fetchEnd - fetchStart + 1) : 0;
	long long repTotal = (totalLength > 0) ? totalLength : (fetchEnd + 1);

	// Always send 206 Partial Content with Content-Range for progressive media streaming
	NSString *respHdr = [NSString stringWithFormat:
		@"HTTP/1.1 206 Partial Content\r\n"
		@"Content-Type: %@\r\n"
		@"Content-Length: %lld\r\n"
		@"Content-Range: bytes %lld-%lld/%lld\r\n"
		@"Accept-Ranges: bytes\r\n"
		@"Connection: close\r\n\r\n",
		contentType,
		expectedLength, fetchStart, fetchEnd, repTotal];

	NSData *hdrData = [respHdr dataUsingEncoding:NSASCIIStringEncoding];
	if (!MLWriteAll(clientFD, hdrData.bytes, hdrData.length)) {
		close(clientFD);
		return;
	}

	long long current = fetchStart;
	while (fetchEnd < 0 || current <= fetchEnd) {
		long long nextChunkEnd = current + MLRelayDefaultChunkSize - 1;
		if (fetchEnd >= 0 && nextChunkEnd > fetchEnd) {
			nextChunkEnd = fetchEnd;
		}

		NSHTTPURLResponse *httpResp = nil;
		NSData *chunkData = [self fetchRangeStart:current
		                                      end:nextChunkEnd
		                                  fromURL:remoteURL
		                             httpResponse:&httpResp];
		if (!chunkData.length) {
			NSLog(@"[MLStreamRelay] Stream %@ interrupted at byte %lld/%lld (HTTP %ld)",
			      streamId, current, fetchEnd, (long)httpResp.statusCode);
			break;
		}

		if (!MLWriteAll(clientFD, chunkData.bytes, chunkData.length)) {
			break;
		}

		current += (long long)chunkData.length;
	}

	close(clientFD);
}

- (NSTimeInterval)durationForStreamURL:(NSURL *)url
{
	if (!url) return 0;
	NSString *streamId = nil;
	NSArray *comps = [url.path componentsSeparatedByString:@"/"];
	for (NSString *comp in comps) {
		if (comp.length && ![comp hasPrefix:@"stream"] && ![comp hasSuffix:@".mp4"] &&
		    ![comp hasSuffix:@".m3u8"] && ![comp isEqualToString:@"s"] && ![comp hasSuffix:@".ts"] &&
		    ![comp hasSuffix:@".aac"]) {
			streamId = comp;
			break;
		}
	}
	if (!streamId) return 0;
	[_lock lock];
	NSTimeInterval dur = [_durationMap[streamId] doubleValue];
	[_lock unlock];
	return dur;
}

- (BOOL)isStreamFinishedForURL:(NSURL *)url
{
	if (!url) return NO;
	NSString *streamId = nil;
	NSArray *comps = [url.path componentsSeparatedByString:@"/"];
	for (NSString *comp in comps) {
		if (comp.length && ![comp hasPrefix:@"stream"] && ![comp hasSuffix:@".mp4"] &&
		    ![comp hasSuffix:@".m3u8"] && ![comp isEqualToString:@"s"] && ![comp hasSuffix:@".ts"] &&
		    ![comp hasSuffix:@".aac"]) {
			streamId = comp;
			break;
		}
	}
	if (!streamId) return NO;
	[_lock lock];
	BOOL fin = [_finishedMap[streamId] boolValue];
	[_lock unlock];
	return fin;
}

@end
