#import "MLYTItem.h"

@implementation MLYTItem

- (id)init
{
	self = [super init];
	if (self) {
		_kind = MLYTKindUnknown;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	MLYTItem *c = [[MLYTItem allocWithZone:zone] init];
	c.kind = _kind;
	c.videoId = _videoId;
	c.browseId = _browseId;
	c.playlistId = _playlistId;
	c.title = _title;
	c.subtitle = _subtitle;
	c.artists = _artists;
	c.thumbnailUrl = _thumbnailUrl;
	c.duration = _duration;
	c.explicit = _explicit;
	c.params = _params;
	c.continuation = _continuation;
	c.artistBrowseId = _artistBrowseId;
	c.albumBrowseId = _albumBrowseId;
	return c;
}

+ (NSString *)subtitleFromArtists:(NSArray *)artists suffix:(NSString *)suffix
{
	NSMutableString *s = [NSMutableString string];
	for (NSUInteger i = 0; i < artists.count; i++) {
		if (i > 0)
			[s appendString:@", "];
		[s appendString:artists[i]];
	}
	if (suffix.length > 0) {
		if (s.length > 0)
			[s appendFormat:@" • %@", suffix];
		else
			[s appendString:suffix];
	}
	return s;
}

- (NSDictionary *)toDictionary
{
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	d[@"kind"] = @(_kind);
	if (_videoId) d[@"videoId"] = _videoId;
	if (_browseId) d[@"browseId"] = _browseId;
	if (_playlistId) d[@"playlistId"] = _playlistId;
	if (_title) d[@"title"] = _title;
	if (_subtitle) d[@"subtitle"] = _subtitle;
	if (_artists) d[@"artists"] = _artists;
	if (_thumbnailUrl) d[@"thumbnailUrl"] = _thumbnailUrl;
	if (_duration > 0) d[@"duration"] = @(_duration);
	if (_explicit) d[@"explicit"] = @YES;
	if (_params) d[@"params"] = _params;
	if (_continuation) d[@"continuation"] = _continuation;
	if (_artistBrowseId) d[@"artistBrowseId"] = _artistBrowseId;
	if (_albumBrowseId) d[@"albumBrowseId"] = _albumBrowseId;
	return d;
}

+ (instancetype)itemFromDictionary:(NSDictionary *)dict
{
	if (![dict isKindOfClass:[NSDictionary class]])
		return nil;
	MLYTItem *it = [[MLYTItem alloc] init];
	it.kind = (MLYTKind)[dict[@"kind"] integerValue];
	it.videoId = dict[@"videoId"];
	it.browseId = dict[@"browseId"];
	it.playlistId = dict[@"playlistId"];
	it.title = dict[@"title"];
	it.subtitle = dict[@"subtitle"];
	it.artists = dict[@"artists"];
	it.thumbnailUrl = dict[@"thumbnailUrl"];
	it.duration = [dict[@"duration"] doubleValue];
	it.explicit = [dict[@"explicit"] boolValue];
	it.params = dict[@"params"];
	it.continuation = dict[@"continuation"];
	it.artistBrowseId = dict[@"artistBrowseId"];
	it.albumBrowseId = dict[@"albumBrowseId"];
	return it.title.length ? it : nil;
}

@end

NSString *MLFormatDuration(NSTimeInterval sec)
{
	if (sec < 0 || isnan(sec)) sec = 0;
	NSInteger total = (NSInteger)sec;
	if (total >= 3600) {
		return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(total / 3600), (long)((total % 3600) / 60), (long)(total % 60)];
	}
	return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

