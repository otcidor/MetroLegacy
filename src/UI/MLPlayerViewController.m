#import "MLPlayerViewController.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLImageCache.h"
#import "MLPlaybackManager.h"
#import "MLQueueViewController.h"
#import "MLNavigator.h"
#import "MLRootViewController.h"
#import "MLArtistViewController.h"
#import "MLLibraryManager.h"
#import "MLLocalization.h"
#import "MLLyricsView.h"
#import "MLSponsorBlockManager.h"
#import "MLEqualizerViewController.h"
#import "MLEqualizerManager.h"
#import <QuartzCore/QuartzCore.h>

/*
 * Pure Quartz 2D rounded rectangle path with individual corner radii (iOS 6+ compatible).
 */
static CGPathRef MLCreateRoundedRectPath(CGRect rect, CGFloat tl, CGFloat tr, CGFloat bl, CGFloat br)
{
	CGFloat x = rect.origin.x;
	CGFloat y = rect.origin.y;
	CGFloat w = rect.size.width;
	CGFloat h = rect.size.height;

	CGFloat maxR = MIN(w / 2.0f, h / 2.0f);
	tl = MIN(tl, maxR);
	tr = MIN(tr, maxR);
	bl = MIN(bl, maxR);
	br = MIN(br, maxR);

	CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint(path, NULL, x + tl, y);
	CGPathAddLineToPoint(path, NULL, x + w - tr, y);
	if (tr > 0) {
		CGPathAddArcToPoint(path, NULL, x + w, y, x + w, y + tr, tr);
	}
	CGPathAddLineToPoint(path, NULL, x + w, y + h - br);
	if (br > 0) {
		CGPathAddArcToPoint(path, NULL, x + w, y + h, x + w - br, y + h, br);
	}
	CGPathAddLineToPoint(path, NULL, x + bl, y + h);
	if (bl > 0) {
		CGPathAddArcToPoint(path, NULL, x, y + h, x, y + h - bl, bl);
	}
	CGPathAddLineToPoint(path, NULL, x, y + tl);
	if (tl > 0) {
		CGPathAddArcToPoint(path, NULL, x, y, x + tl, y, tl);
	}
	CGPathCloseSubpath(path);
	return path;
}

/*
 * Custom M3 button with configurable corner radii via CAShapeLayer mask.
 * Uses native view backgroundColor and border stroke layer so icon is never obstructed.
 */
@interface MLShapeButton : UIButton
{
	CAShapeLayer *_maskLayer;
	CAShapeLayer *_borderLayer;
}
@property (nonatomic, assign) CGFloat topLeftRadius;
@property (nonatomic, assign) CGFloat topRightRadius;
@property (nonatomic, assign) CGFloat bottomLeftRadius;
@property (nonatomic, assign) CGFloat bottomRightRadius;
@property (nonatomic, strong) UIColor *customFillColor;
@property (nonatomic, strong) UIColor *customBorderColor;
@property (nonatomic, assign) CGFloat customBorderWidth;

- (void)updateShape;
@end

@implementation MLShapeButton

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_maskLayer = [CAShapeLayer layer];
		self.layer.mask = _maskLayer;

		_borderLayer = [CAShapeLayer layer];
		_borderLayer.fillColor = [UIColor clearColor].CGColor;
		[self.layer addSublayer:_borderLayer];

		self.adjustsImageWhenHighlighted = NO;
		self.imageView.contentMode = UIViewContentModeCenter;
	}
	return self;
}

- (void)setTopLeftRadius:(CGFloat)r { _topLeftRadius = r; [self updateShape]; }
- (void)setTopRightRadius:(CGFloat)r { _topRightRadius = r; [self updateShape]; }
- (void)setBottomLeftRadius:(CGFloat)r { _bottomLeftRadius = r; [self updateShape]; }
- (void)setBottomRightRadius:(CGFloat)r { _bottomRightRadius = r; [self updateShape]; }

- (void)setCustomFillColor:(UIColor *)c
{
	_customFillColor = c;
	self.backgroundColor = c ?: [UIColor clearColor];
}

- (void)setCustomBorderColor:(UIColor *)c
{
	_customBorderColor = c;
	[self updateShape];
}

- (void)setCustomBorderWidth:(CGFloat)w
{
	_customBorderWidth = w;
	[self updateShape];
}

- (void)setHighlighted:(BOOL)highlighted
{
	[super setHighlighted:highlighted];
	self.alpha = highlighted ? 0.65f : 1.0f;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	[self updateShape];
	if (self.imageView) {
		[self bringSubviewToFront:self.imageView];
	}
}

- (void)updateShape
{
	if (CGRectIsEmpty(self.bounds)) return;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	self.backgroundColor = _customFillColor ?: [UIColor clearColor];

	CGPathRef p = MLCreateRoundedRectPath(self.bounds, _topLeftRadius, _topRightRadius, _bottomLeftRadius, _bottomRightRadius);
	_maskLayer.frame = self.bounds;
	_maskLayer.path = p;

	_borderLayer.frame = self.bounds;
	_borderLayer.path = p;
	_borderLayer.fillColor = [UIColor clearColor].CGColor;
	_borderLayer.strokeColor = _customBorderColor ? _customBorderColor.CGColor : NULL;
	_borderLayer.lineWidth = _customBorderWidth;

	CGPathRelease(p);
	[CATransaction commit];
}

@end

@interface MLPlayerViewController ()
{
	CAGradientLayer *_bgGradient;
	UIView *_dragHandle;
	UIButton *_closeButton;
	UIButton *_eqButton;
	UILabel *_headerSubtitleLabel;
	UILabel *_headerTitleLabel;

	UIView *_artContainer;
	UIImageView *_artView;
	MLLyricsView *_lyricsView;
	BOOL _showingLyrics;

	UILabel *_titleLabel;
	UILabel *_explicitBadge;
	UIButton *_artistButton;
	MLShapeButton *_shareButton;
	MLShapeButton *_likeButton;

	UISlider *_seekBar;
	UILabel *_elapsedLabel;
	UILabel *_durationLabel;
	UILabel *_statusLabel;

