#import <Foundation/Foundation.h>
#import "../InnerTube/MLYTItem.h"

extern NSString *const MLLibraryDidUpdateNotification;

@interface MLLibraryManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly) NSArray *likedSongs;       // MLYTItem
@property (nonatomic, readonly) NSArray *syncedPlaylists;  // MLYTItem
@property (nonatomic, readonly) NSArray *syncedSongs;      // MLYTItem
@property (nonatomic, readonly) NSArray *syncedAlbums;     // MLYTItem
@property (nonatomic, readonly) NSArray *syncedArtists;    // MLYTItem
@property (nonatomic, readonly) NSArray *historySongs;     // MLYTItem
@property (nonatomic, readonly) NSArray *downloadedSongs;  // MLYTItem
@property (nonatomic, readonly) NSArray *cachedSongs;      // MLYTItem
@property (nonatomic, readonly) NSArray *top50Songs;        // MLYTItem

@property (nonatomic, readonly, getter=isSyncing) BOOL syncing;
@property (nonatomic, readonly) NSDate *lastSyncDate;

// YouTube Music Synchronization
- (void)syncWithYouTubeMusicCompletion:(void (^)(BOOL ok, NSString *error))completion;

// Likes
- (BOOL)isSongLiked:(NSString *)videoId;
- (void)toggleLikeForSong:(MLYTItem *)song completion:(void (^)(BOOL isLiked, NSString *error))completion;

// History
- (void)recordPlayedSong:(MLYTItem *)song;

// Offline Downloads & Stream Cache
- (BOOL)isSongDownloaded:(NSString *)videoId;
- (BOOL)isSongDownloading:(NSString *)videoId;
- (BOOL)isSongCached:(NSString *)videoId;
- (BOOL)isBatchDownloading;
- (NSUInteger)activeDownloadsCount;

- (NSURL *)localFileURLForVideoId:(NSString *)videoId;

- (void)downloadSong:(MLYTItem *)song completion:(void (^)(BOOL ok, NSString *error))completion;
- (void)downloadAllSongs:(NSArray *)songs;
- (void)cancelDownloadForVideoId:(NSString *)videoId;
- (void)cancelAllDownloads;
- (void)removeDownloadedSong:(NSString *)videoId;

// Playlist Creation & Queue Persistence
- (void)saveQueue:(NSArray *)queue
  asPlaylistWithTitle:(NSString *)title
           completion:(void (^)(NSString *playlistId, NSString *error))completion;
- (void)removePlaylistWithId:(NSString *)playlistId;

- (void)cacheSong:(MLYTItem *)song fromStreamURL:(NSURL *)streamURL;
- (void)clearAudioCache;

// Playlist & Album Metadata/Tracklist Cache
- (void)cachePlaylistHeader:(NSDictionary *)header tracks:(NSArray *)tracks forKey:(NSString *)key;
- (NSDictionary *)cachedPlaylistForKey:(NSString *)key;

// Storage metrics
- (unsigned long long)downloadedTotalBytes;
- (unsigned long long)audioCacheTotalBytes;
- (NSString *)formattedSizeForBytes:(unsigned long long)bytes;

@end
