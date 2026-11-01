#import "MLEqualizerManager.h"
#import "MLPlaybackManager.h"
#import <MediaToolbox/MTAudioProcessingTap.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#import <pthread.h>
#import <math.h>
#import <dlfcn.h>

NSString *const MLEqualizerDidChangeNotification = @"MLEqualizerDidChangeNotification";

// Runtime vDSP_biquad availability (iOS 8+ only; iOS 6/7 lack symbols)
static BOOL MLvDSPBiquadAvailable = NO;
static dispatch_once_t MLvDSPBiquadOnceToken;

static inline BOOL MLEnsureVDSPBiquadAvailable(void) {
	dispatch_once(&MLvDSPBiquadOnceToken, ^{
		void *handle = dlopen("/System/Library/Frameworks/Accelerate.framework/Accelerate", RTLD_LAZY | RTLD_LOCAL);
		if (handle) {
			MLvDSPBiquadAvailable = (dlsym(handle, "vDSP_biquad_CreateSetup") != NULL);
			dlclose(handle);
		}
	});
	return MLvDSPBiquadAvailable;
}

// ============================================================================
// Manual Biquad Implementation (Direct Form II Transposed)
// Used on iOS 6/7 where vDSP_biquad is unavailable.
// Coefficients layout per section: [b0, b1, b2, a1, a2] (a0 normalized to 1.0)
// ============================================================================

typedef struct {
	double coeffs[5 * ML_EQ_NUM_BANDS]; // 5 coeffs per band: b0,b1,b2,a1,a2
	float delays[2][2 * ML_EQ_NUM_BANDS]; // delay lines per channel: [w1, w2] per section
} MLManualBiquadState;

static inline void MLManualBiquadInit(MLManualBiquadState *state, const double *coeffs) {
	if (!state) return;
	memcpy(state->coeffs, coeffs, sizeof(double) * 5 * ML_EQ_NUM_BANDS);
	memset(state->delays, 0, sizeof(state->delays));
}

static inline void MLManualBiquadProcessInPlace(MLManualBiquadState *state,
                                                float *samples, uint32_t numChannels,
                                                uint32_t frames) {
	if (!state) return;
	
	for (uint32_t ch = 0; ch < numChannels; ch++) {
		float *data = samples + ch;
		float *delay = state->delays[ch];
		
		for (uint32_t n = 0; n < frames; n++) {
			float x = data[n * numChannels];
			float y = x;
			
			for (int band = 0; band < ML_EQ_NUM_BANDS; band++) {
				const double *c = &state->coeffs[band * 5];
				double b0 = c[0], b1 = c[1], b2 = c[2];
				double a1 = c[3], a2 = c[4];
				
				double w = y - a1 * delay[band * 2] - a2 * delay[band * 2 + 1];
				y = (float)(b0 * w + b1 * delay[band * 2] + b2 * delay[band * 2 + 1]);
				
				delay[band * 2 + 1] = delay[band * 2];
				delay[band * 2] = (float)w;
			}
			
			data[n * numChannels] = y;
		}
	}
}

static NSString *const kPrefEqualizerEnabled = @"ml_eq_enabled";
static NSString *const kPrefEqualizerPresetId = @"ml_eq_preset_id";
static NSString *const kPrefEqualizerBandValues = @"ml_eq_band_values";

#define ML_EQ_SCOPE_SIZE 1024

// Exact 10-band ISO frequencies used by TuneShell
static const float kEQFrequencies[ML_EQ_NUM_BANDS] = {
	31.0f, 62.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f
};

// 1-octave Q factor for 10-band ISO equalizer
static const float kEQDefaultQ = 1.41421356f; // sqrt(2)

typedef struct {
	void *manager;
	pthread_mutex_t lock;
	BOOL enabled;
	BOOL allBandsFlat;
	float preampGain;
	double sampleRate;
	uint32_t channels;
	BOOL isFloat;
	BOOL isInterleaved;
	vDSP_biquad_Setup biquadSetup;
	MLManualBiquadState manualBiquad; // iOS 6/7 fallback
	BOOL useManualBiquad;
	float delays[2][2 * ML_EQ_NUM_BANDS + 2];
	float scopeBuffer[ML_EQ_SCOPE_SIZE];
	uint32_t scopeWritePos;
} MLEqualizerTapStorage;

@implementation MLEQPreset

+ (instancetype)presetWithId:(NSString *)presetId nameKey:(NSString *)nameKey gains:(NSArray *)gains
{
	MLEQPreset *p = [[MLEQPreset alloc] init];
	p.presetId = presetId;
	p.nameKey = nameKey;
	p.bandGains = gains;
	return p;
}

@end

@interface MLEqualizerManager () {
	float _bandGains[ML_EQ_NUM_BANDS];
	NSRecursiveLock *_lock;
	NSMutableSet *_activeStorages; // set of [NSValue valueWithPointer:storage]
	NSArray *_presetList;
	MLEqualizerTapStorage _coreAudioStorage;
}

- (void)registerTapStorage:(MLEqualizerTapStorage *)storage;
- (void)unregisterTapStorage:(MLEqualizerTapStorage *)storage;
- (void)updateStorageCoefficients:(MLEqualizerTapStorage *)storage;

@end

// MARK: - C Audio Processing Tap Callbacks

