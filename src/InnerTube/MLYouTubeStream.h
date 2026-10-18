#import <Foundation/Foundation.h>
#import "MLYTItem.h"

/*
 * Resolves a playable audio stream URL for a YouTube videoId.
 * Port of Metrolist's player flow: youtubei/v1/player + audio/mp4 selection.
 */
@interface MLYouTubeStream : NSObject

// Returns an https URL to an audio/mp4 (AAC) stream, or an error string.
+ (void)audioStreamURLForVideoId:(NSString *)videoId
                      completion:(void (^)(NSURL *url, NSString *error))completion;

// Resolves stream URL and player videoDetails (e.g. lengthSeconds, title, author).
+ (void)resolveStreamForVideoId:(NSString *)videoId
                     completion:(void (^)(NSURL *url, NSDictionary *videoDetails, NSString *error))completion;


// Test connectivity of the innertube API from this device.
+ (void)pingAPI:(void (^)(BOOL ok, NSString *detail))completion;

@end
