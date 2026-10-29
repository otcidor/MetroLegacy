#import "MLLibraryViewController.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLImageCache.h"
#import "MLComponents.h"
#import "MLNavigator.h"
#import "MLInnerTube.h"
#import "MLLibraryManager.h"
#import "MLPlaybackManager.h"
#import "MLListDetailViewController.h"
#import "MLLoginViewController.h"
#import "MLTokenEditorViewController.h"
#import "MLAccountSettingsViewController.h"
#import "MLLocalization.h"
#import "MLRootViewController.h"
#import "MLBottomSheet.h"
#import <QuartzCore/QuartzCore.h>

typedef enum {
	MLLibFilterAll = 0,
	MLLibFilterPlaylists,
	MLLibFilterSongs,
	MLLibFilterAlbums,
	MLLibFilterArtists,
	MLLibFilterDownloaded,
} MLLibFilter;

typedef enum {
	MLLibSortRecent = 0,
	MLLibSortName,
	MLLibSortArtist,
} MLLibSortOrder;

@interface MLLibraryCardCell : UITableViewCell
@property (nonatomic, copy) void (^moreTapped)(NSDictionary *entry);
- (void)fillWithEntry:(NSDictionary *)entry;
@end

@implementation MLLibraryCardCell
{
	UIView *_bgHighlight;
	UIView *_thumbContainer;
	UIImageView *_artView;
	UIView *_iconBox;
	UIImageView *_iconView;
	UIView *_badgeBox;
	UIImageView *_badgeIconView;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UIButton *_moreButton;
	NSDictionary *_entry;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;

		_bgHighlight = [[UIView alloc] initWithFrame:CGRectZero];
		_bgHighlight.backgroundColor = [MLTheme surfaceContainerHigh];
		_bgHighlight.layer.cornerRadius = 12.0f;
		_bgHighlight.hidden = YES;
		[self.contentView addSubview:_bgHighlight];

		_thumbContainer = [[UIView alloc] initWithFrame:CGRectMake(12.0f, 8.0f, 48.0f, 48.0f)];
		_thumbContainer.layer.cornerRadius = MLRadiusThumbnail;
		_thumbContainer.clipsToBounds = YES;
		_thumbContainer.backgroundColor = [MLTheme surfaceContainer];
		[self.contentView addSubview:_thumbContainer];

		_iconBox = [[UIView alloc] initWithFrame:_thumbContainer.bounds];
		_iconBox.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_iconBox.backgroundColor = [MLTheme surfaceContainer];
		[_thumbContainer addSubview:_iconBox];

		_iconView = [[UIImageView alloc] initWithFrame:CGRectMake(12.0f, 12.0f, 24.0f, 24.0f)];
		_iconView.contentMode = UIViewContentModeCenter;
		[_iconBox addSubview:_iconView];

		_artView = [[UIImageView alloc] initWithFrame:_thumbContainer.bounds];
		_artView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_artView.contentMode = UIViewContentModeScaleAspectFill;
		_artView.clipsToBounds = YES;
		_artView.hidden = YES;
		[_thumbContainer addSubview:_artView];

		_badgeBox = [[UIView alloc] initWithFrame:CGRectMake(28.0f, 28.0f, 18.0f, 18.0f)];
		_badgeBox.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.65f];
		_badgeBox.layer.cornerRadius = 9.0f;
		_badgeBox.clipsToBounds = YES;
		_badgeBox.hidden = YES;
		[_thumbContainer addSubview:_badgeBox];

		_badgeIconView = [[UIImageView alloc] initWithFrame:CGRectMake(3.0f, 3.0f, 12.0f, 12.0f)];
		_badgeIconView.contentMode = UIViewContentModeCenter;
		[_badgeBox addSubview:_badgeIconView];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = [MLTheme fontTitleSmall];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.font = [MLTheme fontBodySmall];
		_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_subtitleLabel];

		_moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[_moreButton setImage:[MLIcon icon:@"more_vert" size:20.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
		[_moreButton addTarget:self action:@selector(moreTap:) forControlEvents:UIControlEventTouchUpInside];
		[self.contentView addSubview:_moreButton];
	}
	return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
	[super setHighlighted:highlighted animated:animated];
	_bgHighlight.hidden = !highlighted;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_bgHighlight.frame = CGRectMake(6.0f, 2.0f, b.size.width - 12.0f, b.size.height - 4.0f);
	_thumbContainer.frame = CGRectMake(12.0f, (b.size.height - 48.0f) / 2.0f, 48.0f, 48.0f);
	_moreButton.frame = CGRectMake(b.size.width - 40.0f, (b.size.height - 36.0f) / 2.0f, 36.0f, 36.0f);

	CGFloat rightMargin = _moreButton.frame.origin.x;
	CGFloat textX = 70.0f;
	CGFloat textW = MAX(40.0f, rightMargin - textX - 4.0f);

	if (_subtitleLabel.text.length > 0) {
		_titleLabel.frame = CGRectMake(textX, 13.0f, textW, 19.0f);
		_subtitleLabel.frame = CGRectMake(textX, 33.0f, textW, 16.0f);
		_subtitleLabel.hidden = NO;
	} else {
		_titleLabel.frame = CGRectMake(textX, (b.size.height - 20.0f) / 2.0f, textW, 20.0f);
		_subtitleLabel.hidden = YES;
	}
}

- (void)fillWithEntry:(NSDictionary *)e
{
	_entry = e;
	_titleLabel.text = e[@"title"];
	_subtitleLabel.text = e[@"subtitle"];
	NSString *type = e[@"type"];
	BOOL isDestructive = [type isEqualToString:@"logout"];
	UIColor *accent = e[@"color"] ?: (isDestructive ? [MLTheme error] : [MLTheme primary]);
	_titleLabel.textColor = isDestructive ? [MLTheme error] : [MLTheme onSurface];

	NSString *icon = e[@"icon"];
	NSString *thumb = e[@"thumbnailUrl"];

	if (thumb.length > 0) {
		_artView.hidden = NO;
		_iconBox.hidden = YES;
		[MLImageCache loadImageAtURLString:thumb intoView:_artView fitSize:_thumbContainer.frame.size cornerRadius:MLRadiusThumbnail placeholder:[MLImageCache placeholderImageWithSize:_thumbContainer.frame.size]];
		if (icon.length > 0) {
			_badgeBox.hidden = NO;
			_badgeIconView.image = [MLIcon icon:icon size:12.0f color:[UIColor whiteColor]];
		} else {
			_badgeBox.hidden = YES;
		}
	} else {
		_artView.hidden = YES;
		_artView.image = nil;
		_badgeBox.hidden = YES;
		_iconBox.hidden = NO;
		_iconBox.backgroundColor = [accent colorWithAlphaComponent:0.18f];
		if (icon.length > 0) {
			_iconView.image = [MLIcon icon:icon size:24.0f color:accent];
		} else {
			_iconView.image = nil;
		}
	}

	[self setNeedsLayout];
}