static void tapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut)
{
	MLEqualizerTapStorage *storage = (MLEqualizerTapStorage *)calloc(1, sizeof(MLEqualizerTapStorage));
	if (!storage) return;

	storage->manager = clientInfo;
	pthread_mutex_init(&storage->lock, NULL);
	storage->sampleRate = 0.0; // Will be set in tapPrepare; 0 = not ready
	storage->channels = 2;
	storage->isFloat = YES;
	storage->isInterleaved = NO;
	*tapStorageOut = storage;

	MLEqualizerManager *mgr = (__bridge MLEqualizerManager *)clientInfo;
	if (mgr) {
		[mgr registerTapStorage:storage];
	}
	NSLog(@"[MLEQ] tapInit: sampleRate=%.0f, channels=%u, isFloat=%d, isInterleaved=%d",
	      storage->sampleRate, storage->channels, storage->isFloat, storage->isInterleaved);
}

static void tapFinalize(MTAudioProcessingTapRef tap)
{
	MLEqualizerTapStorage *storage = (MLEqualizerTapStorage *)MTAudioProcessingTapGetStorage(tap);
	if (storage) {
		MLEqualizerManager *mgr = (__bridge MLEqualizerManager *)storage->manager;
		if (mgr) {
			[mgr unregisterTapStorage:storage];
		}
		pthread_mutex_lock(&storage->lock);
		if (storage->biquadSetup) {
			vDSP_biquad_DestroySetup(storage->biquadSetup);
			storage->biquadSetup = NULL;
		}
		pthread_mutex_unlock(&storage->lock);
		pthread_mutex_destroy(&storage->lock);
		free(storage);
	}
}

static void tapPrepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *processingFormat)
{
	MLEqualizerTapStorage *storage = (MLEqualizerTapStorage *)MTAudioProcessingTapGetStorage(tap);
	if (!storage || !processingFormat) return;

	pthread_mutex_lock(&storage->lock);
	storage->sampleRate = (processingFormat->mSampleRate > 0) ? processingFormat->mSampleRate : 44100.0;
	storage->channels = processingFormat->mChannelsPerFrame;
	storage->isInterleaved = !(processingFormat->mFormatFlags & kAudioFormatFlagIsNonInterleaved);
	storage->isFloat = (processingFormat->mFormatFlags & kAudioFormatFlagIsFloat) || (processingFormat->mBitsPerChannel == 32);
	memset(storage->delays, 0, sizeof(storage->delays));
	pthread_mutex_unlock(&storage->lock);

	NSLog(@"[MLEQ] tapPrepare: sampleRate=%.0f, channels=%u, formatID=0x%X, formatFlags=0x%X, bitsPerChan=%u, bytesPerFrame=%u",
	      storage->sampleRate, storage->channels, (unsigned int)processingFormat->mFormatID,
	      (unsigned int)processingFormat->mFormatFlags, (unsigned int)processingFormat->mBitsPerChannel,
	      (unsigned int)processingFormat->mBytesPerFrame);

	MLEqualizerManager *mgr = (__bridge MLEqualizerManager *)storage->manager;
	if (mgr) {
		[mgr updateStorageCoefficients:storage];
	}
}

static void tapUnprepare(MTAudioProcessingTapRef tap)
{
	MLEqualizerTapStorage *storage = (MLEqualizerTapStorage *)MTAudioProcessingTapGetStorage(tap);
	if (storage) {
		memset(storage->delays, 0, sizeof(storage->delays));
	}
}

