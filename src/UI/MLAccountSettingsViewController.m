#import "MLAccountSettingsViewController.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLImageCache.h"
#import "MLInnerTube.h"
#import "MLLibraryManager.h"
#import "MLSponsorBlockManager.h"
#import "MLLocalization.h"
#import "MLLoginViewController.h"
#import "MLTokenEditorViewController.h"
#import "MLListDetailViewController.h"
#import "MLRootViewController.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Navbar Circular Profile Avatar Button

@implementation MLAccountBarButton
{
	__weak UIViewController *_targetVC;
	UIImageView *_avatarView;
	NSString *_lastLoadedPhotoUrl;
	BOOL _requestedAccountMenu;
}

- (id)initWithTargetViewController:(UIViewController *)targetVC
{
	self = [super initWithFrame:CGRectMake(0, 0, 32.0f, 32.0f)];
	if (self) {
		_targetVC = targetVC;
		self.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
		self.layer.cornerRadius = 16.0f;
		self.layer.borderWidth = 1.0f;
		self.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.18f].CGColor;
		self.clipsToBounds = YES;

		_avatarView = [[UIImageView alloc] initWithFrame:self.bounds];
		_avatarView.contentMode = UIViewContentModeCenter;
		_avatarView.userInteractionEnabled = NO;
		[self addSubview:_avatarView];

		[self addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];

		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(onSessionChanged:)
		                                             name:MLSessionChangedNotification
		                                           object:nil];
		[self reloadAvatar];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setHighlighted:(BOOL)highlighted
{
	[super setHighlighted:highlighted];
	self.alpha = highlighted ? 0.65f : 1.0f;
}

- (void)onSessionChanged:(NSNotification *)note
{
	_lastLoadedPhotoUrl = nil;
	[self reloadAvatar];
}

- (void)reloadAvatar
{
	MLInnerTube *yt = [MLInnerTube sharedClient];
	if (yt.loggedIn) {
		self.layer.borderColor = [[MLTheme primary] colorWithAlphaComponent:0.65f].CGColor;
		NSString *photoUrl = yt.accountPhotoUrl;
		if (photoUrl.length > 0) {
			if (![photoUrl isEqualToString:_lastLoadedPhotoUrl]) {
				_lastLoadedPhotoUrl = [photoUrl copy];
				_avatarView.contentMode = UIViewContentModeScaleAspectFill;
				UIImage *fallback = [MLIcon icon:@"person" size:18.0f color:[MLTheme primary]];
				[MLImageCache loadImageAtURLString:photoUrl
				                          intoView:_avatarView
				                           fitSize:CGSizeMake(32.0f, 32.0f)
				                      cornerRadius:16.0f
				                       placeholder:fallback];
			}
		} else {
			_lastLoadedPhotoUrl = nil;
			_avatarView.contentMode = UIViewContentModeCenter;
			_avatarView.image = [MLIcon icon:@"person" size:18.0f color:[MLTheme primary]];
			if (!_requestedAccountMenu) {
				_requestedAccountMenu = YES;
				[yt accountMenu:nil];
			}
		}
	} else {
		_lastLoadedPhotoUrl = nil;
		_requestedAccountMenu = NO;
		self.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.18f].CGColor;
		_avatarView.contentMode = UIViewContentModeCenter;
		_avatarView.image = [MLIcon icon:@"person" size:18.0f color:[MLTheme onSurface]];
	}
}

- (void)handleTap
{
	if (_targetVC) {
		[MLAccountSettingsViewController presentFromViewController:_targetVC];
	}
}

@end

#pragma mark - Account Header Cell (Metrolist Profile Card)

@interface MLAccountProfileCell : UITableViewCell
@property (nonatomic, copy) void (^logoutTapped)(void);
- (void)fillWithName:(NSString *)name subtitle:(NSString *)subtitle photoUrl:(NSString *)photoUrl;
@end

