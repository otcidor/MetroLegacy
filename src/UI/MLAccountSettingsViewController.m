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
#import "MLBottomSheet.h"
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
@property (nonatomic, copy) void (^actionTapped)(void);
@property (nonatomic, assign) NSInteger groupPosition;
- (void)fillWithName:(NSString *)name subtitle:(NSString *)subtitle photoUrl:(NSString *)photoUrl isLoggedIn:(BOOL)isLoggedIn;
@end

@implementation MLAccountProfileCell
{
	UIView *_card;
	UIImageView *_avatar;
	UILabel *_nameLabel;
	UILabel *_subLabel;
	UIButton *_actionBtn;
	BOOL _isLoggedIn;
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
		_card.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.25f].CGColor;
		[self.contentView addSubview:_card];

		_avatar = [[UIImageView alloc] initWithFrame:CGRectMake(14.0f, 14.0f, 48.0f, 48.0f)];
		_avatar.backgroundColor = [[MLTheme primary] colorWithAlphaComponent:0.18f];
		_avatar.layer.cornerRadius = 24.0f;
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

		_actionBtn = [UIButton buttonWithType:UIButtonTypeCustom];
		_actionBtn.layer.cornerRadius = 16.0f;
		_actionBtn.titleLabel.font = [MLTheme fontLabelMedium];
		[_actionBtn addTarget:self action:@selector(onActionTap) forControlEvents:UIControlEventTouchUpInside];
		[_card addSubview:_actionBtn];
	}
	return self;
}

- (void)onActionTap
{
	if (_actionTapped)
		_actionTapped();
}