static void tapProcess(MTAudioProcessingTapRef tap,
                       CMItemCount numberFrames,
                       MTAudioProcessingTapFlags flags,
                       AudioBufferList *bufferListInOut,
                       CMItemCount *numberFramesOut,
                       MTAudioProcessingTapFlags *flagsOut)
{
	OSStatus status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, NULL, numberFramesOut);
	if (status != noErr || !numberFramesOut || *numberFramesOut == 0) {
		return;
	}

	MLEqualizerTapStorage *storage = (MLEqualizerTapStorage *)MTAudioProcessingTapGetStorage(tap);
	if (!storage) {
		return;
	}

	if (flags & kMTAudioProcessingTapFlag_StartOfStream) {
		memset(storage->delays, 0, sizeof(storage->delays));
		NSLog(@"[MLEqualizer] Started processing stream: sampleRate=%.0f, channels=%u, enabled=%d",
		      storage->sampleRate, storage->channels, storage->enabled);
	}

	CMItemCount frames = *numberFramesOut;
	if (frames <= 0) return;

	// Use mutex lock to guarantee that coefficients and buffers are never skipped
	pthread_mutex_lock(&storage->lock);

	// If sampleRate not ready, or EQ disabled/flat, pass through
	if (storage->sampleRate == 0.0 || !storage->enabled || storage->allBandsFlat || (!storage->useManualBiquad && !storage->biquadSetup)) {
		static uint32_t sLogCounter = 0;
		if ((sLogCounter++ % 150) == 0) {
			NSLog(@"[MLEQ] tapProcess PASSTHROUGH: manual=%d enabled=%d allFlat=%d biquadSetup=%p",
			      storage->useManualBiquad, storage->enabled, storage->allBandsFlat, storage->biquadSetup);
		}
		// Pass-through: copy recent audio to scope buffer for visualizer even when EQ is off
		if (storage->isFloat && bufferListInOut->mNumberBuffers > 0) {
			float *src = (float *)bufferListInOut->mBuffers[0].mData;
			if (src) {
				NSUInteger copyCount = MIN((NSUInteger)frames, (NSUInteger)ML_EQ_SCOPE_SIZE);
				if (storage->isInterleaved) {
					uint32_t nc = storage->channels > 0 ? storage->channels : 1;
					for (NSUInteger k = 0; k < copyCount; k++) {
						storage->scopeBuffer[k] = src[k * nc];
					}
				} else {
					memcpy(storage->scopeBuffer, src, copyCount * sizeof(float));
				}
			}
		}
		pthread_mutex_unlock(&storage->lock);
		return;
	}

	static uint32_t sProcLogCounter = 0;
	if ((sProcLogCounter++ % 150) == 0) {
		NSLog(@"[MLEQ] tapProcess ACTIVE: processing %ld frames (preamp=%.2f)",
		      (long)frames, storage->preampGain);
	}

	float preamp = storage->preampGain;
	float clipLow = -1.0f;
	float clipHigh = 1.0f;

	if (storage->isFloat) {
		if (storage->isInterleaved) {
			uint32_t numChannels = storage->channels;
			if (numChannels > 2) numChannels = 2;
			float *samples = (float *)bufferListInOut->mBuffers[0].mData;
			if (samples) {
				// 1. Preamp Scaling
				vDSP_Length totalSamples = frames * numChannels;
				vDSP_vsmul(samples, 1, &preamp, samples, 1, totalSamples);

				// 2. 10-Band Cascaded Biquad Filtering
				if (storage->useManualBiquad) {
					// Manual biquad (iOS 6/7) - process in-place
					MLManualBiquadProcessInPlace(&storage->manualBiquad, samples, numChannels, frames);
				} else {
					// vDSP (iOS 8+)
					vDSP_biquad(storage->biquadSetup, storage->delays[0], samples, numChannels, samples, numChannels, frames);
					if (numChannels > 1) {
						vDSP_biquad(storage->biquadSetup, storage->delays[1], samples + 1, numChannels, samples + 1, numChannels, frames);
					}
				}

				// 3. Saturation Clamping
				vDSP_vclip(samples, 1, &clipLow, &clipHigh, samples, 1, totalSamples);

				// 4. Update Scope Buffer for UI Waveform Visualizer
				NSUInteger copyCount = MIN((NSUInteger)frames, (NSUInteger)ML_EQ_SCOPE_SIZE);
				for (NSUInteger k = 0; k < copyCount; k++) {
					storage->scopeBuffer[k] = samples[k * numChannels];
				}
			}
		} else {
			// Non-interleaved stereo (Standard on iOS MTAudioProcessingTap)
			uint32_t numBuffers = bufferListInOut->mNumberBuffers;
			if (numBuffers > 2) numBuffers = 2;

			for (uint32_t ch = 0; ch < numBuffers; ch++) {
				float *samples = (float *)bufferListInOut->mBuffers[ch].mData;
				if (!samples) continue;

				// 1. Preamp Scaling
				vDSP_vsmul(samples, 1, &preamp, samples, 1, frames);

				// 2. 10-Band Cascaded Biquad Filtering
				if (storage->useManualBiquad) {
					MLManualBiquadProcessInPlace(&storage->manualBiquad, samples, 1, frames);
				} else {
					vDSP_biquad(storage->biquadSetup, storage->delays[ch], samples, 1, samples, 1, frames);
				}

				// 3. Saturation Clamping
				vDSP_vclip(samples, 1, &clipLow, &clipHigh, samples, 1, frames);

				if (ch == 0) {
					NSUInteger copyCount = MIN((NSUInteger)frames, (NSUInteger)ML_EQ_SCOPE_SIZE);
					memcpy(storage->scopeBuffer, samples, copyCount * sizeof(float));
				}
			}
		}
	} else {
		// 16-bit integer PCM fallback (SIMD converted to float and back)
		uint32_t numBuffers = storage->isInterleaved ? 1 : bufferListInOut->mNumberBuffers;
		if (numBuffers > 2) numBuffers = 2;

		for (uint32_t ch = 0; ch < numBuffers; ch++) {
			int16_t *intSamples = (int16_t *)bufferListInOut->mBuffers[ch].mData;
			if (!intSamples) continue;
			vDSP_Length count = storage->isInterleaved ? frames * storage->channels : frames;
			if (count == 0) continue;

			float stackBuf[1024];
			float *floatBuffer = (count <= 1024) ? stackBuf : (float *)malloc(count * sizeof(float));
			if (!floatBuffer) continue;

			// int16 -> float
			vDSP_vflt16(intSamples, 1, floatBuffer, 1, count);
			float scale = preamp / 32768.0f;
			vDSP_vsmul(floatBuffer, 1, &scale, floatBuffer, 1, count);

			if (storage->isInterleaved) {
				uint32_t nc = storage->channels > 2 ? 2 : storage->channels;
				if (storage->useManualBiquad) {
					MLManualBiquadProcessInPlace(&storage->manualBiquad, floatBuffer, nc, frames);
				} else {
					vDSP_biquad(storage->biquadSetup, storage->delays[0], floatBuffer, nc, floatBuffer, nc, frames);
					if (nc > 1) {
						vDSP_biquad(storage->biquadSetup, storage->delays[1], floatBuffer + 1, nc, floatBuffer + 1, nc, frames);
					}
				}
				NSUInteger copyCount = MIN((NSUInteger)frames, (NSUInteger)ML_EQ_SCOPE_SIZE);
				for (NSUInteger k = 0; k < copyCount; k++) {
					storage->scopeBuffer[k] = floatBuffer[k * nc];
				}
			} else {
				if (storage->useManualBiquad) {
					MLManualBiquadProcessInPlace(&storage->manualBiquad, floatBuffer, 1, frames);
				} else {
					vDSP_biquad(storage->biquadSetup, storage->delays[ch], floatBuffer, 1, floatBuffer, 1, frames);
				}
				if (ch == 0) {
					NSUInteger copyCount = MIN((NSUInteger)frames, (NSUInteger)ML_EQ_SCOPE_SIZE);
					memcpy(storage->scopeBuffer, floatBuffer, copyCount * sizeof(float));
				}
			}

			vDSP_vclip(floatBuffer, 1, &clipLow, &clipHigh, floatBuffer, 1, count);
			float unscale = 32767.0f;
			vDSP_vsmul(floatBuffer, 1, &unscale, floatBuffer, 1, count);
			vDSP_vfix16(floatBuffer, 1, intSamples, 1, count);

			if (floatBuffer != stackBuf) {
				free(floatBuffer);
			}
		}
	}

	pthread_mutex_unlock(&storage->lock);
}