- (void)moreTap:(UIButton *)sender
{
	if (_moreTapped && _entry) {
		_moreTapped(_entry);
	}
}

@end

@interface MLLibraryGridItemView : UIControl
{
	UIView *_iconBox;
	UIImageView *_iconView;
	UIImageView *_artView;
	UIView *_badgeBox;
	UIImageView *_badgeIconView;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	id _item;
}
@property (nonatomic, readonly) id item;
- (void)fillWithObject:(id)obj width:(CGFloat)width;
@end

@implementation MLLibraryGridItemView

- (id)item { return _item; }

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor clearColor];

		_iconBox = [[UIView alloc] initWithFrame:CGRectZero];
		_iconBox.backgroundColor = [MLTheme surfaceContainer];
		_iconBox.layer.cornerRadius = 12.0f;
		_iconBox.layer.borderWidth = 1.0f;
		_iconBox.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.22f].CGColor;
		_iconBox.clipsToBounds = YES;
		_iconBox.userInteractionEnabled = NO;
		[self addSubview:_iconBox];

		_iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_iconView.contentMode = UIViewContentModeCenter;
		_iconView.userInteractionEnabled = NO;
		[_iconBox addSubview:_iconView];

		_artView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_artView.contentMode = UIViewContentModeScaleAspectFill;
		_artView.clipsToBounds = YES;
		_artView.layer.cornerRadius = 12.0f;
		_artView.userInteractionEnabled = NO;
		[self addSubview:_artView];

		_badgeBox = [[UIView alloc] initWithFrame:CGRectZero];
		_badgeBox.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.65f];
		_badgeBox.layer.cornerRadius = 14.0f;
		_badgeBox.clipsToBounds = YES;
		_badgeBox.hidden = YES;
		_badgeBox.userInteractionEnabled = NO;
		[self addSubview:_badgeBox];

		_badgeIconView = [[UIImageView alloc] initWithFrame:CGRectMake(5.0f, 5.0f, 18.0f, 18.0f)];
		_badgeIconView.contentMode = UIViewContentModeCenter;
		_badgeIconView.userInteractionEnabled = NO;
		[_badgeBox addSubview:_badgeIconView];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = [MLTheme fontTitleSmall];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		_titleLabel.userInteractionEnabled = NO;
		_titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		[self addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.font = [MLTheme fontBodySmall];
		_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		_subtitleLabel.userInteractionEnabled = NO;
		_subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		[self addSubview:_subtitleLabel];
	}
	return self;
}

- (void)setHighlighted:(BOOL)highlighted
{
	[super setHighlighted:highlighted];
	self.alpha = highlighted ? 0.72f : 1.0f;
}

- (void)fillWithObject:(id)obj width:(CGFloat)width
{
	_item = obj;
	if (!obj || [obj isKindOfClass:[NSNull class]]) {
		self.hidden = YES;
		return;
	}
	self.hidden = NO;

	if ([obj isKindOfClass:[NSDictionary class]]) {
		NSString *thumb = obj[@"thumbnailUrl"];
		NSString *icon = obj[@"icon"];
		UIColor *accent = obj[@"color"] ?: [MLTheme primary];

		if (thumb.length > 0) {
			_iconBox.hidden = YES;
			_artView.hidden = NO;
			_artView.frame = CGRectMake(0, 0, width, width);
			_artView.layer.cornerRadius = 12.0f;
			[MLImageCache loadImageAtURLString:thumb intoView:_artView fitSize:_artView.frame.size cornerRadius:12.0f placeholder:[MLImageCache placeholderImageWithSize:_artView.frame.size]];

			if (icon.length > 0) {
				_badgeBox.hidden = NO;
				_badgeBox.frame = CGRectMake(width - 34.0f, width - 34.0f, 28.0f, 28.0f);
				_badgeIconView.image = [MLIcon icon:icon size:18.0f color:[UIColor whiteColor]];
			} else {
				_badgeBox.hidden = YES;
			}
		} else {
			_artView.hidden = YES;
			_artView.image = nil;
			_badgeBox.hidden = YES;
			_iconBox.hidden = NO;
			_iconBox.frame = CGRectMake(0, 0, width, width);
			_iconBox.layer.cornerRadius = 12.0f;
			_iconBox.backgroundColor = [accent colorWithAlphaComponent:0.18f];
			_iconView.frame = CGRectMake((width - 48.0f) / 2.0f, (width - 48.0f) / 2.0f, 48.0f, 48.0f);
			if (icon.length > 0) {
				_iconView.image = [MLIcon icon:icon size:36.0f color:accent];
			} else {
				_iconView.image = nil;
			}
		}

		_titleLabel.frame = CGRectMake(2.0f, width + 6.0f, width - 4.0f, 19.0f);
		_titleLabel.text = obj[@"title"];
		_titleLabel.textAlignment = NSTextAlignmentLeft;

		_subtitleLabel.frame = CGRectMake(2.0f, width + 26.0f, width - 4.0f, 16.0f);
		_subtitleLabel.text = obj[@"subtitle"];
		_subtitleLabel.textAlignment = NSTextAlignmentLeft;
	} else if ([obj isKindOfClass:[MLYTItem class]]) {
		MLYTItem *it = (MLYTItem *)obj;
		_iconBox.hidden = YES;
		_badgeBox.hidden = YES;
		_artView.hidden = NO;
		BOOL isArtist = (it.kind == MLYTKindArtist || [it.browseId hasPrefix:@"UC"]);
		_artView.frame = CGRectMake(0, 0, width, width);
		_artView.layer.cornerRadius = isArtist ? (width / 2.0f) : 12.0f;
		if (it.thumbnailUrl.length > 0) {
			[MLImageCache loadImageAtURLString:it.thumbnailUrl intoView:_artView fitSize:_artView.frame.size cornerRadius:_artView.layer.cornerRadius placeholder:[MLImageCache placeholderImageWithSize:_artView.frame.size]];
		} else {
			_artView.image = [MLImageCache placeholderImageWithSize:_artView.frame.size];
		}

		_titleLabel.frame = CGRectMake(2.0f, width + 6.0f, width - 4.0f, 19.0f);
		_titleLabel.text = it.title;
		_titleLabel.textAlignment = isArtist ? NSTextAlignmentCenter : NSTextAlignmentLeft;

		NSString *sub = it.subtitle.length ? it.subtitle : (it.artists.count ? [it.artists componentsJoinedByString:@", "] : @"");
		_subtitleLabel.frame = CGRectMake(2.0f, width + 26.0f, width - 4.0f, 16.0f);
		_subtitleLabel.text = sub;
		_subtitleLabel.textAlignment = isArtist ? NSTextAlignmentCenter : NSTextAlignmentLeft;
	}
}

