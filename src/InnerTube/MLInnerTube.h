#import <Foundation/Foundation.h>
#import "MLYTItem.h"

/*
 * Objective-C port of Metrolist's innertube client (WEB_REMIX).
 * Plain JSON/REST over NSURLConnection — works on iOS 6.
 */

// Key-path lookup helper: MLPath(obj, @"a.0.b") — defined in MLInnerTube.m
extern id MLPath(id root, NSString *keyPath);

extern NSString *const MLSessionChangedNotification;

@class MLHomeSection;
@class MLChip;

@interface MLInnerTube : NSObject

+ (instancetype)sharedClient;

// Session state (persisted in NSUserDefaults)
@property (nonatomic, copy) NSString *cookie;        // raw account cookie, nil when signed out
@property (nonatomic, copy) NSString *visitorData;
@property (nonatomic, copy) NSString *dataSyncId;
@property (nonatomic, copy) NSString *authUser;        // session index, default "0"
@property (nonatomic, copy) NSString *accountName;
@property (nonatomic, copy) NSString *accountEmail;
@property (nonatomic, copy) NSString *accountChannelHandle;
@property (nonatomic, copy) NSString *accountPhotoUrl;
@property (nonatomic, copy) NSString *hl;
@property (nonatomic, copy) NSString *gl;
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, copy) NSString *refreshToken;
@property (nonatomic, strong) NSDate *tokenExpiry;

@property (nonatomic, readonly) BOOL loggedIn;

- (void)loadSavedSession;
- (void)saveSession;
- (void)clearSession;
- (void)setOAuthAccessToken:(NSString *)access refreshToken:(NSString *)refresh expiresIn:(NSTimeInterval)expires;
- (void)ensureValidAccessToken:(void (^)(BOOL ok))completion;

// Direct token import / export (Metrolist format or raw cookie)
- (BOOL)importSessionFromTokenString:(NSString *)tokenString error:(NSString **)errorOut;
- (NSString *)exportSessionTokenString;

#pragma mark - Raw endpoints

- (void)browse:(NSString *)browseId
        params:(NSString *)params
   continuation:(NSString *)continuation
     completion:(void (^)(NSDictionary *response, NSString *error))completion;

- (void)searchRaw:(NSString *)query
           params:(NSString *)params
      continuation:(NSString *)continuation
        completion:(void (^)(NSDictionary *response, NSString *error))completion;

- (void)playerForVideoId:(NSString *)videoId
	signatureTimestamp:(NSInteger)sts
	           poToken:(NSString *)poToken
	        completion:(void (^)(NSDictionary *playerResponse, NSString *error))completion;

- (void)playerForVideoId:(NSString *)videoId
	signatureTimestamp:(NSInteger)sts
	        completion:(void (^)(NSDictionary *playerResponse, NSString *error))completion;

- (void)playerAndroidVrForVideoId:(NSString *)videoId
                       completion:(void (^)(NSDictionary *playerResponse, NSString *error))completion;

- (void)playerVisionOsForVideoId:(NSString *)videoId
                      completion:(void (^)(NSDictionary *playerResponse, NSString *error))completion;

- (void)suggestionsForInput:(NSString *)input
                 completion:(void (^)(NSArray *suggestions, NSString *error))completion;

- (void)accountMenu:(void (^)(NSDictionary *accountInfo, NSString *error))completion;

#pragma mark - Parsed operations

- (void)homeFeedWithParams:(NSString *)params
                completion:(void (^)(NSArray *sections, NSArray *chips, NSString *error))completion;

- (void)searchQuery:(NSString *)query
             params:(NSString *)params
        continuation:(NSString *)continuation
         completion:(void (^)(NSArray *items, NSString *nextContinuation, NSString *error))completion;

// Album: header info + tracks. Two-step (release page, then VL playlist).
- (void)albumWithBrowseId:(NSString *)browseId
               completion:(void (^)(NSDictionary *header, NSArray *tracks, NSString *error))completion;

// Playlist by id (accepts with or without VL prefix).
- (void)playlistWithId:(NSString *)playlistId
            continuation:(NSString *)continuation
             completion:(void (^)(NSDictionary *header, NSArray *tracks, NSString *nextContinuation, NSString *error))completion;

// Artist page: header + sections.
- (void)artistWithBrowseId:(NSString *)browseId
               completion:(void (^)(NSDictionary *header, NSArray *sections, NSString *error))completion;

