#import <UIKit/UIKit.h>
#import "MLYTItem.h"

/*
 * Generic list screen for albums / playlists / liked songs.
 * Metrolist layout: big centered artwork, title, subtitle, play button, track list.
 */
@interface MLListDetailViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate>

- (id)initWithAlbumItem:(MLYTItem *)item;
- (id)initWithPlaylistId:(NSString *)playlistId title:(NSString *)title thumbnail:(NSString *)thumbnail;
- (id)initWithLikedSongs;
- (id)initWithDownloadedSongs;
- (id)initWithCachedSongs;
- (id)initWithHistorySongs;
- (id)initWithTop50Songs;

@end