@end

@interface MLLibraryGridRowCell : UITableViewCell
{
	MLLibraryGridItemView *_leftView;
	MLLibraryGridItemView *_rightView;
}
@property (nonatomic, copy) void (^onItemTapped)(id item);
- (void)fillWithLeftItem:(id)left rightItem:(id)right width:(CGFloat)width;
@end

@implementation MLLibraryGridRowCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;

		_leftView = [[MLLibraryGridItemView alloc] initWithFrame:CGRectZero];
		[_leftView addTarget:self action:@selector(leftTap) forControlEvents:UIControlEventTouchUpInside];
		[self.contentView addSubview:_leftView];

		_rightView = [[MLLibraryGridItemView alloc] initWithFrame:CGRectZero];
		[_rightView addTarget:self action:@selector(rightTap) forControlEvents:UIControlEventTouchUpInside];
		[self.contentView addSubview:_rightView];
	}
	return self;
}

- (void)leftTap
{
	if (_onItemTapped && _leftView.item) {
		_onItemTapped(_leftView.item);
	}
}

- (void)rightTap
{
	if (_onItemTapped && _rightView.item) {
		_onItemTapped(_rightView.item);
	}
}

- (void)fillWithLeftItem:(id)left rightItem:(id)right width:(CGFloat)width
{
	CGFloat pad = 12.0f;
	CGFloat gap = 10.0f;
	CGFloat rowH = width + 50.0f;

	_leftView.frame = CGRectMake(pad, 4.0f, width, rowH - 8.0f);
	[_leftView fillWithObject:left width:width];

	_rightView.frame = CGRectMake(pad + width + gap, 4.0f, width, rowH - 8.0f);
	[_rightView fillWithObject:right width:width];
}

@end

@interface MLLibraryViewController () <UIActionSheetDelegate, UIAlertViewDelegate>
{
	MLChipsRowView *_chipsRow;
	UIView *_subHeaderView;
	UIButton *_sortBtn;
	UIButton *_libSearchBtn;
	UIButton *_gridToggleBtn;
	BOOL _isGridView;

	UITableView *_table;
	UIRefreshControl *_refreshControl;
	MLLibFilter _activeFilter;
	MLLibSortOrder _sortOrder;

	// Flat list of rows (NSDictionary cards, NSDictionary section_header, or MLYTItem)
	NSArray *_flatRows;
	NSArray *_playableSongsInActiveFilter;
	BOOL _loadingAccount;
	NSDictionary *_selectedMenuCollectionEntry;
}
@end

@implementation MLLibraryViewController

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.backgroundColor = [MLTheme background];
}

- (void)dealloc
{
	_table.dataSource = nil;
	_table.delegate = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	[MLTheme setLeftNavigationTitle:MLLocalizedString(@"library_title", nil) forViewController:self];
	_activeFilter = MLLibFilterAll;
	_sortOrder = (MLLibSortOrder)[[NSUserDefaults standardUserDefaults] integerForKey:@"ml_lib_sort_order"];
	_isGridView = [[NSUserDefaults standardUserDefaults] boolForKey:@"ml_lib_view_grid"];

	[self setupNavButtons];

	CGFloat w = self.view.bounds.size.width;
	CGFloat h = self.view.bounds.size.height;

	_chipsRow = [[MLChipsRowView alloc] initWithFrame:CGRectMake(0, 0, w, 46.0f)];
	_chipsRow.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	__weak MLLibraryViewController *wself = self;
	_chipsRow.onChange = ^(MLChip *chip) {
		MLLibraryViewController *s = wself;
		if (!s) return;
		s->_activeFilter = (MLLibFilter)[chip.params integerValue];
		[s rebuildSections];
	};
	[self.view addSubview:_chipsRow];
	[self populateFilterChips];

	_subHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 46.0f, w, 36.0f)];
	_subHeaderView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_subHeaderView.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_subHeaderView];

	_sortBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_sortBtn.frame = CGRectMake(14.0f, 0, w - 90.0f, 36.0f);
	_sortBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_sortBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	_sortBtn.titleLabel.font = [MLTheme fontTitleSmall];
	[_sortBtn setTitleColor:[MLTheme primary] forState:UIControlStateNormal];
	[_sortBtn addTarget:self action:@selector(sortTapped:) forControlEvents:UIControlEventTouchUpInside];
	[_subHeaderView addSubview:_sortBtn];
	[self updateSortButtonTitle];

	_libSearchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_libSearchBtn.frame = CGRectMake(w - 74.0f, 2.0f, 32.0f, 32.0f);
	_libSearchBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[_libSearchBtn setImage:[MLIcon icon:@"search" size:18.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
	[_libSearchBtn addTarget:self action:@selector(libSearchTapped:) forControlEvents:UIControlEventTouchUpInside];
	[_subHeaderView addSubview:_libSearchBtn];

	_gridToggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_gridToggleBtn.frame = CGRectMake(w - 38.0f, 2.0f, 32.0f, 32.0f);
	_gridToggleBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self updateGridToggleButtonIcon];
	[_gridToggleBtn addTarget:self action:@selector(toggleGridTapped:) forControlEvents:UIControlEventTouchUpInside];
	[_subHeaderView addSubview:_gridToggleBtn];

	_table = [[UITableView alloc] initWithFrame:CGRectMake(0, 82.0f, w, h - 82.0f) style:UITableViewStylePlain];
	_table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_table.backgroundColor = [UIColor clearColor];
	_table.dataSource = self;
	_table.delegate = self;
	_table.separatorStyle = UITableViewCellSeparatorStyleNone;
	_table.contentInset = UIEdgeInsetsMake(2.0f, 0.0f, 16.0f, 0.0f);
	[self.view addSubview:_table];

	if ([UIRefreshControl class]) {
		_refreshControl = [[UIRefreshControl alloc] init];
		_refreshControl.tintColor = [MLTheme primary];
		[_refreshControl addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
		[_table addSubview:_refreshControl];
	}

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(reloadData) name:MLSessionChangedNotification object:nil];
	[nc addObserver:self selector:@selector(onLibraryUpdated:) name:MLLibraryDidUpdateNotification object:nil];
	[nc addObserver:self selector:@selector(onPlaybackChanged:) name:MLPlaybackStateChangedNotification object:nil];
	[nc addObserver:self selector:@selector(languageChanged:) name:MLLanguageChangedNotification object:nil];
	[nc addObserver:self selector:@selector(themeChanged:) name:MLThemeDidChangeNotification object:nil];

	[self reloadData];
}