// Liked songs (login required).
- (void)likedSongsWithCompletion:(void (^)(NSDictionary *header, NSArray *tracks, NSString *nextContinuation, NSString *error))completion;
- (void)likedSongsWithContinuation:(NSString *)continuation
                        completion:(void (^)(NSDictionary *header, NSArray *tracks, NSString *nextContinuation, NSString *error))completion;

// Fetch any YouTube Music library browseId (FEmusic_liked_playlists, FEmusic_liked_videos, FEmusic_liked_albums, FEmusic_library_corpus_artists, FEmusic_history).
- (void)libraryWithBrowseId:(NSString *)browseId
                 completion:(void (^)(NSArray *items, NSString *error))completion;

// Real-time Like / Remove Like on YouTube Music (like/like or like/removelike).
- (void)likeVideoWithId:(NSString *)videoId
                  liked:(BOOL)liked
             completion:(void (^)(BOOL ok, NSString *error))completion;

// Create a new YouTube Music playlist (playlist/create).
- (void)createPlaylistWithTitle:(NSString *)title
                     completion:(void (^)(NSString *playlistId, NSString *error))completion;
- (void)createPlaylistWithTitle:(NSString *)title
                       videoIds:(NSArray *)videoIds
                     completion:(void (^)(NSString *playlistId, NSString *error))completion;

// Add a song to a YouTube Music playlist (browse/edit_playlist).
- (void)addVideoId:(NSString *)videoId
      toPlaylistId:(NSString *)playlistId
        completion:(void (^)(BOOL ok, NSString *error))completion;
- (void)addVideoIds:(NSArray *)videoIds
       toPlaylistId:(NSString *)playlistId
         completion:(void (^)(BOOL ok, NSString *error))completion;

// Up Next / Radio / Related recommendations for a video or playlist (Metrolist queue port).
- (void)nextForVideoId:(NSString *)videoId
            playlistId:(NSString *)playlistId
            completion:(void (^)(NSArray *items, NSString *title, NSString *error))completion;

// Fetches visitorData via sw.js_data if missing.
- (void)bootstrapVisitorData:(void (^)(BOOL ok))completion;

@end

/*
 * A home/explore section: title + horizontal list of items.
 */
@interface MLHomeSection : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray *items;         // MLYTItem
@property (nonatomic, copy) NSString *moreBrowseId;  // "more" endpoint
@property (nonatomic, copy) NSString *moreParams;

@end

/*
 * A filter chip (home filters / search filters).
 */
@interface MLChip : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *params;     // browse params
@property (nonatomic, copy) NSString *browseId;  // for search-type chips
@property (nonatomic, assign, getter=isSelected) BOOL selected;

@end

/*
 * Search filter constants (from Metrolist YouTube.kt).
 */
extern NSString *const MLSearchFilterSongs;
extern NSString *const MLSearchFilterVideos;
extern NSString *const MLSearchFilterAlbums;
extern NSString *const MLSearchFilterArtists;
extern NSString *const MLSearchFilterPlaylists;

@interface MLInnerTube (Parsing)

// Recursive collector: finds all dicts whose matching key exists, shallowest first.
+ (NSArray *)allObjectsForKey:(NSString *)key inObject:(id)obj maxDepth:(NSUInteger)maxDepth;

+ (NSString *)textFromRuns:(id)textObj;
+ (NSString *)bestThumbnailUrl:(id)thumbObj;

// Parse a musicResponsiveListItemRenderer / musicTwoRowItemRenderer into MLYTItem.
+ (MLYTItem *)itemFromResponsiveListRenderer:(NSDictionary *)r;
+ (MLYTItem *)itemFromTwoRowRenderer:(NSDictionary *)r;
+ (NSArray *)itemsFromContentsArray:(NSArray *)contents;
+ (MLYTItem *)itemFromRenderer:(NSDictionary *)wrapper;

+ (NSArray *)homeSectionsFromResponse:(NSDictionary *)response;
+ (NSArray *)chipsFromResponse:(NSDictionary *)response;
+ (NSString *)continuationFromResponseOrShelf:(id)obj;

+ (NSDictionary *)headerInfoFromResponse:(NSDictionary *)response;
+ (NSUInteger)trackCountFromText:(NSString *)text;
+ (NSUInteger)trackCountFromHeader:(NSDictionary *)header;

@end
