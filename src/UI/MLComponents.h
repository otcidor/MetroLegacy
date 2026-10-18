#import <UIKit/UIKit.h>
#import "MLYTItem.h"
#import "MLInnerTube.h"

/*
 * Pill filter chips in a horizontal scroll (M3 FilterChip).
 */
@interface MLChipsRowView : UIView

@property (nonatomic, copy) void (^onChange)(MLChip *chip);

- (void)setChips:(NSArray *)chips;
- (void)setSelectedIndex:(NSUInteger)index;

@end

/*
 * A card in a horizontal shelf: square/circular thumbnail + play badge + title + subtitle.
 */
@interface MLCardButton : UIControl

- (void)fillWithItem:(MLYTItem *)item;

@property (nonatomic, readonly) MLYTItem *item;

@end

/*
 * Table row: section title + horizontal shelf of album/playlist/artist cards.
 */
@interface MLShelfCell : UITableViewCell

@property (nonatomic, copy) void (^cardTapped)(MLYTItem *item);

- (void)fillWithSection:(MLHomeSection *)section;

@end

/*
 * Metrolist Quick Picks horizontal 3-row song grid cell.
 */
@interface MLQuickPicksShelfCell : UITableViewCell

@property (nonatomic, copy) void (^songTapped)(MLYTItem *item, NSArray *sectionItems);
@property (nonatomic, copy) void (^moreTapped)(MLYTItem *item);

- (void)fillWithSection:(MLHomeSection *)section playingVideoId:(NSString *)playingVideoId;

@end

/*
 * 3-column vertical grid shelf cell matching MetroList Home "Speed dial" layout.
 */
@interface MLGridShelfCell : UITableViewCell

@property (nonatomic, copy) void (^cardTapped)(MLYTItem *item);

- (void)fillWithSection:(MLHomeSection *)section;
+ (CGFloat)heightForSection:(MLHomeSection *)section width:(CGFloat)width;

@end

/*
 * MetroList Home Speed Dial 3x3 paged grid with bottom title overlays and page dots.
 */
@interface MLSpeedDialCell : UITableViewCell

@property (nonatomic, copy) void (^itemTapped)(MLYTItem *item, BOOL isLucky);

- (void)fillWithItems:(NSArray *)items title:(NSString *)title;
+ (CGFloat)heightForWidth:(CGFloat)width;

@end

/*
 * 64pt song list row with active-playing equalizer badge and rounded highlight.
 */
@interface MLSongCell : UITableViewCell

@property (nonatomic, copy) void (^moreTapped)(MLYTItem *item);

- (void)fillWithItem:(MLYTItem *)item;
- (void)fillWithItem:(MLYTItem *)item isPlaying:(BOOL)isPlaying;

@end