- (void)updateSortButtonTitle
{
	NSString *title = nil;
	if (_sortOrder == MLLibSortName) {
		title = MLLocalizedString(@"sort_name", nil);
	} else if (_sortOrder == MLLibSortArtist) {
		title = MLLocalizedString(@"sort_artist", nil);
	} else {
		title = MLLocalizedString(@"sort_recent", nil);
	}
	[_sortBtn setTitle:[NSString stringWithFormat:@"%@  ↓", title] forState:UIControlStateNormal];
}

- (void)updateGridToggleButtonIcon
{
	NSString *iconName = _isGridView ? @"view_list" : @"grid_view";
	[_gridToggleBtn setImage:[MLIcon icon:iconName size:19.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
}

- (void)toggleGridTapped:(id)sender
{
	[MLTheme triggerImpactHaptic];
	_isGridView = !_isGridView;
	[[NSUserDefaults standardUserDefaults] setBool:_isGridView forKey:@"ml_lib_view_grid"];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[self updateGridToggleButtonIcon];
	[self rebuildSections];
}

- (void)libSearchTapped:(id)sender
{
	[MLTheme triggerImpactHaptic];
	UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
	if ([root isKindOfClass:[MLRootViewController class]]) {
		[(MLRootViewController *)root switchToTabIndex:1];
	}
}

- (UIBarButtonItem *)circleBarButtonWithIcon:(NSString *)iconName action:(SEL)action
{
	UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
	btn.frame = CGRectMake(0, 0, 32.0f, 32.0f);
	btn.backgroundColor = [MLTheme surfaceContainer];
	btn.layer.cornerRadius = 16.0f;
	btn.layer.borderWidth = 0.5f;
	btn.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.28f].CGColor;
	[btn setImage:[MLIcon icon:iconName size:18.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return [[UIBarButtonItem alloc] initWithCustomView:btn];
}

- (void)setupNavButtons
{
	UIBarButtonItem *accountItem = [MLAccountSettingsViewController barButtonItemForViewController:self];
	UIBarButtonItem *syncItem = [self circleBarButtonWithIcon:@"sync" action:@selector(syncTapped:)];
	UIBarButtonItem *addItem = [self circleBarButtonWithIcon:@"playlist_add" action:@selector(createPlaylistTapped:)];
	if ([self.navigationItem respondsToSelector:@selector(setRightBarButtonItems:)]) {
		self.navigationItem.rightBarButtonItems = @[ accountItem, syncItem, addItem ];
	} else {
		self.navigationItem.rightBarButtonItem = accountItem;
	}
}

- (void)sortTapped:(id)sender
{
	[MLTheme triggerImpactHaptic];
	__weak MLLibraryViewController *wself = self;

	NSArray *titles = @[
		MLLocalizedString(@"sort_recent", nil),
		MLLocalizedString(@"sort_name", nil),
		MLLocalizedString(@"sort_artist", nil)
	];
	NSArray *icons = @[@"history", @"sort", @"person"];

	NSMutableArray *items = [NSMutableArray array];
	for (NSUInteger i = 0; i < titles.count; i++) {
		BOOL isSel = (_sortOrder == (MLLibSortOrder)i);
		MLBottomSheetItem *it = [MLBottomSheetItem radioItemWithTitle:titles[i]
		                                                     subtitle:nil
		                                                     selected:isSel
		                                                      handler:^{
			MLLibraryViewController *sself = wself;
			if (!sself) return;
			sself->_sortOrder = (MLLibSortOrder)i;
			[[NSUserDefaults standardUserDefaults] setInteger:sself->_sortOrder forKey:@"ml_lib_sort_order"];
			[[NSUserDefaults standardUserDefaults] synchronize];
			[sself updateSortButtonTitle];
			[sself rebuildSections];
		}];
		it.iconName = icons[i];
		[items addObject:it];
	}

	MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:MLLocalizedString(@"sort_by", nil) items:items];
	[menu showInView:self.view];
}

- (void)populateFilterChips
{
	NSArray *titles = @[
		MLLocalizedString(@"lib_filter_all", nil),
		MLLocalizedString(@"lib_filter_playlists", nil),
		MLLocalizedString(@"lib_filter_songs", nil),
		MLLocalizedString(@"lib_filter_albums", nil),
		MLLocalizedString(@"lib_filter_artists", nil),
		MLLocalizedString(@"lib_filter_downloaded", nil),
	];
	NSMutableArray *chips = [NSMutableArray arrayWithCapacity:titles.count];
	for (NSUInteger i = 0; i < titles.count; i++) {
		MLChip *c = [[MLChip alloc] init];
		c.title = titles[i];
		c.params = [NSString stringWithFormat:@"%lu", (unsigned long)i];
		c.selected = (i == (NSUInteger)_activeFilter);
		[chips addObject:c];
	}
	[_chipsRow setChips:chips];
	[_chipsRow setSelectedIndex:(NSUInteger)_activeFilter];
}

- (void)languageChanged:(NSNotification *)note
{
	[MLTheme setLeftNavigationTitle:MLLocalizedString(@"library_title", nil) forViewController:self];
	[self populateFilterChips];
	[self updateSortButtonTitle];
	[self rebuildSections];
}

- (void)onLibraryUpdated:(NSNotification *)note
{
	if (![MLLibraryManager sharedManager].isSyncing && _refreshControl.isRefreshing) {
		[_refreshControl endRefreshing];
	}
	[self rebuildSections];
}

- (void)onPlaybackChanged:(NSNotification *)note
{
	static NSString *lastVideoId = nil;
	NSString *curId = [MLPlaybackManager sharedManager].currentItem.videoId ?: @"";
	if ([curId isEqualToString:lastVideoId ?: @""])
		return;
	lastVideoId = [curId copy];
	[_table reloadData];
}

- (void)themeChanged:(NSNotification *)note
{
	self.view.backgroundColor = [MLTheme background];
	_table.backgroundColor = [MLTheme background];
	[_sortBtn setTitleColor:[MLTheme primary] forState:UIControlStateNormal];
	if (_refreshControl) {
		_refreshControl.tintColor = [MLTheme primary];
	}
	[self setupNavButtons];
	[_table reloadData];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[MLTheme resetNavigationBarForNavigationController:self.navigationController];
	[self rebuildSections];
}

- (void)pullToRefresh:(id)sender
{
	if (![[MLInnerTube sharedClient] loggedIn]) {
		[_refreshControl endRefreshing];
		return;
	}
	[[MLLibraryManager sharedManager] syncWithYouTubeMusicCompletion:^(BOOL ok, NSString *error) {
		[_refreshControl endRefreshing];
	}];
}

- (void)syncTapped:(id)sender
{
	if (![[MLInnerTube sharedClient] loggedIn]) {
		MLLoginViewController *login = [[MLLoginViewController alloc] init];
		[self presentViewController:login animated:YES completion:nil];
		return;
	}
	[[MLLibraryManager sharedManager] syncWithYouTubeMusicCompletion:nil];
}

- (void)createPlaylistTapped:(id)sender
{
	if (![[MLInnerTube sharedClient] loggedIn]) {
		MLLoginViewController *login = [[MLLoginViewController alloc] init];
		[self presentViewController:login animated:YES completion:nil];
		return;
	}
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:MLLocalizedString(@"new_playlist", nil)
	                                                message:nil
	                                               delegate:self
	                                      cancelButtonTitle:MLLocalizedString(@"cancel", nil)
	                                      otherButtonTitles:MLLocalizedString(@"create", nil), nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	UITextField *tf = [alert textFieldAtIndex:0];
	tf.placeholder = MLLocalizedString(@"playlist_name_placeholder", nil);
	alert.tag = 501;
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (alertView.tag == 501 && buttonIndex != alertView.cancelButtonIndex) {
		UITextField *tf = [alertView textFieldAtIndex:0];
		NSString *title = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (title.length > 0) {
			[[MLInnerTube sharedClient] createPlaylistWithTitle:title completion:^(NSString *playlistId, NSString *error) {
				[[MLLibraryManager sharedManager] syncWithYouTubeMusicCompletion:nil];
			}];
		}
	}
}

- (NSString *)songsCountSubtitle:(NSUInteger)count
{
	static NSNumberFormatter *formatter = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSNumberFormatter alloc] init];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
	});
	NSString *numStr = [formatter stringFromNumber:@(count)] ?: [NSString stringWithFormat:@"%lu", (unsigned long)count];
	NSString *fmt = (count == 1) ? MLLocalizedString(@"songs_count_single", nil) : MLLocalizedString(@"songs_count_plural", nil);
	return [fmt stringByReplacingOccurrencesOfString:@"%lu" withString:numStr];
}