// MARK: - Manager Implementation

@implementation MLEqualizerManager

+ (instancetype)sharedManager
{
	static MLEqualizerManager *sMgr = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sMgr = [[MLEqualizerManager alloc] init];
	});
	return sMgr;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_lock = [[NSRecursiveLock alloc] init];
		_activeStorages = [[NSMutableSet alloc] init];

		[self setupPresets];

		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		_enabled = [ud boolForKey:kPrefEqualizerEnabled];
		_currentPresetId = [ud stringForKey:kPrefEqualizerPresetId] ?: @"flat";

		NSArray *savedGains = [ud arrayForKey:kPrefEqualizerBandValues];
		if (savedGains.count == ML_EQ_NUM_BANDS) {
			for (int i = 0; i < ML_EQ_NUM_BANDS; i++) {
				_bandGains[i] = [savedGains[i] floatValue];
			}
		} else {
			for (int i = 0; i < ML_EQ_NUM_BANDS; i++) {
				_bandGains[i] = 0.0f;
			}
		}

		pthread_mutex_init(&_coreAudioStorage.lock, NULL);
		_coreAudioStorage.manager = (__bridge void *)self;
		_coreAudioStorage.isInterleaved = YES;
		_coreAudioStorage.isFloat = YES;
		_coreAudioStorage.channels = 2;
		_coreAudioStorage.sampleRate = 44100.0;
		_coreAudioStorage.enabled = _enabled;
		_coreAudioStorage.allBandsFlat = YES;
		_coreAudioStorage.preampGain = 1.0f;
		_coreAudioStorage.biquadSetup = NULL;
		memset(_coreAudioStorage.delays, 0, sizeof(_coreAudioStorage.delays));
		memset(_coreAudioStorage.scopeBuffer, 0, sizeof(_coreAudioStorage.scopeBuffer));
	}
	return self;
}

- (void)dealloc
{
	if (_coreAudioStorage.biquadSetup) {
		vDSP_biquad_DestroySetup(_coreAudioStorage.biquadSetup);
		_coreAudioStorage.biquadSetup = NULL;
	}
	pthread_mutex_destroy(&_coreAudioStorage.lock);
}

- (void)setupPresets
{
	_presetList = @[
		[MLEQPreset presetWithId:@"flat" nameKey:@"eq_preset_flat"
		                   gains:@[ @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f ]],
		[MLEQPreset presetWithId:@"acoustic" nameKey:@"eq_preset_acoustic"
		                   gains:@[ @5.0f, @4.9f, @3.95f, @1.05f, @2.15f, @1.75f, @3.5f, @4.1f, @3.55f, @2.15f ]],
		[MLEQPreset presetWithId:@"bass_booster" nameKey:@"eq_preset_bass_booster"
		                   gains:@[ @5.5f, @4.25f, @3.5f, @2.5f, @1.25f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f ]],
		[MLEQPreset presetWithId:@"bass_reducer" nameKey:@"eq_preset_bass_reducer"
		                   gains:@[ @-5.5f, @-4.25f, @-3.5f, @-2.5f, @-1.25f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f ]],
		[MLEQPreset presetWithId:@"classical" nameKey:@"eq_preset_classical"
		                   gains:@[ @4.75f, @3.75f, @3.0f, @2.5f, @-1.5f, @-1.5f, @0.0f, @2.25f, @3.25f, @3.75f ]],
		[MLEQPreset presetWithId:@"dance" nameKey:@"eq_preset_dance"
		                   gains:@[ @3.57f, @6.55f, @4.99f, @0.0f, @1.92f, @3.65f, @5.15f, @4.54f, @3.59f, @0.0f ]],
		[MLEQPreset presetWithId:@"deep" nameKey:@"eq_preset_deep"
		                   gains:@[ @4.95f, @3.55f, @1.75f, @1.0f, @2.85f, @2.5f, @1.45f, @-2.15f, @-3.55f, @-4.6f ]],
		[MLEQPreset presetWithId:@"electronic" nameKey:@"eq_preset_electronic"
		                   gains:@[ @4.25f, @3.8f, @1.2f, @0.0f, @-2.15f, @2.25f, @0.85f, @1.25f, @3.95f, @4.8f ]],
		[MLEQPreset presetWithId:@"hip_hop" nameKey:@"eq_preset_hip_hop"
		                   gains:@[ @5.0f, @4.25f, @1.5f, @3.0f, @-1.0f, @-1.0f, @1.5f, @-0.5f, @2.0f, @3.0f ]],
		[MLEQPreset presetWithId:@"jazz" nameKey:@"eq_preset_jazz"
		                   gains:@[ @4.0f, @3.0f, @1.5f, @2.25f, @-1.5f, @-1.5f, @0.0f, @1.5f, @3.0f, @3.75f ]],
		[MLEQPreset presetWithId:@"latin" nameKey:@"eq_preset_latin"
		                   gains:@[ @4.5f, @3.0f, @0.0f, @0.0f, @-1.5f, @-1.5f, @-1.5f, @0.0f, @3.0f, @4.5f ]],
		[MLEQPreset presetWithId:@"loudness" nameKey:@"eq_preset_loudness"
		                   gains:@[ @6.0f, @4.0f, @0.0f, @0.0f, @-2.0f, @0.0f, @-1.0f, @-5.0f, @5.0f, @1.0f ]],
		[MLEQPreset presetWithId:@"lounge" nameKey:@"eq_preset_lounge"
		                   gains:@[ @-3.0f, @-1.5f, @-0.5f, @1.5f, @4.0f, @2.5f, @0.0f, @-1.5f, @2.0f, @1.0f ]],
		[MLEQPreset presetWithId:@"piano" nameKey:@"eq_preset_piano"
		                   gains:@[ @3.0f, @2.0f, @0.0f, @2.5f, @3.0f, @1.5f, @3.5f, @4.5f, @3.0f, @3.5f ]],
		[MLEQPreset presetWithId:@"pop" nameKey:@"eq_preset_pop"
		                   gains:@[ @-1.5f, @-1.0f, @0.0f, @2.0f, @4.0f, @4.0f, @2.0f, @0.0f, @-1.0f, @-1.5f ]],
		[MLEQPreset presetWithId:@"r_b" nameKey:@"eq_preset_r_b"
		                   gains:@[ @2.62f, @6.92f, @5.65f, @1.33f, @-2.19f, @-1.5f, @2.32f, @2.65f, @3.0f, @3.75f ]],
		[MLEQPreset presetWithId:@"rock" nameKey:@"eq_preset_rock"
		                   gains:@[ @5.0f, @4.0f, @3.0f, @1.5f, @-0.5f, @-1.0f, @0.5f, @2.5f, @3.5f, @4.5f ]],
		[MLEQPreset presetWithId:@"small_speakers" nameKey:@"eq_preset_small_speakers"
		                   gains:@[ @5.5f, @4.25f, @3.5f, @2.5f, @1.25f, @0.0f, @-1.25f, @-2.5f, @-3.5f, @-4.25f ]],
		[MLEQPreset presetWithId:@"spoken_word" nameKey:@"eq_preset_spoken_word"
		                   gains:@[ @-3.46f, @-0.47f, @0.0f, @0.69f, @3.46f, @4.61f, @4.84f, @4.28f, @2.54f, @0.0f ]],
		[MLEQPreset presetWithId:@"treble_booster" nameKey:@"eq_preset_treble_booster"
		                   gains:@[ @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @1.25f, @2.5f, @3.5f, @4.25f, @5.5f ]],
		[MLEQPreset presetWithId:@"treble_reducer" nameKey:@"eq_preset_treble_reducer"
		                   gains:@[ @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @-1.25f, @-2.5f, @-3.5f, @-4.25f, @-5.5f ]],
		[MLEQPreset presetWithId:@"vocal_booster" nameKey:@"eq_preset_vocal_booster"
		                   gains:@[ @-1.5f, @-3.0f, @-3.0f, @1.5f, @3.75f, @3.75f, @3.0f, @1.5f, @0.0f, @-1.5f ]],
		[MLEQPreset presetWithId:@"custom" nameKey:@"eq_preset_custom"
		                   gains:@[ @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f ]]
	];
}

