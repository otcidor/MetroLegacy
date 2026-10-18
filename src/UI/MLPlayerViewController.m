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
#import <QuartzCore/QuartzCore.h>

@interface MLPlayerViewController ()
{
	CAGradientLayer *_bgGradient;
	UIView *_dragHandle;
	UIButton *_closeButton;
	UILabel *_headerLabel;
	UIButton *_moreButton;
	UIButton *_lyricsButton;

	UIView *_artContainer;
	UIImageView *_artView;
	MLLyricsView *_lyricsView;
	BOOL _showingLyrics;

	UILabel *_titleLabel;
	UIButton *_artistButton;
	UIButton *_shareButton;
	UIButton *_likeButton;

	UILabel *_statusLabel;
	UILabel *_elapsedLabel;
	UILabel *_durationLabel;
	UISlider *_seekBar;

	UIButton *_shuffleButton;
	UIButton *_prevButton;
	UIButton *_playButton;
	UIButton *_nextButton;
	UIButton *_repeatButton;

	UIControl *_queueBar;
	UIImageView *_queueIconView;
	UILabel *_queueTitleLabel;
	UIImageView *_queueChevronView;

	NSString *_lastThumbUrl;
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

	_dragHandle = [[UIView alloc] initWithFrame:CGRectZero];
	_dragHandle.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.28f];
	_dragHandle.layer.cornerRadius = 2.0f;
	[self.view addSubview:_dragHandle];

	_closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[_closeButton setImage:[MLIcon icon:@"expand_more" size:28.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_closeButton addTarget:self action:@selector(closeTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_closeButton];

	_headerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_headerLabel.font = [UIFont boldSystemFontOfSize:11.0f];
	_headerLabel.textColor = [MLTheme onSurfaceVariant];
	_headerLabel.textAlignment = NSTextAlignmentCenter;
	_headerLabel.backgroundColor = [UIColor clearColor];
	_headerLabel.text = MLLocalizedString(@"now_playing", nil);
	[self.view addSubview:_headerLabel];

	_moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[_moreButton setImage:[MLIcon icon:@"more_vert" size:24.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_moreButton addTarget:self action:@selector(moreTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_moreButton];

	_lyricsButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[_lyricsButton setImage:[MLIcon icon:@"lyrics" size:22.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
	[_lyricsButton addTarget:self action:@selector(toggleLyrics:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_lyricsButton];

	_artContainer = [[UIView alloc] initWithFrame:CGRectZero];
	_artContainer.backgroundColor = [UIColor clearColor];
	_artContainer.layer.shadowColor = [UIColor blackColor].CGColor;
	_artContainer.layer.shadowOpacity = 0.50f;
	_artContainer.layer.shadowOffset = CGSizeMake(0, 10.0f);
	_artContainer.layer.shadowRadius = 16.0f;
	[self.view addSubview:_artContainer];

	_lyricsView = [[MLLyricsView alloc] initWithFrame:CGRectZero];
	_lyricsView.hidden = YES;
	_lyricsView.alpha = 0.0f;
	_lyricsView.onSeekRequested = ^(CGFloat targetSeconds) {
		[[MLPlaybackManager sharedManager] seekToTime:targetSeconds];
	};
	[self.view addSubview:_lyricsView];

	_artView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_artView.contentMode = UIViewContentModeScaleAspectFill;
	_artView.clipsToBounds = YES;
	_artView.layer.cornerRadius = 16.0f;
	_artView.layer.borderWidth = 0.5f;
	_artView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.15f].CGColor;
	[_artContainer addSubview:_artView];

	_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_titleLabel.font = [UIFont boldSystemFontOfSize:20.0f];
	_titleLabel.textColor = [MLTheme onSurface];
	_titleLabel.textAlignment = NSTextAlignmentLeft;
	_titleLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_titleLabel];

	_artistButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_artistButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	_artistButton.titleLabel.font = [UIFont systemFontOfSize:15.0f];
	_artistButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[_artistButton setTitleColor:[MLTheme onSurfaceVariant] forState:UIControlStateNormal];
	[_artistButton setTitleColor:[MLTheme primary] forState:UIControlStateHighlighted];
	[_artistButton addTarget:self action:@selector(artistTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_artistButton];

	_shareButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_shareButton.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
	_shareButton.layer.cornerRadius = 19.0f;
	[_shareButton setImage:[MLIcon icon:@"share" size:20.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_shareButton addTarget:self action:@selector(shareTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_shareButton];

	_likeButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_likeButton.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
	_likeButton.layer.cornerRadius = 19.0f;
	[_likeButton setImage:[MLIcon icon:@"favorite_border" size:20.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_likeButton addTarget:self action:@selector(likeTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_likeButton];

	_statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_statusLabel.font = [MLTheme fontLabelMedium];
	_statusLabel.textColor = [MLTheme primaryContainer];
	_statusLabel.textAlignment = NSTextAlignmentLeft;
	_statusLabel.backgroundColor = [UIColor clearColor];
	_statusLabel.adjustsFontSizeToFitWidth = YES;
	_statusLabel.minimumFontSize = 9.0f;
	[self.view addSubview:_statusLabel];

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

	_shuffleButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[_shuffleButton setImage:[MLIcon icon:@"shuffle" size:22.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
	[_shuffleButton addTarget:self action:@selector(shuffleTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_shuffleButton];

	_prevButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_prevButton.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
	[_prevButton setImage:[MLIcon icon:@"skip_previous" size:28.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_prevButton addTarget:self action:@selector(prevTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_prevButton];

	_playButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_playButton.backgroundColor = [MLTheme primary];
	_playButton.layer.shadowColor = [MLTheme primary].CGColor;
	_playButton.layer.shadowOpacity = 0.40f;
	_playButton.layer.shadowOffset = CGSizeMake(0, 4.0f);
	_playButton.layer.shadowRadius = 10.0f;
	[_playButton setImage:[MLIcon icon:@"play_arrow" size:32.0f color:[UIColor whiteColor]] forState:UIControlStateNormal];
	[_playButton addTarget:self action:@selector(playTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_playButton];

	_nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_nextButton.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
	[_nextButton setImage:[MLIcon icon:@"skip_next" size:28.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_nextButton addTarget:self action:@selector(nextTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_nextButton];

	_repeatButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[_repeatButton setImage:[MLIcon icon:@"repeat" size:22.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
	[_repeatButton addTarget:self action:@selector(repeatTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_repeatButton];

	_queueBar = [[UIControl alloc] initWithFrame:CGRectZero];
	_queueBar.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.09f];
	_queueBar.layer.cornerRadius = 20.0f;
	_queueBar.layer.borderWidth = 0.5f;
	_queueBar.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.14f].CGColor;
	[_queueBar addTarget:self action:@selector(queueTap:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_queueBar];

	_queueIconView = [[UIImageView alloc] initWithImage:[MLIcon icon:@"queue_music" size:20.0f color:[MLTheme primary]]];
	[_queueBar addSubview:_queueIconView];

	_queueTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_queueTitleLabel.font = [MLTheme fontTitleSmall];
	_queueTitleLabel.textColor = [MLTheme onSurface];
	_queueTitleLabel.backgroundColor = [UIColor clearColor];
	[_queueBar addSubview:_queueTitleLabel];

	_queueChevronView = [[UIImageView alloc] initWithImage:[MLIcon icon:@"chevron_right" size:20.0f color:[MLTheme onSurfaceVariant]]];
	[_queueBar addSubview:_queueChevronView];

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
	BOOL compact = (H <= 480.0f);
	CGFloat topInset = [MLTheme safeAreaTopInsetForView:self.view];
	CGFloat bottomInset = [MLTheme safeAreaBottomInsetForView:self.view];

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_bgGradient.frame = b;
	[CATransaction commit];

	_dragHandle.frame = CGRectMake((W - 36.0f) / 2.0f, topInset + 6.0f, 36.0f, 4.0f);

	CGFloat topY = topInset + (compact ? 6.0f : 12.0f);
	_closeButton.frame = CGRectMake(12.0f, topY, 38.0f, 38.0f);
	_lyricsButton.frame = CGRectMake(W - 90.0f, topY, 38.0f, 38.0f);
	_moreButton.frame = CGRectMake(W - 50.0f, topY, 38.0f, 38.0f);
	_headerLabel.frame = CGRectMake(52.0f, topY + 9.0f, W - 146.0f, 20.0f);

	CGFloat artSize;
	if (compact) {
		artSize = 138.0f;
	} else if (H >= 812.0f) {
		artSize = MIN(W - 48.0f, 320.0f);
	} else if (H >= 667.0f) {
		artSize = MIN(W - 48.0f, 250.0f);
	} else {
		artSize = MIN(W - 60.0f, 200.0f);
	}

	CGFloat artY = topY + (compact ? 36.0f : 42.0f);
	_artContainer.frame = CGRectMake((W - artSize) / 2.0f, artY, artSize, artSize);
	_artView.frame = _artContainer.bounds;
	_lyricsView.frame = _artContainer.frame;

	CGFloat metaY = artY + artSize + (compact ? 8.0f : 16.0f);
	CGFloat actionButtonsW = 84.0f;
	CGFloat textW = W - 48.0f - actionButtonsW - 8.0f;
	_titleLabel.frame = CGRectMake(24.0f, metaY, textW, 26.0f);
	_artistButton.frame = CGRectMake(24.0f, metaY + 24.0f, textW, 20.0f);

	_shareButton.frame = CGRectMake(W - 24.0f - 82.0f, metaY + 3.0f, 38.0f, 38.0f);
	_likeButton.frame = CGRectMake(W - 24.0f - 38.0f, metaY + 3.0f, 38.0f, 38.0f);

	CGFloat sliderY = metaY + (compact ? 44.0f : 52.0f);
	_seekBar.frame = CGRectMake(22.0f, sliderY, W - 44.0f, 24.0f);

	CGFloat timeY = sliderY + 22.0f;
	_elapsedLabel.frame = CGRectMake(24.0f, timeY, 56.0f, 14.0f);
	_durationLabel.frame = CGRectMake(W - 80.0f, timeY, 56.0f, 14.0f);

	CGFloat statusX = 84.0f;
	CGFloat statusW = MAX(40.0f, W - statusX * 2.0f);
	_statusLabel.frame = CGRectMake(statusX, timeY, statusW, 14.0f);
	_statusLabel.textAlignment = NSTextAlignmentCenter;

	CGFloat queueH = compact ? 38.0f : 44.0f;
	CGFloat queueY = H - queueH - bottomInset - (compact ? 8.0f : 16.0f);
	_queueBar.frame = CGRectMake(20.0f, queueY, W - 40.0f, queueH);
	_queueBar.layer.cornerRadius = queueH / 2.0f;
	_queueIconView.frame = CGRectMake(14.0f, (queueH - 20.0f) / 2.0f, 20.0f, 20.0f);
	_queueChevronView.frame = CGRectMake(_queueBar.bounds.size.width - 30.0f, (queueH - 20.0f) / 2.0f, 20.0f, 20.0f);
	_queueTitleLabel.frame = CGRectMake(42.0f, 0.0f, _queueBar.bounds.size.width - 76.0f, queueH);

	CGFloat availTop = timeY + 16.0f;
	CGFloat availBot = queueY - 12.0f;
	CGFloat controlsCenterY = (availTop + availBot) / 2.0f;

	CGFloat playSide = compact ? 54.0f : (H >= 812.0f ? 66.0f : 60.0f);
	_playButton.frame = CGRectMake((W - playSide) / 2.0f, controlsCenterY - playSide / 2.0f, playSide, playSide);
	BOOL isPlaying = [MLPlaybackManager sharedManager].playing;
	_playButton.layer.cornerRadius = isPlaying ? 20.0f : (playSide / 2.0f);

	CGFloat sideSize = compact ? 42.0f : 46.0f;
	CGFloat btnSpacing = compact ? 56.0f : 66.0f;
	CGFloat midX = W / 2.0f;
	_prevButton.frame = CGRectMake(midX - btnSpacing - sideSize / 2.0f, controlsCenterY - sideSize / 2.0f, sideSize, sideSize);
	_prevButton.layer.cornerRadius = sideSize / 2.0f;
	_nextButton.frame = CGRectMake(midX + btnSpacing - sideSize / 2.0f, controlsCenterY - sideSize / 2.0f, sideSize, sideSize);
	_nextButton.layer.cornerRadius = sideSize / 2.0f;

	CGFloat outerSpacing = compact ? 112.0f : 126.0f;
	_shuffleButton.frame = CGRectMake(midX - outerSpacing - 20.0f, controlsCenterY - 20.0f, 40.0f, 40.0f);
	_repeatButton.frame = CGRectMake(midX + outerSpacing - 20.0f, controlsCenterY - 20.0f, 40.0f, 40.0f);
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
	                                         selector:@selector(stateChanged:)
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
}

- (void)themeChanged:(NSNotification *)note
{
	self.view.backgroundColor = [MLTheme background];
	_seekBar.minimumTrackTintColor = [MLTheme primary];
	_seekBar.thumbTintColor = [MLTheme primary];
	_playButton.backgroundColor = [MLTheme primary];
	_playButton.layer.shadowColor = [MLTheme primary].CGColor;
	_queueIconView.image = [MLIcon icon:@"queue_music" size:20.0f color:[MLTheme primary]];
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
	UIColor *activeColor = _showingLyrics ? [MLTheme primary] : [MLTheme onSurfaceVariant];
	[_lyricsButton setImage:[MLIcon icon:@"lyrics" size:22.0f color:activeColor] forState:UIControlStateNormal];

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
	_headerLabel.text = MLLocalizedString(@"now_playing", nil);
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self reload];
}

- (void)stateChanged:(NSNotification *)n
{
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
	if (_delegate && [_delegate respondsToSelector:@selector(playerViewControllerDidClose:)])
		[_delegate playerViewControllerDidClose:self];
}

- (void)moreTap:(UIButton *)sender
{
	MLYTItem *item = [MLPlaybackManager sharedManager].currentItem;
	if (item) {
		[MLNavigator presentSongMenuForItem:item fromViewController:self];
	}
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
	_statusLabel.text = MLLocalizedString(@"copied_title", nil);
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
	UIColor *color = _liked ? [MLTheme primary] : [MLTheme onSurface];
	[_likeButton setImage:[MLIcon icon:icon size:20.0f color:color] forState:UIControlStateNormal];
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

	_liked = [[MLLibraryManager sharedManager] isSongLiked:item.videoId];
	NSString *likeIcon = _liked ? @"favorite" : @"favorite_border";
	UIColor *likeColor = _liked ? [MLTheme primary] : [MLTheme onSurface];
	[_likeButton setImage:[MLIcon icon:likeIcon size:20.0f color:likeColor] forState:UIControlStateNormal];

	_titleLabel.text = item.title;
	NSString *artistText = item.artists.count ? [item.artists componentsJoinedByString:@", "] : (item.subtitle ?: @"");
	[_artistButton setTitle:artistText forState:UIControlStateNormal];

	if (item.thumbnailUrl && ![item.thumbnailUrl isEqualToString:_lastThumbUrl]) {
		_lastThumbUrl = [item.thumbnailUrl copy];
		__weak MLPlayerViewController *wself = self;
		[MLImageCache loadImageAtURLString:item.thumbnailUrl
		                          intoView:_artView
		                           fitSize:_artView.frame.size
		                      cornerRadius:16.0f
		                       placeholder:[MLImageCache placeholderImageWithSize:_artView.frame.size]
		                        completion:^(UIImage *image) {
			MLPlayerViewController *s = wself;
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

	NSString *icon = pm.playing ? @"pause" : @"play_arrow";
	[_playButton setImage:[MLIcon icon:icon size:32.0f color:[UIColor whiteColor]] forState:UIControlStateNormal];

	BOOL compact = (self.view.bounds.size.height <= 480.0f);
	CGFloat playSide = _playButton.bounds.size.width ?: (compact ? 54.0f : 62.0f);
	[UIView animateWithDuration:0.18f animations:^{
		_playButton.layer.cornerRadius = pm.playing ? 18.0f : (playSide / 2.0f);
		_artView.transform = pm.playing ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.93f, 0.93f);
	}];

	BOOL shuffleOn = pm.shuffle;
	[_shuffleButton setImage:[MLIcon icon:@"shuffle" size:22.0f color:shuffleOn ? [MLTheme primary] : [MLTheme onSurfaceVariant]] forState:UIControlStateNormal];

	NSString *repeatIcon = (pm.repeatMode == MLRepeatModeOne) ? @"repeat_one" : @"repeat";
	UIColor *repeatColor = (pm.repeatMode == MLRepeatModeOff) ? [MLTheme onSurfaceVariant] : [MLTheme primary];
	[_repeatButton setImage:[MLIcon icon:repeatIcon size:22.0f color:repeatColor] forState:UIControlStateNormal];

	if (pm.statusError) {
		_statusLabel.textColor = [MLTheme error];
		_statusLabel.text = pm.statusError;
	} else if (pm.buffering) {
		_statusLabel.textColor = [MLTheme onSurfaceVariant];
		_statusLabel.text = MLLocalizedString(@"loading_audio", nil);
	} else {
		_statusLabel.text = @"";
	}

	NSUInteger nextIdx = pm.currentIndex + 1;
	if (nextIdx < pm.queue.count) {
		MLYTItem *nextItem = pm.queue[nextIdx];
		_queueTitleLabel.text = [NSString stringWithFormat:@"%@: %@", MLLocalizedString(@"up_next", nil), nextItem.title ?: @""];
	} else {
		_queueTitleLabel.text = MLLocalizedString(@"up_next", nil);
	}

	if (!_seeking) {
		CGFloat dur = pm.duration ?: item.duration;
		_seekBar.value = dur > 0 ? MIN(1.0f, pm.currentTime / dur) : 0;
		if (dur > 0) {
			_elapsedLabel.text = MLFormatDuration(pm.currentTime);
			_durationLabel.text = MLFormatDuration(dur);
		} else {
			_elapsedLabel.text = @"0:00";
			_durationLabel.text = @"0:00";
		}
	}

	if (_lyricsView) {
		NSString *artName = item.artists.count ? item.artists[0] : (item.subtitle ?: @"");
		CGFloat dur = pm.duration ?: item.duration;
		[_lyricsView loadLyricsForTitle:item.title artist:artName duration:dur videoId:item.videoId];
		[_lyricsView updateCurrentPlaybackTime:pm.currentTime];
	}
}

@end