- (NSString *)firstThumbnailInSongs:(NSArray *)songs
{
	for (MLYTItem *it in songs) {
		if (it.thumbnailUrl.length > 0) {
			return it.thumbnailUrl;
		}
	}
	return @"";
}

- (NSArray *)songsForCollectionType:(NSString *)type
{
	MLLibraryManager *lib = [MLLibraryManager sharedManager];
	if ([type isEqualToString:@"liked"]) return lib.likedSongs;
	if ([type isEqualToString:@"top50"]) return lib.top50Songs;
	if ([type isEqualToString:@"downloaded"]) return lib.downloadedSongs;
	if ([type isEqualToString:@"cached"]) return lib.cachedSongs;
	if ([type isEqualToString:@"history"]) return lib.historySongs;
	return nil;
}

- (void)presentCollectionMenuForEntry:(NSDictionary *)entry
{
	[MLTheme triggerImpactHaptic];
	NSString *type = entry[@"type"];
	NSString *title = entry[@"title"] ?: @"";
	NSArray *songs = [self songsForCollectionType:type];

	NSMutableArray *items = [NSMutableArray array];
	if (songs.count > 0) {
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"play_all", nil)
		                                         iconName:@"play_arrow"
		                                          handler:^{
			[[MLPlaybackManager sharedManager] playQueue:songs startIndex:0];
		}]];

		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"shuffle_all", nil)
		                                         iconName:@"shuffle"
		                                          handler:^{
			[[MLPlaybackManager sharedManager] playShuffledQueue:songs];
		}]];
	}
	if ([type isEqualToString:@"cached"] && [MLLibraryManager sharedManager].cachedSongs.count > 0) {
		__weak MLLibraryViewController *wself = self;
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"clear_cache", nil)
		                                         subtitle:nil
		                                         iconName:@"delete"
		                                    isDestructive:YES
		                                          handler:^{
			[[MLLibraryManager sharedManager] clearAudioCache];
			[wself rebuildSections];
		}]];
	}

	MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:title items:items];
	[menu showInView:self.view];
}