- (NSArray *)presets
{
	return _presetList;
}

- (NSInteger)numberOfBands
{
	return ML_EQ_NUM_BANDS;
}

- (float)frequencyForBand:(NSInteger)bandIndex
{
	if (bandIndex >= 0 && bandIndex < ML_EQ_NUM_BANDS) {
		return kEQFrequencies[bandIndex];
	}
	return 1000.0f;
}

- (NSString *)frequencyStringForBand:(NSInteger)bandIndex
{
	float freq = [self frequencyForBand:bandIndex];
	if (freq >= 1000.0f) {
		return [NSString stringWithFormat:@"%.0f kHz", freq / 1000.0f];
	} else {
		return [NSString stringWithFormat:@"%.0f Hz", freq];
	}
}

- (NSString *)shortFrequencyStringForBand:(NSInteger)bandIndex
{
	float freq = [self frequencyForBand:bandIndex];
	if (freq >= 1000.0f) {
		return [NSString stringWithFormat:@"%.0fK", freq / 1000.0f];
	} else {
		return [NSString stringWithFormat:@"%.0f", freq];
	}
}

- (float)gainForBand:(NSInteger)bandIndex
{
	if (bandIndex >= 0 && bandIndex < ML_EQ_NUM_BANDS) {
		return _bandGains[bandIndex];
	}
	return 0.0f;
}

- (void)setGain:(float)gainDb forBand:(NSInteger)bandIndex
{
	[self setGain:gainDb forBand:bandIndex notify:YES];
}

- (void)setGain:(float)gainDb forBand:(NSInteger)bandIndex notify:(BOOL)notify
{
	if (bandIndex < 0 || bandIndex >= ML_EQ_NUM_BANDS) return;

	if (gainDb > 12.0f) gainDb = 12.0f;
	if (gainDb < -12.0f) gainDb = -12.0f;

	[_lock lock];
	_bandGains[bandIndex] = gainDb;
	_currentPresetId = @"custom";
	[_lock unlock];

	[self updateAllActiveStorages];

	if (notify) {
		[self saveSettings];
		[[NSNotificationCenter defaultCenter] postNotificationName:MLEqualizerDidChangeNotification object:self];
	}
}

- (NSArray *)allBandGains
{
	NSMutableArray *arr = [NSMutableArray arrayWithCapacity:ML_EQ_NUM_BANDS];
	[_lock lock];
	for (int i = 0; i < ML_EQ_NUM_BANDS; i++) {
		[arr addObject:@(_bandGains[i])];
	}
	[_lock unlock];
	return arr;
}

