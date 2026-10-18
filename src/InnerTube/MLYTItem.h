#import <Foundation/Foundation.h>

typedef enum {
	MLYTKindUnknown = 0,
	MLYTKindSong,
	MLYTKindVideo,
	MLYTKindAlbum,
	MLYTKindArtist,
	MLYTKindPlaylist,
	MLYTKindPodcast,
} MLYTKind;

/*
 * A parsed YouTube Music item (song, album, artist, playlist...).
 * Mirrors Metrolist's YTItem models.
 */
@interface MLYTItem : NSObject <NSCopying>

@property (nonatomic, assign) MLYTKind kind;
@property (nonatomic, copy) NSString *videoId;        // songs/videos
@property (nonatomic, copy) NSString *browseId;       // albums/artists/playlists
@property (nonatomic, copy) NSString *playlistId;      // album playlistId / playlists
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;       // "Artista • Álbum • 3:45"
@property (nonatomic, copy) NSArray *artists;         // NSString names
@property (nonatomic, copy) NSString *thumbnailUrl;    // largest available
@property (nonatomic, assign) double duration;        // seconds, 0 unknown
@property (nonatomic, assign, getter=isExplicit) BOOL explicit;
@property (nonatomic, copy) NSString *params;          // extra browse params
@property (nonatomic, copy) NSString *continuation;    // for paged lists
@property (nonatomic, copy) NSString *artistBrowseId;  // UC... channel id if available
@property (nonatomic, copy) NSString *albumBrowseId;   // MPRE... album id if available

+ (NSString *)subtitleFromArtists:(NSArray *)artists suffix:(NSString *)suffix;

- (NSDictionary *)toDictionary;
+ (instancetype)itemFromDictionary:(NSDictionary *)dict;

@end

NSString *MLFormatDuration(NSTimeInterval sec);