- (NSArray *)autoPlaylistCards
{
	MLLibraryManager *lib = [MLLibraryManager sharedManager];
	NSUInteger likedCount = lib.totalLikedSongsCount > 0 ? lib.totalLikedSongsCount : lib.likedSongs.count;
	NSUInteger top50Count = lib.top50Songs.count;
	NSUInteger dlCount = lib.downloadedSongs.count;
	NSUInteger cacheCount = lib.cachedSongs.count;
	NSUInteger histCount = lib.historySongs.count;

	NSString *dlSize = [lib formattedSizeForBytes:[lib downloadedTotalBytes]];
	NSString *cacheSize = [lib formattedSizeForBytes:[lib audioCacheTotalBytes]];

	NSString *autoSub = MLLocalizedString(@"liked_songs_sub", nil);

	NSString *likedSub = likedCount > 0 ? [NSString stringWithFormat:@"%@ • %@", autoSub, [self songsCountSubtitle:likedCount]] : autoSub;
	NSString *top50Sub = top50Count > 0 ? [NSString stringWithFormat:@"%@ • %@", autoSub, [self songsCountSubtitle:top50Count]] : autoSub;
	NSString *dlSub = dlCount > 0 ? [NSString stringWithFormat:@"%@ • %@", [self songsCountSubtitle:dlCount], dlSize] : MLLocalizedString(@"downloaded_songs_sub", nil);
	NSString *cacheSub = cacheCount > 0 ? [NSString stringWithFormat:@"%@ • %@", [self songsCountSubtitle:cacheCount], cacheSize] : MLLocalizedString(@"cached_songs_sub", nil);
	NSString *histSub = histCount > 0 ? [NSString stringWithFormat:@"%@ • %@", autoSub, [self songsCountSubtitle:histCount]] : MLLocalizedString(@"history_songs_sub", nil);

	return @[
		@{
			@"type" : @"liked",
			@"title" : MLLocalizedString(@"liked_songs", nil),
			@"subtitle" : likedSub,
			@"icon" : @"favorite",
			@"color" : [MLTheme primary],
			@"thumbnailUrl" : [self firstThumbnailInSongs:lib.likedSongs],
		},
		@{
			@"type" : @"top50",
			@"title" : MLLocalizedString(@"my_top_50", nil),
			@"subtitle" : top50Sub,
			@"icon" : @"trending_up",
			@"color" : [UIColor colorWithRed:0.95f green:0.60f blue:0.18f alpha:1.0f],
			@"thumbnailUrl" : [self firstThumbnailInSongs:lib.top50Songs],
		},
		@{
			@"type" : @"downloaded",
			@"title" : MLLocalizedString(@"downloaded_songs", nil),
			@"subtitle" : dlSub,
			@"icon" : @"download_done",
			@"color" : [UIColor colorWithRed:0.18f green:0.65f blue:0.45f alpha:1.0f],
			@"thumbnailUrl" : [self firstThumbnailInSongs:lib.downloadedSongs],
		},
		@{
			@"type" : @"cached",
			@"title" : MLLocalizedString(@"cached_songs", nil),
			@"subtitle" : cacheSub,
			@"icon" : @"cached",
			@"color" : [UIColor colorWithRed:0.22f green:0.52f blue:0.85f alpha:1.0f],
			@"thumbnailUrl" : [self firstThumbnailInSongs:lib.cachedSongs],
		},
		@{
			@"type" : @"history",
			@"title" : MLLocalizedString(@"history_songs", nil),
			@"subtitle" : histSub,
			@"icon" : @"history",
			@"color" : [UIColor colorWithRed:0.58f green:0.38f blue:0.82f alpha:1.0f],
			@"thumbnailUrl" : [self firstThumbnailInSongs:lib.historySongs],
		},
	];
}

- (void)appendSectionTitle:(NSString *)title rows:(NSArray *)rows into:(NSMutableArray *)flat
{
	if (!rows.count) return;
	if (title.length > 0) {
		[flat addObject:@{ @"type" : @"section_header", @"title" : title }];
	}
	if (!_isGridView) {
		[flat addObjectsFromArray:rows];
	} else {
		for (NSUInteger i = 0; i < rows.count; i += 2) {
			id left = rows[i];
			id right = (i + 1 < rows.count) ? rows[i + 1] : nil;
			[flat addObject:@{
				@"type" : @"grid_row",
				@"left" : left,
				@"right" : right ?: [NSNull null],
			}];
		}
	}
}

- (NSArray *)sortedItems:(NSArray *)items
{
	if (!items.count || _sortOrder == MLLibSortRecent)
		return items;

	return [items sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		if (![obj1 isKindOfClass:[MLYTItem class]] || ![obj2 isKindOfClass:[MLYTItem class]])
			return NSOrderedSame;
		MLYTItem *it1 = (MLYTItem *)obj1;
		MLYTItem *it2 = (MLYTItem *)obj2;
		if (_sortOrder == MLLibSortName) {
			NSString *s1 = it1.title ?: @"";
			NSString *s2 = it2.title ?: @"";
			return [s1 localizedCaseInsensitiveCompare:s2];
		} else if (_sortOrder == MLLibSortArtist) {
			NSString *s1 = it1.subtitle ?: @"";
			NSString *s2 = it2.subtitle ?: @"";
			NSComparisonResult res = [s1 localizedCaseInsensitiveCompare:s2];
			if (res == NSOrderedSame) {
				return [(it1.title ?: @"") localizedCaseInsensitiveCompare:(it2.title ?: @"")];
			}
			return res;
		}
		return NSOrderedSame;
	}];
}