- (void)setAllBandGains:(NSArray *)gains
{
	if (gains.count != ML_EQ_NUM_BANDS) return;

	[_lock lock];
	for (int i = 0; i < ML_EQ_NUM_BANDS; i++) {
		float g = [gains[i] floatValue];
		if (g > 12.0f) g = 12.0f;
		if (g < -12.0f) g = -12.0f;
		_bandGains[i] = g;
	}
	[_lock unlock];

	[self updateAllActiveStorages];

	[self synchronizeSettings];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLEqualizerDidChangeNotification object:self];
}

- (void)setEnabled:(BOOL)enabled
{
	if (_enabled == enabled) return;

	[_lock lock];
	_enabled = enabled;
	[_lock unlock];

	[self updateAllActiveStorages];

	[self synchronizeSettings];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLEqualizerDidChangeNotification object:self];

	// Ensure current playerItem has tap attached if not already attached
	dispatch_async(dispatch_get_main_queue(), ^{
		AVPlayerItem *item = [MLPlaybackManager sharedManager].player.currentItem;
		if (item && item.audioMix == nil) {
			[self attachEqualizerToPlayerItem:item];
		}
	});
}

- (void)applyPresetWithId:(NSString *)presetId
{
	MLEQPreset *target = nil;
	for (MLEQPreset *p in _presetList) {
		if ([p.presetId isEqualToString:presetId]) {
			target = p;
			break;
		}
	}
	if (!target) return;

	[_lock lock];
	_currentPresetId = target.presetId;
	if (![presetId isEqualToString:@"custom"]) {
		for (int i = 0; i < ML_EQ_NUM_BANDS; i++) {
			_bandGains[i] = [target.bandGains[i] floatValue];
		}
	}
	[_lock unlock];

	[self updateAllActiveStorages];

	[self synchronizeSettings];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLEqualizerDidChangeNotification object:self];
}

- (NSString *)currentPresetLocalizedName
{
	for (MLEQPreset *p in _presetList) {
		if ([p.presetId isEqualToString:_currentPresetId]) {
			return NSLocalizedString(p.nameKey, nil);
		}
	}
	return NSLocalizedString(@"eq_preset_custom", nil);
}

- (void)resetToFlat
{
	[self applyPresetWithId:@"flat"];
}

- (void)saveSettings
{
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	[ud setBool:_enabled forKey:kPrefEqualizerEnabled];
	[ud setObject:_currentPresetId forKey:kPrefEqualizerPresetId];

	NSMutableArray *arr = [NSMutableArray arrayWithCapacity:ML_EQ_NUM_BANDS];
	[_lock lock];
	for (int i = 0; i < ML_EQ_NUM_BANDS; i++) {
		[arr addObject:@(_bandGains[i])];
	}
	[_lock unlock];
	[ud setObject:arr forKey:kPrefEqualizerBandValues];
}