	UIButton *_prevButton;
	UIButton *_playButton;
	UIButton *_nextButton;

	MLShapeButton *_queueButton;
	MLShapeButton *_sleepButton;
	MLShapeButton *_shuffleButton;
	MLShapeButton *_lyricsButton;
	MLShapeButton *_repeatButton;
	UIButton *_moreButton;

	NSString *_lastThumbUrl;
	NSString *_lastLyricsVideoId;
	BOOL _viewIsVisible;
	BOOL _seeking;
	BOOL _liked;
}
@end

@implementation MLPlayerViewController

- (UIStatusBarStyle)preferredStatusBarStyle
{
	return UIStatusBarStyleLightContent;
}

- (void)dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.view.backgroundColor = [MLTheme background];

	_bgGradient = [CAGradientLayer layer];
	_bgGradient.startPoint = CGPointMake(0.5f, 0.0f);
	_bgGradient.endPoint = CGPointMake(0.5f, 1.0f);
	_bgGradient.colors = @[
		(id)[MLTheme surfaceContainerHigh].CGColor,
		(id)[MLTheme surface].CGColor,
		(id)[MLTheme background].CGColor
	];
	_bgGradient.locations = @[@0.0f, @0.55f, @1.0f];
	[self.view.layer insertSublayer:_bgGradient atIndex:0];

	// Top Drag Handle
	_dragHandle = [[UIView alloc] initWithFrame:CGRectZero];
	_dragHandle.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.28f];
	_dragHandle.layer.cornerRadius = 2.0f;
	[self.view addSubview:_dragHandle];

	// Dismiss Chevron Button
	_closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[_closeButton setImage:[MLIcon icon:@"expand_more" size:28.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_closeButton addTarget:self action:@selector(closeTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_closeButton];

	// Equalizer Button (Top Right Header)
	_eqButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[_eqButton setImage:[MLIcon icon:@"equalizer" size:24.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_eqButton addTarget:self action:@selector(eqTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_eqButton];

	// Header Subtitle: "NOW PLAYING"
	_headerSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_headerSubtitleLabel.font = [UIFont boldSystemFontOfSize:11.0f];
	_headerSubtitleLabel.textColor = [MLTheme onSurfaceVariant];
	_headerSubtitleLabel.textAlignment = NSTextAlignmentCenter;
	_headerSubtitleLabel.backgroundColor = [UIColor clearColor];
	_headerSubtitleLabel.text = MLLocalizedString(@"now_playing", nil);
	[self.view addSubview:_headerSubtitleLabel];

	// Header Title: Mix or Queue Context Title
	_headerTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_headerTitleLabel.font = [UIFont boldSystemFontOfSize:14.0f];
	_headerTitleLabel.textColor = [MLTheme onSurface];
	_headerTitleLabel.textAlignment = NSTextAlignmentCenter;
	_headerTitleLabel.backgroundColor = [UIColor clearColor];
	_headerTitleLabel.text = @"";
	[self.view addSubview:_headerTitleLabel];

	// Artwork Container with M3 Elevation Shadow
	_artContainer = [[UIView alloc] initWithFrame:CGRectZero];
	_artContainer.backgroundColor = [UIColor clearColor];
	_artContainer.layer.shadowColor = [UIColor blackColor].CGColor;
	_artContainer.layer.shadowOpacity = 0.50f;
	_artContainer.layer.shadowOffset = CGSizeMake(0, 8.0f);
	_artContainer.layer.shadowRadius = 18.0f;
	[self.view addSubview:_artContainer];

	_artView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_artView.contentMode = UIViewContentModeScaleAspectFill;
	_artView.clipsToBounds = YES;
	_artView.layer.cornerRadius = 18.0f;
	_artView.layer.borderWidth = 0.5f;
	_artView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.15f].CGColor;
	[_artContainer addSubview:_artView];

	// Lyrics Overlay View
	_lyricsView = [[MLLyricsView alloc] initWithFrame:CGRectZero];
	_lyricsView.hidden = YES;
	_lyricsView.alpha = 0.0f;
	_lyricsView.layer.cornerRadius = 18.0f;
	_lyricsView.clipsToBounds = YES;
	_lyricsView.onSeekRequested = ^(CGFloat targetSeconds) {
		[[MLPlaybackManager sharedManager] seekToTime:targetSeconds];
	};
	[self.view addSubview:_lyricsView];

	// Metadata: Title
	_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_titleLabel.font = [UIFont boldSystemFontOfSize:22.0f];
	_titleLabel.textColor = [MLTheme onSurface];
	_titleLabel.textAlignment = NSTextAlignmentLeft;
	_titleLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_titleLabel];

	// Metadata: Explicit Badge
	_explicitBadge = [[UILabel alloc] initWithFrame:CGRectZero];
	_explicitBadge.font = [UIFont boldSystemFontOfSize:10.0f];
	_explicitBadge.textColor = [MLTheme onSurfaceVariant];
	_explicitBadge.textAlignment = NSTextAlignmentCenter;
	_explicitBadge.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
	_explicitBadge.layer.cornerRadius = 3.0f;
	_explicitBadge.layer.borderWidth = 0.5f;
	_explicitBadge.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.25f].CGColor;
	_explicitBadge.clipsToBounds = YES;
	_explicitBadge.text = @"E";
	_explicitBadge.hidden = YES;
	[self.view addSubview:_explicitBadge];

	// Metadata: Artist
	_artistButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_artistButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	_artistButton.titleLabel.font = [UIFont systemFontOfSize:15.0f];
	_artistButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[_artistButton setTitleColor:[MLTheme onSurfaceVariant] forState:UIControlStateNormal];
	[_artistButton setTitleColor:[MLTheme primary] forState:UIControlStateHighlighted];
	[_artistButton addTarget:self action:@selector(artistTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_artistButton];

	// Paired Buttons: Share (left pill cap)
	_shareButton = [[MLShapeButton alloc] initWithFrame:CGRectZero];
	_shareButton.topLeftRadius = 21.0f;
	_shareButton.bottomLeftRadius = 21.0f;
	_shareButton.topRightRadius = 4.0f;
	_shareButton.bottomRightRadius = 4.0f;
	_shareButton.customFillColor = [UIColor whiteColor];
	[_shareButton setImage:[MLIcon icon:@"share" size:21.0f color:[UIColor blackColor]] forState:UIControlStateNormal];
	[_shareButton addTarget:self action:@selector(shareTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_shareButton];

	// Paired Buttons: Like (right pill cap)
	_likeButton = [[MLShapeButton alloc] initWithFrame:CGRectZero];
	_likeButton.topLeftRadius = 4.0f;
	_likeButton.bottomLeftRadius = 4.0f;
	_likeButton.topRightRadius = 21.0f;
	_likeButton.bottomRightRadius = 21.0f;
	_likeButton.customFillColor = [UIColor whiteColor];
	[_likeButton setImage:[MLIcon icon:@"favorite_border" size:21.0f color:[UIColor blackColor]] forState:UIControlStateNormal];
	[_likeButton addTarget:self action:@selector(likeTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_likeButton];

	// Progress Slider
	_seekBar = [[UISlider alloc] initWithFrame:CGRectZero];
	_seekBar.minimumTrackTintColor = [MLTheme primary];
	_seekBar.maximumTrackTintColor = [UIColor colorWithWhite:1.0f alpha:0.22f];
	UIImage *normalThumb = [MLTheme circleThumbWithColor:[MLTheme primary] diameter:14.0f];
	UIImage *activeThumb = [MLTheme circleThumbWithColor:[UIColor whiteColor] diameter:18.0f];
	[_seekBar setThumbImage:normalThumb forState:UIControlStateNormal];
	[_seekBar setThumbImage:activeThumb forState:UIControlStateHighlighted];
	[_seekBar addTarget:self action:@selector(seekChanged:) forControlEvents:UIControlEventValueChanged];
	[_seekBar addTarget:self action:@selector(seekFinished:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
	[self.view addSubview:_seekBar];

	// Time Labels
	_elapsedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_elapsedLabel.font = [MLTheme fontLabelMedium];
	_elapsedLabel.textColor = [MLTheme onSurfaceVariant];
	_elapsedLabel.backgroundColor = [UIColor clearColor];
	_elapsedLabel.text = @"0:00";
	[self.view addSubview:_elapsedLabel];

	_durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_durationLabel.font = [MLTheme fontLabelMedium];
	_durationLabel.textColor = [MLTheme onSurfaceVariant];
	_durationLabel.textAlignment = NSTextAlignmentRight;
	_durationLabel.backgroundColor = [UIColor clearColor];
	_durationLabel.text = @"0:00";
	[self.view addSubview:_durationLabel];

	_statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_statusLabel.font = [MLTheme fontLabelMedium];
	_statusLabel.textColor = [MLTheme primaryContainer];
	_statusLabel.textAlignment = NSTextAlignmentCenter;
	_statusLabel.backgroundColor = [UIColor clearColor];
	_statusLabel.adjustsFontSizeToFitWidth = YES;
	_statusLabel.minimumFontSize = 9.0f;
	[self.view addSubview:_statusLabel];

	// Transport Row: Previous (Circle)
	_prevButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_prevButton.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
	[_prevButton setImage:[MLIcon icon:@"skip_previous" size:28.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_prevButton addTarget:self action:@selector(prevTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_prevButton];

	// Transport Row: Prominent Stadium Play/Pause Pill
	_playButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_playButton.backgroundColor = [UIColor whiteColor];
	_playButton.clipsToBounds = YES;
	_playButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0f];
	_playButton.titleLabel.adjustsFontSizeToFitWidth = YES;
	_playButton.titleLabel.minimumFontSize = 12.0f;
	[_playButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
	[_playButton setTitleColor:[UIColor colorWithWhite:0.25f alpha:1.0f] forState:UIControlStateHighlighted];
	_playButton.imageEdgeInsets = UIEdgeInsetsMake(0, -6.0f, 0, 6.0f);
	_playButton.titleEdgeInsets = UIEdgeInsetsMake(0, 6.0f, 0, -6.0f);
	[_playButton setImage:[MLIcon icon:@"play_arrow" size:28.0f color:[UIColor blackColor]] forState:UIControlStateNormal];
	[_playButton setTitle:MLLocalizedString(@"play", nil) forState:UIControlStateNormal];
	[_playButton addTarget:self action:@selector(playTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_playButton];

	// Transport Row: Next (Circle)
	_nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_nextButton.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
	[_nextButton setImage:[MLIcon icon:@"skip_next" size:28.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_nextButton addTarget:self action:@selector(nextTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_nextButton];

	// Bottom Utility Bar: 1. Queue (left pill cap)
	_queueButton = [[MLShapeButton alloc] initWithFrame:CGRectZero];
	_queueButton.topLeftRadius = 21.0f;
	_queueButton.bottomLeftRadius = 21.0f;
	_queueButton.topRightRadius = 4.0f;
	_queueButton.bottomRightRadius = 4.0f;
	_queueButton.customFillColor = [UIColor clearColor];
	_queueButton.customBorderColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
	_queueButton.customBorderWidth = 1.0f;
	[_queueButton setImage:[MLIcon icon:@"queue_music" size:20.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_queueButton addTarget:self action:@selector(queueTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_queueButton];

	// Bottom Utility Bar: 2. Sleep Timer (middle squircle)
	_sleepButton = [[MLShapeButton alloc] initWithFrame:CGRectZero];
	_sleepButton.topLeftRadius = 4.0f;
	_sleepButton.bottomLeftRadius = 4.0f;
	_sleepButton.topRightRadius = 4.0f;
	_sleepButton.bottomRightRadius = 4.0f;
	_sleepButton.customFillColor = [UIColor clearColor];
	_sleepButton.customBorderColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
	_sleepButton.customBorderWidth = 1.0f;
	[_sleepButton setImage:[MLIcon icon:@"bedtime" size:20.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_sleepButton addTarget:self action:@selector(sleepTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_sleepButton];

	// Bottom Utility Bar: 3. Shuffle (middle squircle)
	_shuffleButton = [[MLShapeButton alloc] initWithFrame:CGRectZero];
	_shuffleButton.topLeftRadius = 4.0f;
	_shuffleButton.bottomLeftRadius = 4.0f;
	_shuffleButton.topRightRadius = 4.0f;
	_shuffleButton.bottomRightRadius = 4.0f;
	_shuffleButton.customFillColor = [UIColor clearColor];
	_shuffleButton.customBorderColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
	_shuffleButton.customBorderWidth = 1.0f;
	[_shuffleButton setImage:[MLIcon icon:@"shuffle" size:20.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_shuffleButton addTarget:self action:@selector(shuffleTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_shuffleButton];

	// Bottom Utility Bar: 4. Lyrics (middle squircle)
	_lyricsButton = [[MLShapeButton alloc] initWithFrame:CGRectZero];
	_lyricsButton.topLeftRadius = 4.0f;
	_lyricsButton.bottomLeftRadius = 4.0f;
	_lyricsButton.topRightRadius = 4.0f;
	_lyricsButton.bottomRightRadius = 4.0f;
	_lyricsButton.customFillColor = [UIColor clearColor];
	_lyricsButton.customBorderColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
	_lyricsButton.customBorderWidth = 1.0f;
	[_lyricsButton setImage:[MLIcon icon:@"lyrics" size:20.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_lyricsButton addTarget:self action:@selector(toggleLyrics:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_lyricsButton];

	// Bottom Utility Bar: 5. Repeat (right pill cap)
	_repeatButton = [[MLShapeButton alloc] initWithFrame:CGRectZero];
	_repeatButton.topLeftRadius = 4.0f;
	_repeatButton.bottomLeftRadius = 4.0f;
	_repeatButton.topRightRadius = 21.0f;
	_repeatButton.bottomRightRadius = 21.0f;
	_repeatButton.customFillColor = [UIColor clearColor];
	_repeatButton.customBorderColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
	_repeatButton.customBorderWidth = 1.0f;
	[_repeatButton setImage:[MLIcon icon:@"repeat" size:20.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_repeatButton addTarget:self action:@selector(repeatTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_repeatButton];

	// Bottom Utility Bar: 6. More (Round Circle Button)
	_moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_moreButton.backgroundColor = [UIColor whiteColor];
	_moreButton.clipsToBounds = YES;
	[_moreButton setImage:[MLIcon icon:@"more_vert" size:22.0f color:[UIColor blackColor]] forState:UIControlStateNormal];
	[_moreButton addTarget:self action:@selector(moreTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_moreButton];

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleVerticalPan:)];
	[self.view addGestureRecognizer:pan];
}

- (void)viewSafeAreaInsetsDidChange
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
	if ([UIViewController instancesRespondToSelector:@selector(viewSafeAreaInsetsDidChange)]) {
		[super viewSafeAreaInsetsDidChange];
	}
#endif
	[self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	CGRect b = self.view.bounds;
	CGFloat W = b.size.width;
	CGFloat H = b.size.height;

	BOOL is35Inch = (H <= 480.0f);
	BOOL isCompact = (H <= 568.0f); // 320pt wide devices (iPhone 4s, 5, 5s, SE1)
	BOOL isTall = (H >= 812.0f);    // Modern notch / Dynamic Island

	CGFloat topInset = [MLTheme safeAreaTopInsetForView:self.view];
	CGFloat bottomInset = [MLTheme safeAreaBottomInsetForView:self.view];

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_bgGradient.frame = b;
	[CATransaction commit];

	// Top Drag Handle
	_dragHandle.frame = CGRectMake((W - 36.0f) / 2.0f, topInset + 6.0f, 36.0f, 4.0f);

	// Header Bar
	CGFloat topY = topInset + (isCompact ? 4.0f : 10.0f);
	CGFloat closeBtnSize = isCompact ? 34.0f : 38.0f;
	_closeButton.frame = CGRectMake(14.0f, topY, closeBtnSize, closeBtnSize);
	_eqButton.frame = CGRectMake(W - 14.0f - closeBtnSize, topY, closeBtnSize, closeBtnSize);

	CGFloat headerTextW = W - (14.0f + closeBtnSize + 8.0f) * 2.0f;
	_headerSubtitleLabel.frame = CGRectMake((W - headerTextW) / 2.0f, topY + 2.0f, headerTextW, 14.0f);
	_headerTitleLabel.frame = CGRectMake((W - headerTextW) / 2.0f, topY + 18.0f, headerTextW, 18.0f);
	CGFloat headerBottom = topY + (isCompact ? 36.0f : 40.0f);

	// Bottom Utility Action Bar
	CGFloat bottomBtnH = isCompact ? 36.0f : (isTall ? 44.0f : 40.0f);
	CGFloat bottomMargin = bottomInset + (isCompact ? 8.0f : 16.0f);
	CGFloat bottomBarY = H - bottomBtnH - bottomMargin;

	CGFloat bottomMarginSide = isCompact ? 16.0f : 24.0f;
	CGFloat bottomAvailableW = W - bottomMarginSide * 2.0f;
	CGFloat btnGap = isCompact ? 4.0f : 6.0f;
	CGFloat moreBtnW = bottomBtnH;
	CGFloat maxFiveW = bottomAvailableW - moreBtnW - (isCompact ? 12.0f : 20.0f);
	CGFloat utilBtnW = floorf(MIN(isCompact ? 36.0f : 44.0f, (maxFiveW - btnGap * 4.0f) / 5.0f));

	_queueButton.frame = CGRectMake(bottomMarginSide + (utilBtnW + btnGap) * 0, bottomBarY, utilBtnW, bottomBtnH);
	_queueButton.topLeftRadius = bottomBtnH / 2.0f;
	_queueButton.bottomLeftRadius = bottomBtnH / 2.0f;
	_queueButton.topRightRadius = 4.0f;
	_queueButton.bottomRightRadius = 4.0f;

	_sleepButton.frame = CGRectMake(bottomMarginSide + (utilBtnW + btnGap) * 1, bottomBarY, utilBtnW, bottomBtnH);
	_sleepButton.topLeftRadius = 4.0f;
	_sleepButton.bottomLeftRadius = 4.0f;
	_sleepButton.topRightRadius = 4.0f;
	_sleepButton.bottomRightRadius = 4.0f;

	_shuffleButton.frame = CGRectMake(bottomMarginSide + (utilBtnW + btnGap) * 2, bottomBarY, utilBtnW, bottomBtnH);
	_shuffleButton.topLeftRadius = 4.0f;
	_shuffleButton.bottomLeftRadius = 4.0f;
	_shuffleButton.topRightRadius = 4.0f;
	_shuffleButton.bottomRightRadius = 4.0f;

	_lyricsButton.frame = CGRectMake(bottomMarginSide + (utilBtnW + btnGap) * 3, bottomBarY, utilBtnW, bottomBtnH);
	_lyricsButton.topLeftRadius = 4.0f;
	_lyricsButton.bottomLeftRadius = 4.0f;
	_lyricsButton.topRightRadius = 4.0f;
	_lyricsButton.bottomRightRadius = 4.0f;

	_repeatButton.frame = CGRectMake(bottomMarginSide + (utilBtnW + btnGap) * 4, bottomBarY, utilBtnW, bottomBtnH);
	_repeatButton.topLeftRadius = 4.0f;
	_repeatButton.bottomLeftRadius = 4.0f;
	_repeatButton.topRightRadius = bottomBtnH / 2.0f;
	_repeatButton.bottomRightRadius = bottomBtnH / 2.0f;

	_moreButton.frame = CGRectMake(W - bottomMarginSide - moreBtnW, bottomBarY, moreBtnW, bottomBtnH);
	_moreButton.layer.cornerRadius = moreBtnW / 2.0f;

	// Transport Row Dimensions
	CGFloat transportH = isCompact ? 50.0f : (isTall ? 68.0f : 60.0f);
	CGFloat sideBtnSize = transportH;
	CGFloat playW = isCompact ? 124.0f : (isTall ? 170.0f : 148.0f);
	CGFloat midX = W / 2.0f;
	CGFloat transportSpacing = isCompact ? 10.0f : 16.0f;

	// Progress Slider Dimensions
	CGFloat sliderH = isCompact ? 34.0f : 42.0f;

	// Metadata Row Dimensions
	CGFloat metaH = isCompact ? 40.0f : 48.0f;
	CGFloat actionBtnSize = isCompact ? 36.0f : 42.0f;
	CGFloat actionGap = 6.0f;
	CGFloat actionsTotalW = actionBtnSize * 2.0f + actionGap;
	CGFloat textW = W - 24.0f - actionsTotalW - 14.0f;

	// Proportional Artwork Sizing: calibrated per screen height class
	CGFloat maxArtW = MIN(W - 48.0f, 420.0f);
	CGFloat artSize;
	if (is35Inch) {
		artSize = 136.0f;
	} else if (isCompact) {
		// 4-inch iPhone 5/5s/SE1: leaves ~400pt for UI and generous breathing space
		artSize = 168.0f;
	} else if (isTall) {
		artSize = MIN(maxArtW, 380.0f);
	} else {
		// Medium devices (iPhone 6/7/8)
		artSize = MIN(maxArtW, 250.0f);
	}

	// Dynamic Flex Spacing to eliminate dead void while giving ample room on small devices
	CGFloat remainingSpace = bottomBarY - (headerBottom + artSize + metaH + sliderH + transportH);
	CGFloat gap = MAX(isCompact ? 10.0f : 14.0f, remainingSpace / 4.2f);

	CGFloat artY = headerBottom + gap * 0.7f;
	_artContainer.frame = CGRectMake((W - artSize) / 2.0f, artY, artSize, artSize);
	_artView.frame = _artContainer.bounds;
	_lyricsView.frame = _artContainer.frame;

	CGFloat metaY = artY + artSize + gap * 0.85f;
	_titleLabel.frame = CGRectMake(24.0f, metaY, textW, isCompact ? 22.0f : 26.0f);
	_titleLabel.font = [UIFont boldSystemFontOfSize:(isCompact ? 19.0f : 22.0f)];

	BOOL hasExplicit = _explicitBadge && !_explicitBadge.hidden;
	CGFloat artistX = 24.0f;
	CGFloat artistY = metaY + (isCompact ? 22.0f : 26.0f);
	if (hasExplicit) {
		_explicitBadge.frame = CGRectMake(24.0f, artistY + 2.0f, 16.0f, 16.0f);
		artistX += 22.0f;
	}
	_artistButton.frame = CGRectMake(artistX, artistY, textW - (hasExplicit ? 22.0f : 0.0f), 20.0f);
	_artistButton.titleLabel.font = [UIFont systemFontOfSize:(isCompact ? 14.0f : 15.0f)];

	_shareButton.frame = CGRectMake(W - 24.0f - actionsTotalW, metaY + (metaH - actionBtnSize) / 2.0f, actionBtnSize, actionBtnSize);
	_shareButton.topLeftRadius = actionBtnSize / 2.0f;
	_shareButton.bottomLeftRadius = actionBtnSize / 2.0f;
	_shareButton.topRightRadius = 4.0f;
	_shareButton.bottomRightRadius = 4.0f;

	_likeButton.frame = CGRectMake(W - 24.0f - actionBtnSize, metaY + (metaH - actionBtnSize) / 2.0f, actionBtnSize, actionBtnSize);
	_likeButton.topLeftRadius = 4.0f;
	_likeButton.bottomLeftRadius = 4.0f;
	_likeButton.topRightRadius = actionBtnSize / 2.0f;
	_likeButton.bottomRightRadius = actionBtnSize / 2.0f;

	CGFloat sliderY = metaY + metaH + gap * 0.65f;
	_seekBar.frame = CGRectMake(isCompact ? 20.0f : 22.0f, sliderY, W - (isCompact ? 40.0f : 44.0f), 22.0f);

	CGFloat timeY = sliderY + (isCompact ? 18.0f : 20.0f);
	_elapsedLabel.frame = CGRectMake(24.0f, timeY, 56.0f, 14.0f);
	_durationLabel.frame = CGRectMake(W - 80.0f, timeY, 56.0f, 14.0f);
	_statusLabel.frame = CGRectMake(82.0f, timeY, W - 164.0f, 14.0f);

	// Vertically center transport controls in the remaining space before bottom utility bar
	CGFloat spaceForTransport = bottomBarY - (timeY + 14.0f);
	CGFloat transportY = (timeY + 14.0f) + MAX(gap * 0.6f, (spaceForTransport - transportH) / 2.0f);

	_playButton.frame = CGRectMake(midX - playW / 2.0f, transportY, playW, transportH);
	_playButton.layer.cornerRadius = transportH / 2.0f;
	_playButton.titleLabel.font = [UIFont boldSystemFontOfSize:(isCompact ? 15.0f : 17.0f)];

	_prevButton.frame = CGRectMake(midX - playW / 2.0f - transportSpacing - sideBtnSize, transportY, sideBtnSize, sideBtnSize);
	_prevButton.layer.cornerRadius = sideBtnSize / 2.0f;

	_nextButton.frame = CGRectMake(midX + playW / 2.0f + transportSpacing, transportY, sideBtnSize, sideBtnSize);
	_nextButton.layer.cornerRadius = sideBtnSize / 2.0f;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(stateChanged:)
	                                             name:MLPlaybackStateChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(stateChanged:)
	                                             name:MLLibraryDidUpdateNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(languageChanged:)
	                                             name:MLLanguageChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(sponsorBlockSkipped:)
	                                             name:MLSponsorBlockDidSkipNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(themeChanged:)
	                                             name:MLThemeDidChangeNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(equalizerChanged:)
	                                             name:MLEqualizerDidChangeNotification
	                                           object:nil];
}

- (void)equalizerChanged:(NSNotification *)note
{
	[self updateEqualizerButtonState];
}

- (void)updateEqualizerButtonState
{
	BOOL eqOn = [MLEqualizerManager sharedManager].enabled;
	UIColor *col = eqOn ? [MLTheme primary] : [MLTheme onSurface];
	[_eqButton setImage:[MLIcon icon:@"equalizer" size:24.0f color:col] forState:UIControlStateNormal];
}

- (void)themeChanged:(NSNotification *)note
{
	self.view.backgroundColor = [MLTheme background];
	_seekBar.minimumTrackTintColor = [MLTheme primary];
	_seekBar.thumbTintColor = [MLTheme primary];
	[self updateEqualizerButtonState];
	[self reload];
}

- (void)sponsorBlockSkipped:(NSNotification *)note
{
	_statusLabel.textColor = [MLTheme primary];
	_statusLabel.text = MLLocalizedString(@"sponsorblock_skipped", nil);
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearSponsorBlockStatus) object:nil];
	[self performSelector:@selector(clearSponsorBlockStatus) withObject:nil afterDelay:2.5];
}

- (void)clearSponsorBlockStatus
{
	if ([_statusLabel.text isEqualToString:MLLocalizedString(@"sponsorblock_skipped", nil)]) {
		_statusLabel.text = @"";
	}
}

- (void)toggleLyrics:(UIButton *)sender
{
	_showingLyrics = !_showingLyrics;
	_lyricsButton.customFillColor = _showingLyrics ? [UIColor whiteColor] : [UIColor clearColor];
	_lyricsButton.customBorderColor = _showingLyrics ? nil : [UIColor colorWithWhite:1.0f alpha:0.25f];
	_lyricsButton.customBorderWidth = _showingLyrics ? 0.0f : 1.0f;
	BOOL isCompact = (self.view.bounds.size.height <= 568.0f);
	CGFloat utilIconSize = isCompact ? 18.0f : 20.0f;
	[_lyricsButton setImage:[MLIcon icon:@"lyrics" size:utilIconSize color:(_showingLyrics ? [UIColor blackColor] : [MLTheme onSurface])] forState:UIControlStateNormal];

	if (_showingLyrics) {
		_lyricsView.hidden = NO;
		[UIView animateWithDuration:0.25 animations:^{
			self->_artContainer.alpha = 0.0f;
			self->_lyricsView.alpha = 1.0f;
		} completion:^(BOOL finished) {
			self->_artContainer.hidden = YES;
		}];
	} else {
		_artContainer.hidden = NO;
		[UIView animateWithDuration:0.25 animations:^{
			self->_artContainer.alpha = 1.0f;
			self->_lyricsView.alpha = 0.0f;
		} completion:^(BOOL finished) {
			self->_lyricsView.hidden = YES;
		}];
	}
}

- (void)languageChanged:(NSNotification *)n
{
	_headerSubtitleLabel.text = MLLocalizedString(@"now_playing", nil);
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	_viewIsVisible = YES;
	[self updateEqualizerButtonState];
	[self reload];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	_viewIsVisible = NO;
}

- (void)stateChanged:(NSNotification *)n
{
	if (!_viewIsVisible)
		return;
	[self reload];
}

- (void)handleVerticalPan:(UIPanGestureRecognizer *)pan
{
	if (_seeking)
		return;
	CGPoint trans = [pan translationInView:self.view.superview ?: self.view];
	if (pan.state == UIGestureRecognizerStateChanged) {
		if (trans.y > 0) {
			self.view.transform = CGAffineTransformMakeTranslation(0, trans.y);
		}
	} else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		CGPoint vel = [pan velocityInView:self.view.superview ?: self.view];
		if (trans.y > 110.0f || vel.y > 650.0f) {
			[self closeTap:nil];
		} else {
			[UIView animateWithDuration:0.22f animations:^{
				self.view.transform = CGAffineTransformIdentity;
			}];
		}
	}
}

- (void)closeTap:(UIButton *)sender
{
	_viewIsVisible = NO;
	if (_delegate && [_delegate respondsToSelector:@selector(playerViewControllerDidClose:)])
		[_delegate playerViewControllerDidClose:self];
}

- (void)eqTap:(UIButton *)sender
{
	[MLTheme triggerImpactHaptic];
	MLEqualizerViewController *eqVC = [[MLEqualizerViewController alloc] init];
	[self presentViewController:eqVC animated:YES completion:nil];
}

- (void)moreTap:(UIButton *)sender
{
	MLYTItem *item = [MLPlaybackManager sharedManager].currentItem;
	if (item) {
		[MLNavigator presentSongMenuForItem:item fromViewController:self];
	}
}

- (void)sleepTap:(UIButton *)sender
{
	[MLNavigator presentSleepTimerPickerFromViewController:self];
}

- (void)artistTap:(UIButton *)sender
{
	MLYTItem *item = [MLPlaybackManager sharedManager].currentItem;
	if (!item || !item.artistBrowseId.length)
		return;
	NSString *artistName = item.artists.count ? item.artists[0] : (item.subtitle ?: @"");
	UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
	if ([root isKindOfClass:[MLRootViewController class]]) {
		MLRootViewController *mlRoot = (MLRootViewController *)root;
		UINavigationController *nav = [mlRoot navigationControllerForTab:0];
		if (nav) {
			[self closeTap:nil];
			[mlRoot switchToTabIndex:0];
			MLArtistViewController *artistVC = [[MLArtistViewController alloc] initWithBrowseId:item.artistBrowseId name:artistName];
			[nav pushViewController:artistVC animated:YES];
		}
	}
}

- (void)shareTap:(UIButton *)sender
{
	MLYTItem *item = [MLPlaybackManager sharedManager].currentItem;
	if (!item || !item.videoId.length)
		return;
	NSString *urlStr = [NSString stringWithFormat:@"https://music.youtube.com/watch?v=%@", item.videoId];
	[UIPasteboard generalPasteboard].string = urlStr;
	_statusLabel.textColor = [MLTheme onSurface];
	_statusLabel.text = MLLocalizedString(@"copied_title", nil);
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearSponsorBlockStatus) object:nil];
	[self performSelector:@selector(clearSponsorBlockStatus) withObject:nil afterDelay:2.0];
}

- (void)playTap:(UIButton *)sender
{
	[[MLPlaybackManager sharedManager] togglePlayPause];
	[self reload];
}

- (void)nextTap:(UIButton *)sender
{
	[[MLPlaybackManager sharedManager] next];
}

- (void)prevTap:(UIButton *)sender
{
	[[MLPlaybackManager sharedManager] previous];
}

- (void)shuffleTap:(UIButton *)sender
{
	[[MLPlaybackManager sharedManager] toggleShuffle];
	[self reload];
}

- (void)repeatTap:(UIButton *)sender
{
	[[MLPlaybackManager sharedManager] toggleRepeat];
	[self reload];
}

- (void)queueTap:(id)sender
{
	MLQueueViewController *queueVC = [[MLQueueViewController alloc] init];
	[self presentViewController:queueVC animated:YES completion:nil];
}

- (void)likeTap:(UIButton *)sender
{
	MLYTItem *item = [MLPlaybackManager sharedManager].currentItem;
	if (!item || !item.videoId.length) return;
	[[MLLibraryManager sharedManager] toggleLikeForSong:item completion:nil];
	_liked = [[MLLibraryManager sharedManager] isSongLiked:item.videoId];
	NSString *icon = _liked ? @"favorite" : @"favorite_border";
	UIColor *color = _liked ? [UIColor colorWithRed:0.89f green:0.26f blue:0.21f alpha:1.0f] : [UIColor blackColor];
	BOOL isCompact = (self.view.bounds.size.height <= 568.0f);
	CGFloat actionIconSize = isCompact ? 18.0f : 21.0f;
	[_likeButton setImage:[MLIcon icon:icon size:actionIconSize color:color] forState:UIControlStateNormal];
}

- (void)seekChanged:(UISlider *)slider
{
	_seeking = YES;
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	CGFloat dur = pm.duration ?: pm.currentItem.duration;
	if (dur > 0) {
		CGFloat cur = slider.value * dur;
		_elapsedLabel.text = MLFormatDuration(cur);
		_durationLabel.text = MLFormatDuration(dur);
	}
}

- (void)seekFinished:(UISlider *)slider
{
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	CGFloat dur = pm.duration ?: pm.currentItem.duration;
	if (dur > 0)
		[pm seekToTime:slider.value * dur];
	_seeking = NO;
}

- (void)reload
{
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	MLYTItem *item = pm.currentItem;
	if (!item)
		return;

	BOOL isCompact = (self.view.bounds.size.height <= 568.0f);
	CGFloat actionIconSize = isCompact ? 18.0f : 21.0f;
	CGFloat utilIconSize = isCompact ? 18.0f : 20.0f;

	// Share Button Icon
	[_shareButton setImage:[MLIcon icon:@"share" size:actionIconSize color:[UIColor blackColor]] forState:UIControlStateNormal];

	// Like Button Icon
	_liked = [[MLLibraryManager sharedManager] isSongLiked:item.videoId];
	NSString *likeIcon = _liked ? @"favorite" : @"favorite_border";
	UIColor *likeColor = _liked ? [UIColor colorWithRed:0.89f green:0.26f blue:0.21f alpha:1.0f] : [UIColor blackColor];
	[_likeButton setImage:[MLIcon icon:likeIcon size:actionIconSize color:likeColor] forState:UIControlStateNormal];

	// More Button Icon
	[_moreButton setImage:[MLIcon icon:@"more_vert" size:actionIconSize color:[UIColor blackColor]] forState:UIControlStateNormal];

	_titleLabel.text = item.title ?: @"";
	NSString *artistText = item.artists.count ? [item.artists componentsJoinedByString:@", "] : (item.subtitle ?: @"");
	[_artistButton setTitle:artistText forState:UIControlStateNormal];

	BOOL isExplicit = item.isExplicit;
	_explicitBadge.hidden = !isExplicit;

	// Header Context Title
	if (item.title.length > 0) {
		_headerTitleLabel.text = [NSString stringWithFormat:@"%@ Mix", item.title];
	} else {
		_headerTitleLabel.text = MLLocalizedString(@"up_next", nil);
	}

	if (item.thumbnailUrl && ![item.thumbnailUrl isEqualToString:_lastThumbUrl]) {
		_lastThumbUrl = [item.thumbnailUrl copy];
		__weak MLPlayerViewController *wself = self;
		CGSize artTargetSize = CGSizeMake(380.0f, 380.0f);
		[MLImageCache loadImageAtURLString:item.thumbnailUrl
		                          intoView:_artView
		                           fitSize:artTargetSize
		                      cornerRadius:18.0f
		                       placeholder:[MLImageCache placeholderImageWithSize:artTargetSize]
		                        completion:^(UIImage *image) {
			__strong MLPlayerViewController *s = wself;
			if (!s || !image)
				return;
			UIColor *dom = [MLTheme dominantColorForImage:image];
			[MLTheme setDynamicAccentColor:dom];
			UIColor *topGlow = [MLTheme blendColor:dom overBackground:[MLTheme background] alpha:0.40f];
			s->_bgGradient.colors = @[
				(id)topGlow.CGColor,
				(id)[MLTheme surface].CGColor,
				(id)[MLTheme background].CGColor
			];
		}];
	}

	// Prominent Stadium Play/Pause button
	BOOL isPlaying = pm.playing;
	NSString *playIcon = isPlaying ? @"pause" : @"play_arrow";
	NSString *playTitle = isPlaying ? MLLocalizedString(@"pause", nil) : MLLocalizedString(@"play", nil);
	CGFloat playIconSize = isCompact ? 24.0f : 28.0f;
	[_playButton setImage:[MLIcon icon:playIcon size:playIconSize color:[UIColor blackColor]] forState:UIControlStateNormal];
	[_playButton setTitle:playTitle forState:UIControlStateNormal];

	[UIView animateWithDuration:0.18f animations:^{
		self->_artView.transform = isPlaying ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.94f, 0.94f);
	}];

	// Utility Bar: Queue Icon
	[_queueButton setImage:[MLIcon icon:@"queue_music" size:utilIconSize color:[MLTheme onSurface]] forState:UIControlStateNormal];

	// Utility Bar: Shuffle State
	BOOL shuffleOn = pm.shuffle;
	_shuffleButton.customFillColor = shuffleOn ? [UIColor whiteColor] : [UIColor clearColor];
	_shuffleButton.customBorderColor = shuffleOn ? nil : [UIColor colorWithWhite:1.0f alpha:0.25f];
	_shuffleButton.customBorderWidth = shuffleOn ? 0.0f : 1.0f;
	[_shuffleButton setImage:[MLIcon icon:@"shuffle" size:utilIconSize color:(shuffleOn ? [UIColor blackColor] : [MLTheme onSurface])] forState:UIControlStateNormal];

	// Utility Bar: Repeat State
	BOOL repeatActive = (pm.repeatMode != MLRepeatModeOff);
	_repeatButton.customFillColor = repeatActive ? [UIColor whiteColor] : [UIColor clearColor];
	_repeatButton.customBorderColor = repeatActive ? nil : [UIColor colorWithWhite:1.0f alpha:0.25f];
	_repeatButton.customBorderWidth = repeatActive ? 0.0f : 1.0f;
	NSString *repeatIcon = (pm.repeatMode == MLRepeatModeOne) ? @"repeat_one" : @"repeat";
	[_repeatButton setImage:[MLIcon icon:repeatIcon size:utilIconSize color:(repeatActive ? [UIColor blackColor] : [MLTheme onSurface])] forState:UIControlStateNormal];

	// Utility Bar: Sleep Timer State
	BOOL sleepActive = pm.sleepTimerActive;
	_sleepButton.customFillColor = sleepActive ? [UIColor whiteColor] : [UIColor clearColor];
	_sleepButton.customBorderColor = sleepActive ? nil : [UIColor colorWithWhite:1.0f alpha:0.25f];
	_sleepButton.customBorderWidth = sleepActive ? 0.0f : 1.0f;
	[_sleepButton setImage:[MLIcon icon:@"bedtime" size:utilIconSize color:(sleepActive ? [UIColor blackColor] : [MLTheme onSurface])] forState:UIControlStateNormal];

	// Utility Bar: Lyrics State
	_lyricsButton.customFillColor = _showingLyrics ? [UIColor whiteColor] : [UIColor clearColor];
	_lyricsButton.customBorderColor = _showingLyrics ? nil : [UIColor colorWithWhite:1.0f alpha:0.25f];
	_lyricsButton.customBorderWidth = _showingLyrics ? 0.0f : 1.0f;
	[_lyricsButton setImage:[MLIcon icon:@"lyrics" size:utilIconSize color:(_showingLyrics ? [UIColor blackColor] : [MLTheme onSurface])] forState:UIControlStateNormal];

	if (pm.statusError) {
		_statusLabel.textColor = [MLTheme error];
		_statusLabel.text = pm.statusError;
	} else if (pm.buffering) {
		_statusLabel.textColor = [MLTheme onSurfaceVariant];
		_statusLabel.text = MLLocalizedString(@"loading_audio", nil);
	} else if (![_statusLabel.text isEqualToString:MLLocalizedString(@"copied_title", nil)] &&
	           ![_statusLabel.text isEqualToString:MLLocalizedString(@"sponsorblock_skipped", nil)]) {
		_statusLabel.text = @"";
	}

	if (!_seeking) {
		CGFloat dur = pm.duration ?: item.duration;
		CGFloat cur = pm.currentTime;
		
		// Always show elapsed time
		_elapsedLabel.text = MLFormatDuration(cur);
		
		if (dur > 0) {
			// Known duration: show progress and remaining time
			_seekBar.value = MIN(1.0f, MAX(0.0f, cur / dur));
			_durationLabel.text = MLFormatDuration(dur);
		} else {
			// Unknown duration: show elapsed, progress bar at 0 (or indeterminate)
			_seekBar.value = 0;
			_durationLabel.text = @"--:--";
		}
	}

	if (_lyricsView) {
		if (item.videoId.length && ![item.videoId isEqualToString:_lastLyricsVideoId]) {
			_lastLyricsVideoId = [item.videoId copy];
			NSString *artName = item.artists.count ? item.artists[0] : (item.subtitle ?: @"");
			CGFloat dur = pm.duration ?: item.duration;
			[_lyricsView loadLyricsForTitle:item.title artist:artName duration:dur videoId:item.videoId];
		}
		[_lyricsView updateCurrentPlaybackTime:pm.currentTime];
	}
}

@end