- (void)applyCornerMaskWithTopRadius:(CGFloat)topR bottomRadius:(CGFloat)botR bounds:(CGRect)rect
{
	if (rect.size.width <= 0 || rect.size.height <= 0) return;
	UIBezierPath *path = [UIBezierPath bezierPath];
	CGFloat minX = 0, minY = 0, maxX = rect.size.width, maxY = rect.size.height;

	[path moveToPoint:CGPointMake(minX + topR, minY)];
	[path addLineToPoint:CGPointMake(maxX - topR, minY)];
	[path addArcWithCenter:CGPointMake(maxX - topR, minY + topR) radius:topR startAngle:-M_PI_2 endAngle:0 clockwise:YES];
	[path addLineToPoint:CGPointMake(maxX, maxY - botR)];
	[path addArcWithCenter:CGPointMake(maxX - botR, maxY - botR) radius:botR startAngle:0 endAngle:M_PI_2 clockwise:YES];
	[path addLineToPoint:CGPointMake(minX + botR, maxY)];
	[path addArcWithCenter:CGPointMake(minX + botR, maxY - botR) radius:botR startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
	[path addLineToPoint:CGPointMake(minX, minY + topR)];
	[path addArcWithCenter:CGPointMake(minX + topR, minY + topR) radius:topR startAngle:M_PI endAngle:-M_PI_2 clockwise:YES];
	[path closePath];

	CAShapeLayer *mask = [CAShapeLayer layer];
	mask.path = path.CGPath;
	_card.layer.mask = mask;
	_card.layer.cornerRadius = 0.0f;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_card.frame = CGRectMake(14.0f, 2.0f, b.size.width - 28.0f, b.size.height - 4.0f);
	CGFloat cw = _card.bounds.size.width;
	CGFloat ch = _card.bounds.size.height;

	if (_groupPosition == 0) {
		_card.layer.cornerRadius = 18.0f;
		_card.layer.mask = nil;
	} else if (_groupPosition == 1) {
		[self applyCornerMaskWithTopRadius:18.0f bottomRadius:4.0f bounds:_card.bounds];
	} else if (_groupPosition == 3) {
		[self applyCornerMaskWithTopRadius:4.0f bottomRadius:18.0f bounds:_card.bounds];
	} else {
		_card.layer.cornerRadius = 4.0f;
		_card.layer.mask = nil;
	}

	_avatar.frame = CGRectMake(14.0f, (ch - 48.0f) / 2.0f, 48.0f, 48.0f);

	NSString *title = [_actionBtn titleForState:UIControlStateNormal] ?: @"";
	CGSize ts = [title sizeWithFont:_actionBtn.titleLabel.font];
	CGFloat btnW = MAX(76.0f, ts.width + 24.0f);
	_actionBtn.frame = CGRectMake(cw - btnW - 14.0f, (ch - 32.0f) / 2.0f, btnW, 32.0f);

	CGFloat textX = 74.0f;
	CGFloat textW = MAX(40.0f, _actionBtn.frame.origin.x - textX - 8.0f);
	if (_subLabel.text.length > 0) {
		_nameLabel.frame = CGRectMake(textX, (ch / 2.0f) - 18.0f, textW, 20.0f);
		_subLabel.frame = CGRectMake(textX, (ch / 2.0f) + 2.0f, textW, 16.0f);
		_subLabel.hidden = NO;
	} else {
		_nameLabel.frame = CGRectMake(textX, (ch - 20.0f) / 2.0f, textW, 20.0f);
		_subLabel.hidden = YES;
	}
}

- (void)fillWithName:(NSString *)name subtitle:(NSString *)subtitle photoUrl:(NSString *)photoUrl isLoggedIn:(BOOL)isLoggedIn
{
	_isLoggedIn = isLoggedIn;
	_card.backgroundColor = [MLTheme surfaceContainerHigh];
	_card.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.25f].CGColor;
	_nameLabel.text = name;
	_nameLabel.textColor = [MLTheme onSurface];
	_subLabel.text = subtitle;
	_subLabel.textColor = [MLTheme onSurfaceVariant];

	if (isLoggedIn) {
		_avatar.layer.borderWidth = 1.5f;
		_avatar.layer.borderColor = [[MLTheme primary] colorWithAlphaComponent:0.65f].CGColor;
		_avatar.backgroundColor = [[MLTheme primary] colorWithAlphaComponent:0.18f];
		UIImage *fallback = [MLIcon icon:@"person" size:24.0f color:[MLTheme primary]];
		if (photoUrl.length > 0) {
			_avatar.contentMode = UIViewContentModeScaleAspectFill;
			[MLImageCache loadImageAtURLString:photoUrl
			                          intoView:_avatar
			                           fitSize:CGSizeMake(48.0f, 48.0f)
			                      cornerRadius:24.0f
			                       placeholder:fallback];
		} else {
			_avatar.contentMode = UIViewContentModeCenter;
			_avatar.image = fallback;
		}

		NSString *btnTitle = MLLocalizedString(@"sign_out", nil);
		[_actionBtn setTitle:btnTitle forState:UIControlStateNormal];
		[_actionBtn setTitleColor:[MLTheme onSurface] forState:UIControlStateNormal];
		_actionBtn.backgroundColor = [MLTheme surfaceContainer];
		_actionBtn.layer.borderWidth = 1.0f;
		_actionBtn.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.35f].CGColor;
	} else {
		_avatar.layer.borderWidth = 0.0f;
		_avatar.backgroundColor = [[MLTheme surfaceContainer] colorWithAlphaComponent:0.8f];
		_avatar.contentMode = UIViewContentModeCenter;
		_avatar.image = [MLIcon icon:@"person" size:24.0f color:[MLTheme primary]];

		NSString *btnTitle = MLLocalizedString(@"action_login", nil);
		[_actionBtn setTitle:btnTitle forState:UIControlStateNormal];
		[_actionBtn setTitleColor:[MLTheme onPrimary] forState:UIControlStateNormal];
		_actionBtn.backgroundColor = [MLTheme primary];
		_actionBtn.layer.borderWidth = 0.0f;
	}

	[self setNeedsLayout];
}

@end

#pragma mark - Settings Row Card Cell (Material 3 Expressive Grouping)

@interface MLSettingsRowCell : UITableViewCell
@property (nonatomic, copy) void (^switchChanged)(BOOL on);
- (void)fillWithSpec:(NSDictionary *)spec groupPosition:(NSInteger)pos;
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
	UIView *_swatchView;
	NSInteger _groupPosition;
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
		_card.clipsToBounds = YES;
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

		_swatchView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20.0f, 20.0f)];
		_swatchView.layer.cornerRadius = 10.0f;
		_swatchView.layer.borderWidth = 1.5f;
		_swatchView.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.35f].CGColor;
		_swatchView.hidden = YES;
		[_card addSubview:_swatchView];

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