- (void)synchronizeSettings
{
	[self saveSettings];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

// MARK: - DSP Coefficients Calculation (Accelerate vDSP Biquad + Manual Fallback)

- (void)updateStorageCoefficients:(MLEqualizerTapStorage *)storage
{
	if (!storage) return;

	BOOL vDSPAvailable = MLEnsureVDSPBiquadAvailable();
	
	pthread_mutex_lock(&storage->lock);
	double sampleRate = storage->sampleRate > 8000.0 ? storage->sampleRate : 44100.0;
	pthread_mutex_unlock(&storage->lock);

	BOOL allFlat = YES;
	float maxGain = 0.0f;

	[_lock lock];
	float currentBands[ML_EQ_NUM_BANDS];
	BOOL currentEnabled = _enabled;
	for (int i = 0; i < ML_EQ_NUM_BANDS; i++) {
		currentBands[i] = _bandGains[i];
		if (fabsf(currentBands[i]) > 0.05f) {
			allFlat = NO;
		}
		if (currentBands[i] > maxGain) {
			maxGain = currentBands[i];
		}
	}
	[_lock unlock];

	float preampGain = 1.0f;
	if (maxGain > 0.0f) {
		float headroomDb = MIN(maxGain * 0.35f, 3.5f);
		preampGain = powf(10.0f, -headroomDb / 20.0f);
	}

	// Calculate RBJ Peaking EQ coefficients for each of the 10 bands
	double doubleCoeffs[5 * ML_EQ_NUM_BANDS];

	for (int i = 0; i < ML_EQ_NUM_BANDS; i++) {
		float f0 = kEQFrequencies[i];
		float gainDb = currentBands[i];
		float Q = kEQDefaultQ;

		if (f0 >= (float)(sampleRate * 0.49)) {
			f0 = (float)(sampleRate * 0.49);
		}

		if (fabsf(gainDb) < 0.05f) {
			// Identity section: b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0
			doubleCoeffs[i * 5 + 0] = 1.0;
			doubleCoeffs[i * 5 + 1] = 0.0;
			doubleCoeffs[i * 5 + 2] = 0.0;
			doubleCoeffs[i * 5 + 3] = 0.0;
			doubleCoeffs[i * 5 + 4] = 0.0;
			continue;
		}

		double A = pow(10.0, (double)gainDb / 40.0);
		double omega = 2.0 * M_PI * (double)f0 / sampleRate;
		double sn = sin(omega);
		double cs = cos(omega);
		double alpha = sn / (2.0 * (double)Q);

		double b0 = 1.0 + alpha * A;
		double b1 = -2.0 * cs;
		double b2 = 1.0 - alpha * A;
		double a0 = 1.0 + alpha / A;
		double a1 = -2.0 * cs;
		double a2 = 1.0 - alpha / A;

		if (fabs(a0) > 1e-9) {
			doubleCoeffs[i * 5 + 0] = b0 / a0;
			doubleCoeffs[i * 5 + 1] = b1 / a0;
			doubleCoeffs[i * 5 + 2] = b2 / a0;
			doubleCoeffs[i * 5 + 3] = a1 / a0;
			doubleCoeffs[i * 5 + 4] = a2 / a0;
		} else {
			doubleCoeffs[i * 5 + 0] = 1.0;
			doubleCoeffs[i * 5 + 1] = 0.0;
			doubleCoeffs[i * 5 + 2] = 0.0;
			doubleCoeffs[i * 5 + 3] = 0.0;
			doubleCoeffs[i * 5 + 4] = 0.0;
		}
	}

	// Atomically swap all storage fields under storage mutex
	pthread_mutex_lock(&storage->lock);
	storage->enabled = currentEnabled;
	storage->allBandsFlat = allFlat;
	storage->preampGain = preampGain;
	storage->useManualBiquad = !vDSPAvailable;
	
	if (vDSPAvailable) {
		vDSP_biquad_Setup newSetup = vDSP_biquad_CreateSetup(doubleCoeffs, ML_EQ_NUM_BANDS);
		vDSP_biquad_Setup oldSetup = storage->biquadSetup;
		storage->biquadSetup = newSetup;
		if (oldSetup) {
			vDSP_biquad_DestroySetup(oldSetup);
		}
	} else {
		// Initialize manual biquad state (iOS 6/7)
		MLManualBiquadInit(&storage->manualBiquad, doubleCoeffs);
		if (storage->biquadSetup) {
			vDSP_biquad_DestroySetup(storage->biquadSetup);
			storage->biquadSetup = NULL;
		}
		NSLog(@"[MLEQ] Using manual biquad fallback (iOS 6/7 compatible)");
	}
	pthread_mutex_unlock(&storage->lock);
}

- (void)updateAllActiveStorages
{
	NSArray *storages = nil;
	[_lock lock];
	storages = [_activeStorages allObjects];
	[_lock unlock];

	for (NSValue *val in storages) {
		MLEqualizerTapStorage *st = (MLEqualizerTapStorage *)[val pointerValue];
		if (st) {
			[self updateStorageCoefficients:st];
		}
	}
}

- (void)registerTapStorage:(MLEqualizerTapStorage *)storage
{
	if (!storage) return;

	[_lock lock];
	[_activeStorages addObject:[NSValue valueWithPointer:storage]];
	[_lock unlock];

	[self updateStorageCoefficients:storage];
}

- (void)unregisterTapStorage:(MLEqualizerTapStorage *)storage
{
	if (!storage) return;

	[_lock lock];
	[_activeStorages removeObject:[NSValue valueWithPointer:storage]];
	[_lock unlock];
}

- (void)getScopeData:(float *)outBuffer length:(NSUInteger)len
{
	if (!outBuffer || len == 0) return;

	NSValue *val = nil;
	[_lock lock];
	val = [_activeStorages anyObject];
	[_lock unlock];

	MLEqualizerTapStorage *st = val ? (MLEqualizerTapStorage *)[val pointerValue] : NULL;
	if (st && pthread_mutex_trylock(&st->lock) == 0) {
		NSUInteger copyCount = MIN(len, (NSUInteger)ML_EQ_SCOPE_SIZE);
		memcpy(outBuffer, st->scopeBuffer, copyCount * sizeof(float));
		pthread_mutex_unlock(&st->lock);
		if (copyCount < len) {
			memset(outBuffer + copyCount, 0, (len - copyCount) * sizeof(float));
		}
	} else {
		memset(outBuffer, 0, len * sizeof(float));
	}
}

// MARK: - Direct CoreAudio PCM Processing

- (void)processInterleavedFloatBuffer:(float *)samples
                           frameCount:(UInt32)frames
                             channels:(UInt32)channels
                           sampleRate:(double)sampleRate
{
	if (!samples || frames == 0) return;

	MLEqualizerTapStorage *storage = &_coreAudioStorage;

	if (sampleRate > 0 && fabs(storage->sampleRate - sampleRate) > 1.0) {
		pthread_mutex_lock(&storage->lock);
		storage->sampleRate = sampleRate;
		storage->channels = channels;
		memset(storage->delays, 0, sizeof(storage->delays));
		pthread_mutex_unlock(&storage->lock);
		[self updateStorageCoefficients:storage];
	}

	if (pthread_mutex_trylock(&storage->lock) != 0) {
		// Non-blocking try-lock: if mutex busy updating coefficients, pass audio cleanly
		return;
	}

	if (!storage->enabled || storage->allBandsFlat || (!storage->useManualBiquad && !storage->biquadSetup)) {
		// Pass-through: copy recent samples to scope buffer for UI visualizer
		NSUInteger copyCount = MIN((NSUInteger)frames, (NSUInteger)ML_EQ_SCOPE_SIZE);
		uint32_t nc = storage->channels > 0 ? storage->channels : 1;
		for (NSUInteger k = 0; k < copyCount; k++) {
			storage->scopeBuffer[k] = samples[k * nc];
		}
		pthread_mutex_unlock(&storage->lock);
		return;
	}

	float preamp = storage->preampGain;
	float clipLow = -1.0f;
	float clipHigh = 1.0f;
	uint32_t numChannels = storage->channels > 2 ? 2 : storage->channels;
	vDSP_Length totalSamples = frames * numChannels;

	// 1. Preamp Scaling
	vDSP_vsmul(samples, 1, &preamp, samples, 1, totalSamples);

	// 2. 10-Band Cascaded Biquad Filtering
	if (storage->useManualBiquad) {
		// Manual biquad (iOS 6/7)
		MLManualBiquadProcessInPlace(&storage->manualBiquad, samples, numChannels, frames);
	} else {
		// vDSP (iOS 8+)
		vDSP_biquad(storage->biquadSetup, storage->delays[0], samples, numChannels, samples, numChannels, frames);
		if (numChannels > 1) {
			vDSP_biquad(storage->biquadSetup, storage->delays[1], samples + 1, numChannels, samples + 1, numChannels, frames);
		}
	}

	// 3. Saturation Clamping
	vDSP_vclip(samples, 1, &clipLow, &clipHigh, samples, 1, totalSamples);

	// 4. Update Scope Buffer for UI Waveform Visualizer
	NSUInteger copyCount = MIN((NSUInteger)frames, (NSUInteger)ML_EQ_SCOPE_SIZE);
	for (NSUInteger k = 0; k < copyCount; k++) {
		storage->scopeBuffer[k] = samples[k * numChannels];
	}

	pthread_mutex_unlock(&storage->lock);
}
// MARK: - AVPlayerItem Integration

- (AVAssetTrack *)audioTrackFromPlayerItem:(AVPlayerItem *)playerItem
{
	if (!playerItem) return nil;

	// 1. Check playerItem.tracks (populated when readyToPlay)
	for (AVPlayerItemTrack *itemTrack in playerItem.tracks) {
		AVAssetTrack *t = itemTrack.assetTrack;
		if (t && [t.mediaType isEqualToString:AVMediaTypeAudio]) {
			return t;
		}
	}

	// 2. Check asset tracksWithMediaType
	AVAsset *asset = playerItem.asset;
	if (asset) {
		NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
		if (tracks.count > 0) {
			return tracks[0];
		}
	}

	return nil;
}

- (void)attachEqualizerToPlayerItem:(AVPlayerItem *)playerItem
{
	if (!playerItem) return;
	if (&MTAudioProcessingTapCreate == NULL) {
		NSLog(@"[MLEqualizer] MTAudioProcessingTapCreate not supported on this OS");
		return;
	}

	if (playerItem.audioMix != nil) {
		return;
	}

	AVAsset *asset = playerItem.asset;
	if (!asset) return;

	// In AVFoundation, MTAudioProcessingTap / AVAudioMix cannot be attached to HLS streams (.m3u8),
	// which causes CoreMedia/mediaserverd failure with error -303 (MIG_BAD_ID).
	if ([asset isKindOfClass:[AVURLAsset class]]) {
		NSURL *assetURL = ((AVURLAsset *)asset).URL;
		NSString *urlStr = assetURL.absoluteString;
		if ([assetURL.path hasSuffix:@".m3u8"] ||
		    [urlStr rangeOfString:@".m3u8"].location != NSNotFound ||
		    [urlStr rangeOfString:@"/p.m3u8"].location != NSNotFound) {
			NSLog(@"[MLEqualizer] HLS stream detected — MTAudioProcessingTap is unsupported on HLS, bypassing EQ.");
			return;
		}
	}

	AVAssetTrack *track = [self audioTrackFromPlayerItem:playerItem];
	NSLog(@"[MLEQ] attachEqualizer: track=%@, playerItem.tracks=%lu, asset.tracks=%lu, status=%ld",
	      track, (unsigned long)playerItem.tracks.count,
	      (unsigned long)[[playerItem.asset tracksWithMediaType:AVMediaTypeAudio] count],
	      (long)playerItem.status);

	if (playerItem.status != AVPlayerItemStatusReadyToPlay && playerItem.tracks.count == 0) {
		NSLog(@"[MLEQ] Postponing attachEqualizer until playerItem is ReadyToPlay (status=%ld, tracks=%lu)",
		      (long)playerItem.status, (unsigned long)playerItem.tracks.count);
		return;
	}

	MTAudioProcessingTapCallbacks callbacks;
	callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
	callbacks.clientInfo = (__bridge void *)self;
	callbacks.init = tapInit;
	callbacks.finalize = tapFinalize;
	callbacks.prepare = tapPrepare;
	callbacks.unprepare = tapUnprepare;
	callbacks.process = tapProcess;

	MTAudioProcessingTapRef tap = NULL;
	OSStatus err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap);
	if (err != noErr || !tap) {
		NSLog(@"[MLEQ] MTAudioProcessingTapCreate failed with status %d", (int)err);
		return;
	}

	NSMutableArray *inputParamsArray = [NSMutableArray array];
	if (track) {
		AVMutableAudioMixInputParameters *params = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
		params.audioTapProcessor = tap;
		[inputParamsArray addObject:params];
		NSLog(@"[MLEQ] Successfully attached 10-band vDSP audio tap processor to track (%d)", (int)track.trackID);
	} else {
		// No AVAssetTrack found (e.g. elemental ADTS stream).
		// Use empty audioMixInputParameters with default and invalid trackIDs
		AVMutableAudioMixInputParameters *p1 = [AVMutableAudioMixInputParameters audioMixInputParameters];
		p1.trackID = 1;
		p1.audioTapProcessor = tap;
		[inputParamsArray addObject:p1];

		AVMutableAudioMixInputParameters *p0 = [AVMutableAudioMixInputParameters audioMixInputParameters];
		p0.trackID = kCMPersistentTrackID_Invalid; // 0
		p0.audioTapProcessor = tap;
		[inputParamsArray addObject:p0];

		for (AVPlayerItemTrack *it in playerItem.tracks) {
			if (it.assetTrack && it.assetTrack.trackID != 1 && it.assetTrack.trackID != 0) {
				AVMutableAudioMixInputParameters *pit = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:it.assetTrack];
				pit.audioTapProcessor = tap;
				[inputParamsArray addObject:pit];
			}
		}
		NSLog(@"[MLEQ] Successfully attached 10-band vDSP audio tap processor with fallback parameters");
	}

	AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
	audioMix.inputParameters = inputParamsArray;
	playerItem.audioMix = audioMix;

	CFRelease(tap);
}

@end