- (void)rebuildSections
{
	MLLibraryManager *lib = [MLLibraryManager sharedManager];
	NSMutableArray *flat = [NSMutableArray array];
	_playableSongsInActiveFilter = nil;

	NSArray *playlists = [self sortedItems:lib.syncedPlaylists];
	NSArray *albums = [self sortedItems:lib.syncedAlbums];
	NSArray *artists = [self sortedItems:lib.syncedArtists];

	if (_activeFilter == MLLibFilterAll) {
		[self appendSectionTitle:MLLocalizedString(@"auto_playlists_section", nil) rows:[self autoPlaylistCards] into:flat];
		[self appendSectionTitle:MLLocalizedString(@"playlists_section", nil) rows:playlists into:flat];
		[self appendSectionTitle:MLLocalizedString(@"albums_section", nil) rows:albums into:flat];
		[self appendSectionTitle:MLLocalizedString(@"artists_section", nil) rows:artists into:flat];
	} else if (_activeFilter == MLLibFilterPlaylists) {
		[self appendSectionTitle:MLLocalizedString(@"auto_playlists_section", nil) rows:[self autoPlaylistCards] into:flat];
		[self appendSectionTitle:MLLocalizedString(@"playlists_section", nil) rows:playlists into:flat];
	} else if (_activeFilter == MLLibFilterSongs) {
		NSMutableArray *allSongs = [NSMutableArray array];
		NSMutableSet *seen = [NSMutableSet set];
		for (MLYTItem *it in lib.likedSongs) {
			if (it.videoId.length && ![seen containsObject:it.videoId]) {
				[seen addObject:it.videoId];
				[allSongs addObject:it];
			}
		}
		for (MLYTItem *it in lib.syncedSongs) {
			if (it.videoId.length && ![seen containsObject:it.videoId]) {
				[seen addObject:it.videoId];
				[allSongs addObject:it];
			}
		}
		NSArray *sortedSongs = [self sortedItems:allSongs];
		_playableSongsInActiveFilter = sortedSongs;
		[self appendSectionTitle:MLLocalizedString(@"lib_filter_songs", nil) rows:sortedSongs into:flat];
	} else if (_activeFilter == MLLibFilterAlbums) {
		[self appendSectionTitle:MLLocalizedString(@"albums_section", nil) rows:albums into:flat];
	} else if (_activeFilter == MLLibFilterArtists) {
		[self appendSectionTitle:MLLocalizedString(@"artists_section", nil) rows:artists into:flat];
	} else if (_activeFilter == MLLibFilterDownloaded) {
		if (lib.cachedSongs.count > 0) {
			NSString *cacheSize = [lib formattedSizeForBytes:[lib audioCacheTotalBytes]];
			[self appendSectionTitle:nil rows:@[
				@{
					@"type" : @"cached",
					@"title" : MLLocalizedString(@"cached_songs", nil),
					@"subtitle" : [NSString stringWithFormat:@"%@ • %@", [self songsCountSubtitle:lib.cachedSongs.count], cacheSize],
					@"icon" : @"cached",
					@"color" : [UIColor colorWithRed:0.22f green:0.52f blue:0.85f alpha:1.0f],
					@"thumbnailUrl" : [self firstThumbnailInSongs:lib.cachedSongs],
				}
			] into:flat];
		}
		NSArray *sortedDl = [self sortedItems:lib.downloadedSongs];
		_playableSongsInActiveFilter = sortedDl;
		[self appendSectionTitle:MLLocalizedString(@"downloaded_songs", nil) rows:sortedDl into:flat];
	}

	_flatRows = flat;
	[_table reloadData];
}

- (void)reloadData
{
	[self rebuildSections];

	if (![MLInnerTube sharedClient].loggedIn || _loadingAccount)
		return;
	_loadingAccount = YES;
	__weak MLLibraryViewController *wself = self;
	[[MLInnerTube sharedClient] accountMenu:^(NSDictionary *info, NSString *err) {
		MLLibraryViewController *s = wself;
		if (!s) return;
		s->_loadingAccount = NO;
		[s rebuildSections];
	}];
}

#pragma mark - Table Data Source & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _flatRows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	id item = _flatRows[indexPath.row];
	if ([item isKindOfClass:[NSDictionary class]]) {
		NSString *type = item[@"type"];
		if ([type isEqualToString:@"section_header"]) {
			return 34.0f;
		}
		if ([type isEqualToString:@"grid_row"]) {
			CGFloat w = tableView.bounds.size.width;
			CGFloat pad = 12.0f;
			CGFloat gap = 10.0f;
			CGFloat colW = floorf((w - (pad * 2.0f) - gap) / 2.0f);
			return colW + 50.0f;
		}
		return MLLengthListItem;
	}
	return MLLengthListItem;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	id rowObj = _flatRows[indexPath.row];
	if ([rowObj isKindOfClass:[NSDictionary class]]) {
		NSString *type = rowObj[@"type"];
		if ([type isEqualToString:@"section_header"]) {
			UITableViewCell *hdrCell = [tableView dequeueReusableCellWithIdentifier:@"lib_sec_hdr"];
			if (!hdrCell) {
				hdrCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"lib_sec_hdr"];
				hdrCell.backgroundColor = [UIColor clearColor];
				hdrCell.selectionStyle = UITableViewCellSelectionStyleNone;
				UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16.0f, 10.0f, 280.0f, 18.0f)];
				lbl.tag = 901;
				lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
				lbl.font = [MLTheme fontTitleSmall];
				lbl.textColor = [MLTheme onSurfaceVariant];
				lbl.backgroundColor = [UIColor clearColor];
				[hdrCell.contentView addSubview:lbl];
			}
			UILabel *lbl = (UILabel *)[hdrCell.contentView viewWithTag:901];
			lbl.text = [rowObj[@"title"] uppercaseString];
			return hdrCell;
		}

		if ([type isEqualToString:@"grid_row"]) {
			MLLibraryGridRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"lib_grid_row"];
			if (!cell) {
				cell = [[MLLibraryGridRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"lib_grid_row"];
			}
			CGFloat w = tableView.bounds.size.width;
			CGFloat pad = 12.0f;
			CGFloat gap = 10.0f;
			CGFloat colW = floorf((w - (pad * 2.0f) - gap) / 2.0f);
			id left = rowObj[@"left"];
			id right = rowObj[@"right"];
			if (right == [NSNull null]) right = nil;
			__weak MLLibraryViewController *wself = self;
			cell.onItemTapped = ^(id tappedItem) {
				[wself handleItemSelection:tappedItem];
			};
			[cell fillWithLeftItem:left rightItem:right width:colW];
			return cell;
		}

		MLLibraryCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"lib_card"];
		if (!cell) {
			cell = [[MLLibraryCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"lib_card"];
		}
		[cell fillWithEntry:(NSDictionary *)rowObj];
		__weak MLLibraryViewController *wself = self;
		cell.moreTapped = ^(NSDictionary *entry) {
			[wself presentCollectionMenuForEntry:entry];
		};
		return cell;
	}

	MLSongCell *cell = [tableView dequeueReusableCellWithIdentifier:@"lib_item"];
	if (!cell) {
		cell = [[MLSongCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"lib_item"];
	}
	MLYTItem *it = (MLYTItem *)rowObj;
	BOOL isPlaying = (it.videoId.length > 0 && [it.videoId isEqualToString:[MLPlaybackManager sharedManager].currentItem.videoId]);
	[cell fillWithItem:it isPlaying:isPlaying];
	__weak MLLibraryViewController *wself = self;
	cell.moreTapped = ^(MLYTItem *tapped) {
		[MLNavigator presentSongMenuForItem:tapped fromViewController:wself];
	};
	return cell;
}