@implementation MLAccountProfileCell
{
	UIView *_card;
	UIImageView *_avatar;
	UILabel *_nameLabel;
	UILabel *_subLabel;
	UIButton *_logoutBtn;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;

		_card = [[UIView alloc] initWithFrame:CGRectZero];
		_card.backgroundColor = [MLTheme surfaceContainerHigh];
		_card.layer.cornerRadius = 18.0f;
		_card.layer.borderWidth = 0.5f;
		_card.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.22f].CGColor;
		[self.contentView addSubview:_card];

		_avatar = [[UIImageView alloc] initWithFrame:CGRectMake(14.0f, 14.0f, 46.0f, 46.0f)];
		_avatar.backgroundColor = [[MLTheme primary] colorWithAlphaComponent:0.18f];
		_avatar.layer.cornerRadius = 23.0f;
		_avatar.clipsToBounds = YES;
		_avatar.contentMode = UIViewContentModeCenter;
		[_card addSubview:_avatar];

		_nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_nameLabel.font = [MLTheme fontTitleMedium];
		_nameLabel.textColor = [MLTheme onSurface];
		_nameLabel.backgroundColor = [UIColor clearColor];
		[_card addSubview:_nameLabel];

		_subLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subLabel.font = [MLTheme fontBodySmall];
		_subLabel.textColor = [MLTheme onSurfaceVariant];
		_subLabel.backgroundColor = [UIColor clearColor];
		[_card addSubview:_subLabel];

		_logoutBtn = [UIButton buttonWithType:UIButtonTypeCustom];
		_logoutBtn.backgroundColor = [MLTheme surfaceContainer];
		_logoutBtn.layer.cornerRadius = 16.0f;
		_logoutBtn.layer.borderWidth = 1.0f;
		_logoutBtn.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.35f].CGColor;
		_logoutBtn.titleLabel.font = [MLTheme fontLabelMedium];
		[_logoutBtn setTitleColor:[MLTheme onSurface] forState:UIControlStateNormal];
		[_logoutBtn addTarget:self action:@selector(onLogoutTap) forControlEvents:UIControlEventTouchUpInside];
		[_card addSubview:_logoutBtn];
	}
	return self;
}

- (void)onLogoutTap
{
	if (_logoutTapped)
		_logoutTapped();
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_card.frame = CGRectMake(14.0f, 4.0f, b.size.width - 28.0f, b.size.height - 8.0f);
	CGFloat cw = _card.bounds.size.width;
	CGFloat ch = _card.bounds.size.height;

	_avatar.frame = CGRectMake(14.0f, (ch - 46.0f) / 2.0f, 46.0f, 46.0f);

	NSString *logoutTitle = MLLocalizedString(@"sign_out", nil);
	[_logoutBtn setTitle:logoutTitle forState:UIControlStateNormal];
	CGSize ts = [logoutTitle sizeWithFont:_logoutBtn.titleLabel.font];
	CGFloat btnW = MAX(76.0f, ts.width + 24.0f);
	_logoutBtn.frame = CGRectMake(cw - btnW - 12.0f, (ch - 32.0f) / 2.0f, btnW, 32.0f);

	CGFloat textX = 72.0f;
	CGFloat textW = MAX(40.0f, _logoutBtn.frame.origin.x - textX - 8.0f);
	if (_subLabel.text.length > 0) {
		_nameLabel.frame = CGRectMake(textX, (ch / 2.0f) - 18.0f, textW, 20.0f);
		_subLabel.frame = CGRectMake(textX, (ch / 2.0f) + 3.0f, textW, 16.0f);
		_subLabel.hidden = NO;
	} else {
		_nameLabel.frame = CGRectMake(textX, (ch - 20.0f) / 2.0f, textW, 20.0f);
		_subLabel.hidden = YES;
	}
}

- (void)fillWithName:(NSString *)name subtitle:(NSString *)subtitle photoUrl:(NSString *)photoUrl
{
	_nameLabel.text = name;
	_subLabel.text = subtitle;
	UIImage *fallback = [MLIcon icon:@"person" size:24.0f color:[MLTheme primary]];
	if (photoUrl.length > 0) {
		_avatar.contentMode = UIViewContentModeScaleAspectFill;
		[MLImageCache loadImageAtURLString:photoUrl
		                          intoView:_avatar
		                           fitSize:CGSizeMake(46.0f, 46.0f)
		                      cornerRadius:23.0f
		                       placeholder:fallback];
	} else {
		_avatar.contentMode = UIViewContentModeCenter;
		_avatar.image = fallback;
	}
	[self setNeedsLayout];
}