- (void)applyCornerMaskWithTopRadius:(CGFloat)topR bottomRadius:(CGFloat)botR bounds:(CGRect)rect
{
	if (rect.size.width <= 0 || rect.size.height <= 0) return;
	UIBezierPath *path = [UIBezierPath bezierPath];
	CGFloat minX = 0, minY = 0, maxX = rect.size.width, maxY = rect.size.height;

	[path moveToPoint:CGPointMake(minX + topR, minY)];
	[path addLineToPoint:CGPointMake(maxX - topR, minY)];
	[path addArcWithCenter:CGPointMake(maxX - topR, minY + topR) radius:topR startAngle:-M_PI_2 endAngle:0 clockwise:YES];
	[path addLineToPoint:CGPointMake(maxX, maxY - botR)];
	[path addArcWithCenter:CGPointMake(maxX - botR, maxY - botR) radius:botR startAngle:0 endAngle:M_PI_2 clockwise:YES];
	[path addLineToPoint:CGPointMake(minX + botR, maxY)];
	[path addArcWithCenter:CGPointMake(minX + botR, maxY - botR) radius:botR startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
	[path addLineToPoint:CGPointMake(minX, minY + topR)];
	[path addArcWithCenter:CGPointMake(minX + topR, minY + topR) radius:topR startAngle:M_PI endAngle:-M_PI_2 clockwise:YES];
	[path closePath];

	CAShapeLayer *mask = [CAShapeLayer layer];
	mask.path = path.CGPath;
	_card.layer.mask = mask;
	_card.layer.cornerRadius = 0.0f;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_card.frame = CGRectMake(14.0f, 2.0f, b.size.width - 28.0f, b.size.height - 4.0f);
	CGFloat cw = _card.bounds.size.width;
	CGFloat ch = _card.bounds.size.height;

	if (_groupPosition == 0) {
		_card.layer.cornerRadius = 18.0f;
		_card.layer.mask = nil;
	} else if (_groupPosition == 1) {
		[self applyCornerMaskWithTopRadius:18.0f bottomRadius:4.0f bounds:_card.bounds];
	} else if (_groupPosition == 3) {
		[self applyCornerMaskWithTopRadius:4.0f bottomRadius:18.0f bounds:_card.bounds];
	} else {
		_card.layer.cornerRadius = 4.0f;
		_card.layer.mask = nil;
	}

	_iconCircle.frame = CGRectMake(12.0f, (ch - 40.0f) / 2.0f, 40.0f, 40.0f);
	_chevronView.frame = CGRectMake(cw - 30.0f, (ch - 20.0f) / 2.0f, 20.0f, 20.0f);
	_swatchView.frame = CGRectMake(cw - 56.0f, (ch - 20.0f) / 2.0f, 20.0f, 20.0f);
	_switchView.frame = CGRectMake(cw - 64.0f, (ch - 30.0f) / 2.0f, 51.0f, 31.0f);

	CGFloat textX = 64.0f;
	CGFloat rightLimit = cw - 12.0f;
	if (!_switchView.hidden) {
		rightLimit = _switchView.frame.origin.x;
	} else if (!_swatchView.hidden) {
		rightLimit = _swatchView.frame.origin.x;
	} else if (!_chevronView.hidden) {
		rightLimit = _chevronView.frame.origin.x;
	}

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

- (void)fillWithSpec:(NSDictionary *)spec groupPosition:(NSInteger)pos
{
	_groupPosition = pos;
	_card.backgroundColor = [MLTheme surfaceContainer];
	_card.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.18f].CGColor;
	_titleLabel.text = spec[@"title"];
	_titleLabel.textColor = [MLTheme onSurface];
	_subtitleLabel.text = spec[@"subtitle"];
	_subtitleLabel.textColor = [MLTheme onSurfaceVariant];

	UIColor *accent = spec[@"color"] ?: [MLTheme primary];
	_iconCircle.backgroundColor = [accent colorWithAlphaComponent:0.18f];
	NSString *icon = spec[@"icon"];
	_iconView.image = icon ? [MLIcon icon:icon size:20.0f color:accent] : nil;

	BOOL isSwitch = [spec[@"isSwitch"] boolValue];
	_switchView.hidden = !isSwitch;
	if (isSwitch) {
		_switchView.on = [spec[@"switchValue"] boolValue];
		if ([_switchView respondsToSelector:@selector(setOnTintColor:)]) {
			_switchView.onTintColor = [MLTheme primary];
		}
	}

	BOOL hasSwatch = [spec[@"hasSwatch"] boolValue];
	_swatchView.hidden = !hasSwatch;
	if (hasSwatch) {
		UIColor *swatchColor = spec[@"swatchColor"] ?: [MLTheme defaultAccentColor];
		_swatchView.backgroundColor = swatchColor;
		_swatchView.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.35f].CGColor;
	}

	BOOL noChevron = [spec[@"noChevron"] boolValue];
	_chevronView.hidden = (isSwitch || noChevron);
	_chevronView.image = [MLIcon icon:@"chevron_right" size:20.0f color:[MLTheme onSurfaceVariant]];

	[self setNeedsLayout];
}

