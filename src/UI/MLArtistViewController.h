#import <UIKit/UIKit.h>

@interface MLArtistViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (id)initWithBrowseId:(NSString *)browseId name:(NSString *)name;

@end