@end

#pragma mark - Settings Row Card Cell

@interface MLSettingsRowCell : UITableViewCell
@property (nonatomic, copy) void (^switchChanged)(BOOL on);
- (void)fillWithSpec:(NSDictionary *)spec;
@end

@implementation MLSettingsRowCell
{
	UIView *_card;
	UIView *_iconCircle;
	UIImageView *_iconView;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UIImageView *_chevronView;
	UISwitch *_switchView;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;

		_card = [[UIView alloc] initWithFrame:CGRectZero];
		_card.backgroundColor = [MLTheme surfaceContainer];
		_card.layer.cornerRadius = 14.0f;
		_card.layer.borderWidth = 0.5f;
		_card.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.18f].CGColor;
		[self.contentView addSubview:_card];

		_iconCircle = [[UIView alloc] initWithFrame:CGRectMake(12.0f, 9.0f, 40.0f, 40.0f)];
		_iconCircle.layer.cornerRadius = 12.0f;
		[_card addSubview:_iconCircle];

		_iconView = [[UIImageView alloc] initWithFrame:CGRectMake(9.0f, 9.0f, 22.0f, 22.0f)];
		_iconView.contentMode = UIViewContentModeCenter;
		[_iconCircle addSubview:_iconView];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = [MLTheme fontTitleSmall];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[_card addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.font = [MLTheme fontBodySmall];
		_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		[_card addSubview:_subtitleLabel];

		_chevronView = [[UIImageView alloc] initWithImage:[MLIcon icon:@"chevron_right" size:20.0f color:[MLTheme onSurfaceVariant]]];
		[_card addSubview:_chevronView];

		_switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
		if ([_switchView respondsToSelector:@selector(setOnTintColor:)]) {
			_switchView.onTintColor = [MLTheme primary];
		}
		[_switchView addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
		_switchView.hidden = YES;
		[_card addSubview:_switchView];
	}
	return self;
}

- (void)switchToggled:(UISwitch *)sender
{
	if (_switchChanged) {
		_switchChanged(sender.isOn);
	}
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
	[super setHighlighted:highlighted animated:animated];
	_card.backgroundColor = highlighted ? [MLTheme surfaceContainerHigh] : [MLTheme surfaceContainer];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_card.frame = CGRectMake(14.0f, 3.0f, b.size.width - 28.0f, b.size.height - 6.0f);
	CGFloat cw = _card.bounds.size.width;
	CGFloat ch = _card.bounds.size.height;

	_iconCircle.frame = CGRectMake(12.0f, (ch - 40.0f) / 2.0f, 40.0f, 40.0f);
	_chevronView.frame = CGRectMake(cw - 30.0f, (ch - 20.0f) / 2.0f, 20.0f, 20.0f);
	_switchView.frame = CGRectMake(cw - 64.0f, (ch - 30.0f) / 2.0f, 51.0f, 31.0f);

	CGFloat textX = 64.0f;
	CGFloat rightLimit = _switchView.hidden ? _chevronView.frame.origin.x : _switchView.frame.origin.x;
	CGFloat textW = MAX(40.0f, rightLimit - textX - 8.0f);
	if (_subtitleLabel.text.length > 0) {
		_titleLabel.frame = CGRectMake(textX, (ch / 2.0f) - 17.0f, textW, 18.0f);
		_subtitleLabel.frame = CGRectMake(textX, (ch / 2.0f) + 2.0f, textW, 15.0f);
		_subtitleLabel.hidden = NO;
	} else {
		_titleLabel.frame = CGRectMake(textX, (ch - 20.0f) / 2.0f, textW, 20.0f);
		_subtitleLabel.hidden = YES;
	}
}

- (void)fillWithSpec:(NSDictionary *)spec
{
	_titleLabel.text = spec[@"title"];
	_subtitleLabel.text = spec[@"subtitle"];
	UIColor *accent = spec[@"color"] ?: [MLTheme primary];
	_iconCircle.backgroundColor = [accent colorWithAlphaComponent:0.18f];
	NSString *icon = spec[@"icon"];
	_iconView.image = icon ? [MLIcon icon:icon size:20.0f color:accent] : nil;

	BOOL isSwitch = [spec[@"isSwitch"] boolValue];
	_switchView.hidden = !isSwitch;
	_chevronView.hidden = isSwitch;
	if (isSwitch) {
		_switchView.on = [spec[@"switchValue"] boolValue];
		if ([_switchView respondsToSelector:@selector(setOnTintColor:)]) {
			_switchView.onTintColor = [MLTheme primary];
		}
	}
	[self setNeedsLayout];
}