- (void)handleItemSelection:(id)rowObj
{
	if (!rowObj || [rowObj isKindOfClass:[NSNull class]]) return;

	if ([rowObj isKindOfClass:[MLYTItem class]]) {
		MLYTItem *it = (MLYTItem *)rowObj;
		if ((_activeFilter == MLLibFilterSongs || _activeFilter == MLLibFilterDownloaded) && it.videoId.length > 0 && _playableSongsInActiveFilter.count > 0) {
			NSUInteger songIdx = [_playableSongsInActiveFilter indexOfObject:it];
			if (songIdx == NSNotFound) songIdx = 0;
			[[MLPlaybackManager sharedManager] playQueue:_playableSongsInActiveFilter startIndex:songIdx];
		} else {
			[MLNavigator openItem:it fromViewController:self];
		}
		return;
	}

	NSDictionary *entry = (NSDictionary *)rowObj;
	NSString *type = entry[@"type"];
	if ([type isEqualToString:@"section_header"] || [type isEqualToString:@"grid_row"]) {
		return;
	}
	if ([type isEqualToString:@"login"]) {
		MLLoginViewController *login = [[MLLoginViewController alloc] init];
		[self presentViewController:login animated:YES completion:nil];
	} else if ([type isEqualToString:@"token"]) {
		MLTokenEditorViewController *editor = [[MLTokenEditorViewController alloc] init];
		__weak MLLibraryViewController *wself = self;
		editor.completionHandler = ^(BOOL loggedIn) {
			[wself reloadData];
		};
		UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
		if ([nav.navigationBar respondsToSelector:@selector(setTranslucent:)]) {
			nav.navigationBar.translucent = NO;
		}
		[self presentViewController:nav animated:YES completion:nil];
	} else if ([type isEqualToString:@"liked"]) {
		MLListDetailViewController *list = [[MLListDetailViewController alloc] initWithLikedSongs];
		[self.navigationController pushViewController:list animated:YES];
	} else if ([type isEqualToString:@"top50"]) {
		MLListDetailViewController *list = [[MLListDetailViewController alloc] initWithTop50Songs];
		[self.navigationController pushViewController:list animated:YES];
	} else if ([type isEqualToString:@"downloaded"]) {
		MLListDetailViewController *list = [[MLListDetailViewController alloc] initWithDownloadedSongs];
		[self.navigationController pushViewController:list animated:YES];
	} else if ([type isEqualToString:@"cached"]) {
		MLListDetailViewController *list = [[MLListDetailViewController alloc] initWithCachedSongs];
		[self.navigationController pushViewController:list animated:YES];
	} else if ([type isEqualToString:@"history"]) {
		MLListDetailViewController *list = [[MLListDetailViewController alloc] initWithHistorySongs];
		[self.navigationController pushViewController:list animated:YES];
	} else if ([type isEqualToString:@"sync"]) {
		[[MLLibraryManager sharedManager] syncWithYouTubeMusicCompletion:nil];
	} else if ([type isEqualToString:@"clear_cache"]) {
		[[MLLibraryManager sharedManager] clearAudioCache];
	} else if ([type isEqualToString:@"language"]) {
		NSString *currentPref = [MLLocalization sharedManager].languagePreference ?: @"system";
		NSArray *codes = @[@"system", @"es", @"en", @"ru"];
		NSArray *names = @[
			MLLocalizedString(@"lang_system", nil),
			MLLocalizedString(@"lang_es", nil),
			MLLocalizedString(@"lang_en", nil),
			MLLocalizedString(@"lang_ru", nil)
		];
		NSMutableArray *items = [NSMutableArray array];
		for (NSUInteger i = 0; i < codes.count; i++) {
			NSString *code = codes[i];
			BOOL isSel = [currentPref isEqualToString:code];
			MLBottomSheetItem *it = [MLBottomSheetItem radioItemWithTitle:names[i]
			                                                     subtitle:nil
			                                                     selected:isSel
			                                                      handler:^{
				[[MLLocalization sharedManager] setLanguagePreference:code];
			}];
			it.iconName = @"language";
			[items addObject:it];
		}
		MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:MLLocalizedString(@"select_language", nil) items:items];
		[menu showInView:self.view];
	} else if ([type isEqualToString:@"logout"]) {
		[[MLInnerTube sharedClient] clearSession];
		[self reloadData];
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	id rowObj = _flatRows[indexPath.row];
	[self handleItemSelection:rowObj];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (actionSheet.tag == 601) {
		if (buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex)
			return;
		[MLTheme triggerImpactHaptic];
		_sortOrder = (MLLibSortOrder)buttonIndex;
		[[NSUserDefaults standardUserDefaults] setInteger:_sortOrder forKey:@"ml_lib_sort_order"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		[self updateSortButtonTitle];
		[self rebuildSections];
		return;
	}
	if (actionSheet.tag == 701) {
		if (buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) {
			_selectedMenuCollectionEntry = nil;
			return;
		}
		[MLTheme triggerImpactHaptic];
		NSString *btnTitle = [actionSheet buttonTitleAtIndex:buttonIndex];
		NSString *type = _selectedMenuCollectionEntry[@"type"];
		NSArray *songs = [self songsForCollectionType:type];
		_selectedMenuCollectionEntry = nil;

		if ([btnTitle isEqualToString:MLLocalizedString(@"play_all", nil)]) {
			if (songs.count > 0) {
				[[MLPlaybackManager sharedManager] playQueue:songs startIndex:0];
			}
		} else if ([btnTitle isEqualToString:MLLocalizedString(@"shuffle_all", nil)]) {
			if (songs.count > 0) {
				[[MLPlaybackManager sharedManager] playShuffledQueue:songs];
			}
		} else if ([btnTitle isEqualToString:MLLocalizedString(@"clear_cache", nil)]) {
			[[MLLibraryManager sharedManager] clearAudioCache];
			[self rebuildSections];
		}
		return;
	}
	NSString *chosen = nil;
	if (buttonIndex == 0) {
		chosen = @"auto";
	} else if (buttonIndex == 1) {
		chosen = @"es";
	} else if (buttonIndex == 2) {
		chosen = @"en";
	} else if (buttonIndex == 3) {
		chosen = @"ru";
	}
	if (chosen) {
		[[MLLocalization sharedManager] setLanguagePreference:chosen];
	}
}

@end