@end

#pragma mark - MLAccountSettingsViewController

@implementation MLAccountSettingsViewController
{
	UIView *_topBar;
	UIImageView *_logoView;
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
	_table.dataSource = nil;
	_table.delegate = nil;
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
	CGFloat topInset = [MLTheme safeAreaTopInsetForView:self.view];
	CGFloat barH = 54.0f + topInset;

	_topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, barH)];
	_topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_topBar.backgroundColor = [MLTheme surfaceContainer];
	[self.view addSubview:_topBar];

	_logoView = [[UIImageView alloc] initWithFrame:CGRectMake(16.0f, topInset + 15.0f, 24.0f, 24.0f)];
	_logoView.image = [MLIcon icon:@"music_note" size:22.0f color:[MLTheme primary]];
	[_topBar addSubview:_logoView];

	_headerTitle = [[UILabel alloc] initWithFrame:CGRectMake(48.0f, topInset + 13.0f, b.size.width - 104.0f, 28.0f)];
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

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	CGRect b = self.view.bounds;
	CGFloat topInset = [MLTheme safeAreaTopInsetForView:self.view];
	CGFloat barH = 54.0f + topInset;

	_topBar.frame = CGRectMake(0, 0, b.size.width, barH);
	_logoView.frame = CGRectMake(16.0f, topInset + 15.0f, 24.0f, 24.0f);
	_headerTitle.frame = CGRectMake(48.0f, topInset + 13.0f, b.size.width - 104.0f, 28.0f);
	_closeButton.frame = CGRectMake(b.size.width - 48.0f, topInset + 9.0f, 36.0f, 36.0f);
	_table.frame = CGRectMake(0, barH, b.size.width, b.size.height - barH);
}

- (void)themeChanged:(NSNotification *)note
{
	self.view.backgroundColor = [MLTheme background];
	_topBar.backgroundColor = [MLTheme surfaceContainer];
	_logoView.image = [MLIcon icon:@"music_note" size:22.0f color:[MLTheme primary]];
	_headerTitle.textColor = [MLTheme onSurface];
	[_closeButton setImage:[MLIcon icon:@"close" size:20.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	_table.backgroundColor = [MLTheme background];
	[self rebuildRows];
}

- (void)closeTap
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dismissModalChild
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

	// Group 1: Account
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
			@"isLoggedIn" : @YES,
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
			@"type" : @"profile_card",
			@"name" : MLLocalizedString(@"account_guest", nil),
			@"subtitle" : MLLocalizedString(@"account_guest_sub", nil),
			@"photo" : @"",
			@"isLoggedIn" : @NO,
		}];
		[list addObject:@{
			@"type" : @"login_browser",
			@"title" : MLLocalizedString(@"sign_in_browser", nil),
			@"subtitle" : MLLocalizedString(@"sign_in_browser_sub", nil),
			@"icon" : @"public",
			@"color" : [MLTheme primary],
		}];
		[list addObject:@{
			@"type" : @"login_device",
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

	// Group 2: Storage & Settings
	[list addObject:@{ @"type" : @"section_header", @"title" : MLLocalizedString(@"storage_section", nil) }];

	NSUInteger dlCount = lib.downloadedSongs.count;
	NSString *dlSize = [lib formattedSizeForBytes:[lib downloadedTotalBytes]];
	NSString *countStr = (dlCount == 1) ? [NSString stringWithFormat:MLLocalizedString(@"songs_count_single", nil), (unsigned long)1] : [NSString stringWithFormat:MLLocalizedString(@"songs_count_plural", nil), (unsigned long)dlCount];
	NSString *dlSub = [NSString stringWithFormat:@"%@ • %@", countStr, dlSize];

	[list addObject:@{
		@"type" : @"downloads",
		@"title" : MLLocalizedString(@"downloaded_songs", nil),
		@"subtitle" : dlSub,
		@"icon" : @"download",
		@"color" : [UIColor colorWithRed:0.29f green:0.69f blue:0.34f alpha:1.0f],
	}];
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
		@"subtitle" : sbEnabled ? MLLocalizedString(@"sponsorblock_skipped", nil) : MLLocalizedString(@"disabled", nil),
		@"icon" : @"block",
		@"color" : [UIColor colorWithRed:0.95f green:0.35f blue:0.35f alpha:1.0f],
		@"isSwitch" : @YES,
		@"switchValue" : @(sbEnabled),
	}];

	// Group 3: Theme & Appearance
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
		@"hasSwatch" : @YES,
		@"swatchColor" : [MLTheme defaultAccentColor],
	}];

	// Group 4: About
	[list addObject:@{ @"type" : @"section_header", @"title" : MLLocalizedString(@"about_section", nil) }];

	[list addObject:@{
		@"type" : @"about_app",
		@"title" : MLLocalizedString(@"about_title", nil),
		@"subtitle" : MLLocalizedString(@"about_details", nil),
		@"icon" : @"music_note",
		@"color" : [MLTheme primary],
		@"noChevron" : @YES,
	}];
	[list addObject:@{
		@"type" : @"about_metrolist",
		@"title" : @"MetroList",
		@"subtitle" : MLLocalizedString(@"about_sub", nil),
		@"icon" : @"favorite",
		@"color" : [UIColor colorWithRed:0.95f green:0.35f blue:0.45f alpha:1.0f],
		@"noChevron" : @YES,
	}];

	_rows = list;
	[_table reloadData];
}