@end

#pragma mark - MLAccountSettingsViewController

@implementation MLAccountSettingsViewController
{
	UIView *_topBar;
	UILabel *_headerTitle;
	UIButton *_closeButton;
	UITableView *_table;
	NSArray *_rows;
	BOOL _fetchingAccount;
}

+ (UIBarButtonItem *)barButtonItemForViewController:(UIViewController *)targetVC
{
	MLAccountBarButton *btn = [[MLAccountBarButton alloc] initWithTargetViewController:targetVC];
	return [[UIBarButtonItem alloc] initWithCustomView:btn];
}

+ (void)presentFromViewController:(UIViewController *)presenter
{
	if (!presenter)
		return;
	MLAccountSettingsViewController *vc = [[MLAccountSettingsViewController alloc] init];
	[presenter presentViewController:vc animated:YES completion:nil];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.backgroundColor = [MLTheme background];
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	CGRect b = self.view.bounds;
	CGFloat topInset = ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0f) ? 20.0f : 0.0f;
	CGFloat barH = 54.0f + topInset;

	_topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, barH)];
	_topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_topBar.backgroundColor = [MLTheme surfaceContainer];
	[self.view addSubview:_topBar];

	UIImageView *logoView = [[UIImageView alloc] initWithFrame:CGRectMake(16.0f, topInset + 15.0f, 24.0f, 24.0f)];
	logoView.image = [MLIcon icon:@"music_note" size:22.0f color:[MLTheme primary]];
	[_topBar addSubview:logoView];

	_headerTitle = [[UILabel alloc] initWithFrame:CGRectMake(46.0f, topInset + 13.0f, b.size.width - 104.0f, 28.0f)];
	_headerTitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_headerTitle.font = [MLTheme fontTitleLarge];
	_headerTitle.textColor = [MLTheme onSurface];
	_headerTitle.backgroundColor = [UIColor clearColor];
	_headerTitle.text = @"MetroLegacy";
	[_topBar addSubview:_headerTitle];

	_closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_closeButton.frame = CGRectMake(b.size.width - 48.0f, topInset + 9.0f, 36.0f, 36.0f);
	_closeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	_closeButton.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.10f];
	_closeButton.layer.cornerRadius = 18.0f;
	[_closeButton setImage:[MLIcon icon:@"close" size:20.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_closeButton addTarget:self action:@selector(closeTap) forControlEvents:UIControlEventTouchUpInside];
	[_topBar addSubview:_closeButton];

	_table = [[UITableView alloc] initWithFrame:CGRectMake(0, barH, b.size.width, b.size.height - barH) style:UITableViewStylePlain];
	_table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_table.backgroundColor = [UIColor clearColor];
	_table.separatorStyle = UITableViewCellSeparatorStyleNone;
	_table.dataSource = self;
	_table.delegate = self;
	_table.contentInset = UIEdgeInsetsMake(10.0f, 0, 24.0f, 0);
	[self.view addSubview:_table];

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(rebuildRows) name:MLSessionChangedNotification object:nil];
	[nc addObserver:self selector:@selector(rebuildRows) name:MLLibraryDidUpdateNotification object:nil];
	[nc addObserver:self selector:@selector(rebuildRows) name:MLLanguageChangedNotification object:nil];
	[nc addObserver:self selector:@selector(themeChanged:) name:MLThemeDidChangeNotification object:nil];

	[self rebuildRows];
	[self refreshAccountIfNeeded];
}

- (void)themeChanged:(NSNotification *)note
{
	self.view.backgroundColor = [MLTheme background];
	_topBar.backgroundColor = [MLTheme surfaceContainer];
	_table.backgroundColor = [MLTheme background];
	[self rebuildRows];
}

- (void)closeTap
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)refreshAccountIfNeeded
{
	MLInnerTube *yt = [MLInnerTube sharedClient];
	if (!yt.loggedIn || _fetchingAccount)
		return;
	if (!yt.accountName.length || !yt.accountPhotoUrl.length) {
		_fetchingAccount = YES;
		[yt accountMenu:^(NSDictionary *info, NSString *err) {
			_fetchingAccount = NO;
			[self rebuildRows];
		}];
	}
}

- (void)rebuildRows
{
	BOOL loggedIn = [MLInnerTube sharedClient].loggedIn;
	MLLibraryManager *lib = [MLLibraryManager sharedManager];
	NSString *langPref = [MLLocalization sharedManager].languagePreference;
	NSString *langDisplay = [[MLLocalization sharedManager] displayNameForLanguageCode:langPref];
	NSString *cacheSize = [lib formattedSizeForBytes:[lib audioCacheTotalBytes]];

	NSMutableArray *list = [NSMutableArray array];

	[list addObject:@{ @"type" : @"section_header", @"title" : MLLocalizedString(@"account", nil) }];

	if (loggedIn) {
		NSString *name = [MLInnerTube sharedClient].accountName ?: MLLocalizedString(@"account", nil);
		NSString *sub = [MLInnerTube sharedClient].accountChannelHandle ?: ([MLInnerTube sharedClient].accountEmail ?: @"");
		NSString *photo = [MLInnerTube sharedClient].accountPhotoUrl ?: @"";
		[list addObject:@{
			@"type" : @"profile_card",
			@"name" : name,
			@"subtitle" : sub,
			@"photo" : photo,
		}];
		[list addObject:@{
			@"type" : @"sync",
			@"title" : MLLocalizedString(@"sync_ytm", nil),
			@"subtitle" : lib.isSyncing ? MLLocalizedString(@"syncing_ytm", nil) : (lib.lastSyncDate ? MLLocalizedString(@"sync_done", nil) : MLLocalizedString(@"sync_ytm_sub", nil)),
			@"icon" : @"sync",
			@"color" : [MLTheme primary],
		}];
		[list addObject:@{
			@"type" : @"token",
			@"title" : MLLocalizedString(@"session_token", nil),
			@"subtitle" : MLLocalizedString(@"session_token_sub", nil),
			@"icon" : @"vpn_key",
			@"color" : [MLTheme primary],
		}];
	} else {
		[list addObject:@{
			@"type" : @"login",
			@"title" : MLLocalizedString(@"sign_in_device", nil),
			@"subtitle" : MLLocalizedString(@"sign_in_device_sub", nil),
			@"icon" : @"devices",
			@"color" : [MLTheme primary],
		}];
		[list addObject:@{
			@"type" : @"token",
			@"title" : MLLocalizedString(@"sign_in_token", nil),
			@"subtitle" : MLLocalizedString(@"sign_in_token_sub", nil),
			@"icon" : @"vpn_key",
			@"color" : [MLTheme primary],
		}];
	}

	[list addObject:@{ @"type" : @"section_header", @"title" : MLLocalizedString(@"account_section", nil) }];

	[list addObject:@{
		@"type" : @"clear_cache",
		@"title" : MLLocalizedString(@"clear_cache", nil),
		@"subtitle" : [NSString stringWithFormat:MLLocalizedString(@"clear_cache_sub", nil), cacheSize],
		@"icon" : @"cached",
		@"color" : [UIColor colorWithRed:0.22f green:0.52f blue:0.85f alpha:1.0f],
	}];
	[list addObject:@{
		@"type" : @"language",
		@"title" : MLLocalizedString(@"language", nil),
		@"subtitle" : langDisplay ?: @"",
		@"icon" : @"language",
		@"color" : [UIColor colorWithRed:0.58f green:0.38f blue:0.82f alpha:1.0f],
	}];
	BOOL sbEnabled = [MLSponsorBlockManager sharedManager].enabled;
	[list addObject:@{
		@"type" : @"sponsorblock",
		@"title" : MLLocalizedString(@"sponsorblock_title", nil),
		@"subtitle" : sbEnabled ? MLLocalizedString(@"sponsorblock_skipped", nil) : @"Desactivado",
		@"icon" : @"block",
		@"color" : [UIColor colorWithRed:0.95f green:0.35f blue:0.35f alpha:1.0f],
	}];

	[list addObject:@{ @"type" : @"section_header", @"title" : MLLocalizedString(@"theme_section", nil) }];

	BOOL dynamicOn = [MLTheme dynamicThemeEnabled];
	[list addObject:@{
		@"type" : @"theme_dynamic",
		@"title" : MLLocalizedString(@"theme_dynamic", nil),
		@"subtitle" : dynamicOn ? MLLocalizedString(@"theme_dynamic_sub", nil) : MLLocalizedString(@"disabled", nil),
		@"icon" : @"palette",
		@"color" : [MLTheme primary],
		@"isSwitch" : @YES,
		@"switchValue" : @(dynamicOn),
	}];

	BOOL pureBlackOn = [MLTheme pureBlackEnabled];
	[list addObject:@{
		@"type" : @"theme_pure_black",
		@"title" : MLLocalizedString(@"theme_pure_black", nil),
		@"subtitle" : pureBlackOn ? MLLocalizedString(@"theme_pure_black_sub", nil) : MLLocalizedString(@"disabled", nil),
		@"icon" : @"dark_mode",
		@"color" : [MLTheme primary],
		@"isSwitch" : @YES,
		@"switchValue" : @(pureBlackOn),
	}];

	NSUInteger palIdx = [MLTheme selectedPaletteIndex];
	NSArray *palNames = [MLTheme availablePaletteNames];
	NSString *palName = (palIdx < palNames.count) ? palNames[palIdx] : @"Rojo YouTube Music (M3)";
	[list addObject:@{
		@"type" : @"theme_accent",
		@"title" : MLLocalizedString(@"theme_accent_color", nil),
		@"subtitle" : palName,
		@"icon" : @"palette",
		@"color" : [MLTheme defaultAccentColor],
	}];

	_rows = list;
	[_table reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _rows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSDictionary *r = _rows[indexPath.row];
	NSString *type = r[@"type"];
	if ([type isEqualToString:@"section_header"])
		return 34.0f;
	if ([type isEqualToString:@"profile_card"])
		return 82.0f;
	return 64.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSDictionary *r = _rows[indexPath.row];
	NSString *type = r[@"type"];

	if ([type isEqualToString:@"section_header"]) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sec_hdr"];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sec_hdr"];
			cell.backgroundColor = [UIColor clearColor];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(18.0f, 10.0f, 280.0f, 18.0f)];
			lbl.tag = 901;
			lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
			lbl.font = [MLTheme fontLabelMedium];
			lbl.textColor = [MLTheme primary];
			lbl.backgroundColor = [UIColor clearColor];
			[cell.contentView addSubview:lbl];
		}
		UILabel *lbl = (UILabel *)[cell.contentView viewWithTag:901];
		lbl.text = [r[@"title"] uppercaseString];
		return cell;
	}

	if ([type isEqualToString:@"profile_card"]) {
		MLAccountProfileCell *cell = [tableView dequeueReusableCellWithIdentifier:@"profile"];
		if (!cell) {
			cell = [[MLAccountProfileCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"profile"];
		}
		[cell fillWithName:r[@"name"] subtitle:r[@"subtitle"] photoUrl:r[@"photo"]];
		__weak MLAccountSettingsViewController *wself = self;
		cell.logoutTapped = ^{
			[[MLInnerTube sharedClient] clearSession];
			[wself rebuildRows];
		};
		return cell;
	}

	MLSettingsRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell) {
		cell = [[MLSettingsRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
	}
	[cell fillWithSpec:r];
	__weak MLAccountSettingsViewController *wself = self;
	cell.switchChanged = ^(BOOL on) {
		NSString *cellType = r[@"type"];
		if ([cellType isEqualToString:@"theme_dynamic"]) {
			[MLTheme setDynamicThemeEnabled:on];
			[wself rebuildRows];
		} else if ([cellType isEqualToString:@"theme_pure_black"]) {
			[MLTheme setPureBlackEnabled:on];
			[wself rebuildRows];
		}
	};
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *r = _rows[indexPath.row];
	NSString *type = r[@"type"];

	if ([type isEqualToString:@"profile_card"]) {
		[[MLInnerTube sharedClient] accountMenu:^(NSDictionary *info, NSString *err) {
			[self rebuildRows];
		}];
		return;
	}
	if ([type isEqualToString:@"login"]) {
		MLLoginViewController *login = [[MLLoginViewController alloc] init];
		[self presentViewController:login animated:YES completion:nil];
		return;
	}
	if ([type isEqualToString:@"token"]) {
		MLTokenEditorViewController *editor = [[MLTokenEditorViewController alloc] init];
		UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
		nav.navigationBar.barStyle = UIBarStyleBlack;
		nav.navigationBar.translucent = NO;
		if ([nav.navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
			nav.navigationBar.barTintColor = [MLTheme background];
			nav.navigationBar.tintColor = [MLTheme onSurface];
		} else {
			nav.navigationBar.tintColor = [MLTheme background];
		}
		[self presentViewController:nav animated:YES completion:nil];
		return;
	}
	if ([type isEqualToString:@"sync"]) {
		[[MLLibraryManager sharedManager] syncWithYouTubeMusicCompletion:^(BOOL ok, NSString *err) {
			[self rebuildRows];
		}];
		[self rebuildRows];
		return;
	}
	if ([type isEqualToString:@"clear_cache"]) {
		[[MLLibraryManager sharedManager] clearAudioCache];
		[self rebuildRows];
		return;
	}
	if ([type isEqualToString:@"language"]) {
		[self showLanguagePicker];
		return;
	}
	if ([type isEqualToString:@"sponsorblock"]) {
		[MLSponsorBlockManager sharedManager].enabled = ![MLSponsorBlockManager sharedManager].enabled;
		[self rebuildRows];
		return;
	}
	if ([type isEqualToString:@"theme_dynamic"]) {
		BOOL next = ![MLTheme dynamicThemeEnabled];
		[MLTheme setDynamicThemeEnabled:next];
		[self rebuildRows];
		return;
	}
	if ([type isEqualToString:@"theme_pure_black"]) {
		BOOL next = ![MLTheme pureBlackEnabled];
		[MLTheme setPureBlackEnabled:next];
		[self rebuildRows];
		return;
	}
	if ([type isEqualToString:@"theme_accent"]) {
		[self showPalettePicker];
		return;
	}
}

- (void)showLanguagePicker
{
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:MLLocalizedString(@"language_select_title", nil)
	                                                   delegate:self
	                                          cancelButtonTitle:MLLocalizedString(@"cancel", nil)
	                                     destructiveButtonTitle:nil
	                                          otherButtonTitles:
	                                              MLLocalizedString(@"lang_system", nil),
	                                              MLLocalizedString(@"lang_es", nil),
	                                              MLLocalizedString(@"lang_en", nil),
	                                              MLLocalizedString(@"lang_ru", nil),
	                                              nil];
	sheet.tag = 200;
	[sheet showInView:self.view];
}

- (void)showPalettePicker
{
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:MLLocalizedString(@"theme_accent_color", nil)
	                                                   delegate:self
	                                          cancelButtonTitle:nil
	                                     destructiveButtonTitle:nil
	                                          otherButtonTitles:nil];
	NSArray *names = [MLTheme availablePaletteNames];
	for (NSString *name in names) {
		[sheet addButtonWithTitle:name];
	}
	[sheet addButtonWithTitle:MLLocalizedString(@"cancel", nil)];
	sheet.cancelButtonIndex = names.count;
	sheet.tag = 300;
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (buttonIndex == actionSheet.cancelButtonIndex)
		return;

	if (actionSheet.tag == 200) {
		NSArray *codes = @[@"system", @"es", @"en", @"ru"];
		if (buttonIndex >= 0 && (NSUInteger)buttonIndex < codes.count) {
			[[MLLocalization sharedManager] setLanguagePreference:codes[buttonIndex]];
		}
		return;
	}

	if (actionSheet.tag == 300) {
		NSArray *names = [MLTheme availablePaletteNames];
		if (buttonIndex >= 0 && (NSUInteger)buttonIndex < names.count) {
			[MLTheme setSelectedPaletteIndex:(NSUInteger)buttonIndex];
			[self rebuildRows];
		}
		return;
	}
}

@end