- (NSInteger)groupPositionForRowIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)_rows.count) return 0;
	NSDictionary *curr = _rows[index];
	if ([curr[@"type"] isEqualToString:@"section_header"]) return 0;

	BOOL hasPrev = (index > 0 && ![_rows[index - 1][@"type"] isEqualToString:@"section_header"]);
	BOOL hasNext = (index + 1 < (NSInteger)_rows.count && ![_rows[index + 1][@"type"] isEqualToString:@"section_header"]);

	if (!hasPrev && !hasNext) return 0;
	if (!hasPrev && hasNext) return 1;
	if (hasPrev && hasNext) return 2;
	return 3;
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
		BOOL isLoggedIn = [r[@"isLoggedIn"] boolValue];
		cell.groupPosition = [self groupPositionForRowIndex:indexPath.row];
		[cell fillWithName:r[@"name"] subtitle:r[@"subtitle"] photoUrl:r[@"photo"] isLoggedIn:isLoggedIn];
		__weak MLAccountSettingsViewController *wself = self;
		cell.actionTapped = ^{
			if (isLoggedIn) {
				[wself confirmLogout];
			} else {
				[wself showLoginOptions];
			}
		};
		return cell;
	}

	MLSettingsRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell) {
		cell = [[MLSettingsRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
	}
	NSInteger pos = [self groupPositionForRowIndex:indexPath.row];
	[cell fillWithSpec:r groupPosition:pos];
	__weak MLAccountSettingsViewController *wself = self;
	cell.switchChanged = ^(BOOL on) {
		NSString *cellType = r[@"type"];
		if ([cellType isEqualToString:@"theme_dynamic"]) {
			[MLTheme setDynamicThemeEnabled:on];
			[wself rebuildRows];
		} else if ([cellType isEqualToString:@"theme_pure_black"]) {
			[MLTheme setPureBlackEnabled:on];
			[wself rebuildRows];
		} else if ([cellType isEqualToString:@"sponsorblock"]) {
			[MLSponsorBlockManager sharedManager].enabled = on;
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
		BOOL isLoggedIn = [r[@"isLoggedIn"] boolValue];
		if (isLoggedIn) {
			[[MLInnerTube sharedClient] accountMenu:^(NSDictionary *info, NSString *err) {
				[self rebuildRows];
			}];
		} else {
			[self showLoginOptions];
		}
		return;
	}
	if ([type isEqualToString:@"login_browser"]) {
		MLLoginViewController *login = [[MLLoginViewController alloc] init];
		login.startInWebViewMode = YES;
		[self presentViewController:login animated:YES completion:nil];
		return;
	}
	if ([type isEqualToString:@"login_device"]) {
		MLLoginViewController *login = [[MLLoginViewController alloc] init];
		login.startInWebViewMode = NO;
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
	if ([type isEqualToString:@"downloads"]) {
		MLListDetailViewController *dlVC = [[MLListDetailViewController alloc] initWithDownloadedSongs];
		UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:dlVC];
		UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
		closeBtn.frame = CGRectMake(0, 0, 32.0f, 32.0f);
		closeBtn.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
		closeBtn.layer.cornerRadius = 16.0f;
		[closeBtn setImage:[MLIcon icon:@"close" size:18.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
		[closeBtn addTarget:self action:@selector(dismissModalChild) forControlEvents:UIControlEventTouchUpInside];
		dlVC.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:closeBtn];
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
	if ([type isEqualToString:@"about_metrolist"]) {
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/vfsfitvnm/MetroList"]];
		return;
	}
}

- (void)confirmLogout
{
	__weak MLAccountSettingsViewController *wself = self;
	MLBottomSheetItem *itClear = [MLBottomSheetItem itemWithTitle:MLLocalizedString(@"logout_clear", nil)
	                                                     subtitle:nil
	                                                     iconName:@"delete"
	                                                isDestructive:YES
	                                                      handler:^{
		[[MLInnerTube sharedClient] clearSession];
		[[MLLibraryManager sharedManager] clearAudioCache];
		[wself rebuildRows];
	}];

	MLBottomSheetItem *itKeep = [MLBottomSheetItem itemWithTitle:MLLocalizedString(@"logout_keep", nil)
	                                                    subtitle:nil
	                                                    iconName:@"logout"
	                                               isDestructive:NO
	                                                     handler:^{
		[[MLInnerTube sharedClient] clearSession];
		[wself rebuildRows];
	}];

	MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:MLLocalizedString(@"logout_confirm_title", nil)
	                                                     items:@[itClear, itKeep]];
	[menu showInView:self.view];
}

- (void)showLoginOptions
{
	__weak MLAccountSettingsViewController *wself = self;
	MLBottomSheetItem *itBrowser = [MLBottomSheetItem itemWithTitle:MLLocalizedString(@"sign_in_browser", nil)
	                                                       subtitle:MLLocalizedString(@"sign_in_browser_sub", nil)
	                                                       iconName:@"public"
	                                                        handler:^{
		MLLoginViewController *login = [[MLLoginViewController alloc] init];
		login.startInWebViewMode = YES;
		[wself presentViewController:login animated:YES completion:nil];
	}];

	MLBottomSheetItem *itDevice = [MLBottomSheetItem itemWithTitle:MLLocalizedString(@"sign_in_device", nil)
	                                                      subtitle:MLLocalizedString(@"sign_in_device_sub", nil)
	                                                      iconName:@"devices"
	                                                       handler:^{
		MLLoginViewController *login = [[MLLoginViewController alloc] init];
		login.startInWebViewMode = NO;
		[wself presentViewController:login animated:YES completion:nil];
	}];

	MLBottomSheetItem *itToken = [MLBottomSheetItem itemWithTitle:MLLocalizedString(@"sign_in_token", nil)
	                                                     subtitle:MLLocalizedString(@"sign_in_token_sub", nil)
	                                                     iconName:@"vpn_key"
	                                                      handler:^{
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
		[wself presentViewController:nav animated:YES completion:nil];
	}];

	MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:MLLocalizedString(@"action_login", nil)
	                                                     items:@[itBrowser, itDevice, itToken]];
	[menu showInView:self.view];
}

- (void)showLanguagePicker
{
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
		NSString *name = names[i];
		BOOL isSel = [currentPref isEqualToString:code];
		MLBottomSheetItem *it = [MLBottomSheetItem radioItemWithTitle:name
		                                                     subtitle:nil
		                                                     selected:isSel
		                                                      handler:^{
			[[MLLocalization sharedManager] setLanguagePreference:code];
		}];
		it.iconName = @"language";
		[items addObject:it];
	}

	MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:MLLocalizedString(@"language_select_title", nil)
	                                                     items:items];
	[menu showInView:self.view];
}

- (void)showPalettePicker
{
	NSArray *names = [MLTheme availablePaletteNames];
	NSArray *colors = [MLTheme availablePaletteColors];
	NSUInteger currentIdx = [MLTheme selectedPaletteIndex];

	__weak MLAccountSettingsViewController *wself = self;
	NSMutableArray *items = [NSMutableArray array];
	for (NSUInteger i = 0; i < names.count; i++) {
		UIColor *col = (i < colors.count) ? colors[i] : [MLTheme defaultAccentColor];
		BOOL isSel = (i == currentIdx);
		MLBottomSheetItem *it = [MLBottomSheetItem itemWithTitle:names[i]
		                                             swatchColor:col
		                                                selected:isSel
		                                                 handler:^{
			[MLTheme setSelectedPaletteIndex:i];
			[wself rebuildRows];
		}];
		it.isRadio = YES;
		[items addObject:it];
	}

	MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:MLLocalizedString(@"theme_accent_color", nil)
	                                                     items:items];
	[menu showInView:self.view];
}

@end
