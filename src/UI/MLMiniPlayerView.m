#import "MLMiniPlayerView.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLImageCache.h"
#import "MLPlaybackManager.h"
#import <QuartzCore/QuartzCore.h>

@interface MLMiniPlayerView ()
{
	UIView *_cardView;
	CAGradientLayer *_gradientLayer;
	UIImageView *_thumb;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UIButton *_playButton;
	CAShapeLayer *_progressTrackRing;
	CAShapeLayer *_progressFillRing;
	UIButton *_nextButton;
	UIView *_progressTrack;
	UIView *_progressFill;
	NSString *_lastThumbUrl;
}
@end

@implementation MLMiniPlayerView

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.layer.shadowColor = [UIColor blackColor].CGColor;
		self.layer.shadowOpacity = 0.42f;
		self.layer.shadowOffset = CGSizeMake(0, 4.0f);
		self.layer.shadowRadius = 8.0f;

		_cardView = [[UIView alloc] initWithFrame:self.bounds];
		_cardView.backgroundColor = [MLTheme surfaceContainerHigh];
		_cardView.layer.cornerRadius = 22.0f;
		_cardView.layer.borderWidth = 1.0f;
		_cardView.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.28f].CGColor;
		_cardView.clipsToBounds = YES;
		[self addSubview:_cardView];

		_gradientLayer = [CAGradientLayer layer];
		_gradientLayer.startPoint = CGPointMake(0.0f, 0.5f);
		_gradientLayer.endPoint = CGPointMake(1.0f, 0.5f);
		_gradientLayer.colors = @[
			(id)[MLTheme surfaceContainerHigh].CGColor,
			(id)[MLTheme surfaceContainer].CGColor
		];
		[_cardView.layer insertSublayer:_gradientLayer atIndex:0];

		_thumb = [[UIImageView alloc] initWithFrame:CGRectMake(10.0f, 7.0f, 44.0f, 44.0f)];
		_thumb.contentMode = UIViewContentModeScaleAspectFill;
		_thumb.clipsToBounds = YES;
		_thumb.layer.cornerRadius = 10.0f;
		[_cardView addSubview:_thumb];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = [MLTheme fontTitleSmall];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[_cardView addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.font = [MLTheme fontBodySmall];
		_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		[_cardView addSubview:_subtitleLabel];

		_playButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[_playButton setImage:[MLIcon icon:@"play_arrow" size:24.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
		[_playButton addTarget:self action:@selector(playTap:) forControlEvents:UIControlEventTouchUpInside];
		[_cardView addSubview:_playButton];

		UIBezierPath *ringPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(20.0f, 20.0f)
		                                                        radius:17.5f
		                                                    startAngle:-(CGFloat)M_PI_2
		                                                      endAngle:(CGFloat)(M_PI * 1.5)
		                                                     clockwise:YES];
		_progressTrackRing = [CAShapeLayer layer];
		_progressTrackRing.path = ringPath.CGPath;
		_progressTrackRing.fillColor = [UIColor clearColor].CGColor;
		_progressTrackRing.strokeColor = [[MLTheme outline] colorWithAlphaComponent:0.25f].CGColor;
		_progressTrackRing.lineWidth = 2.5f;
		[_playButton.layer addSublayer:_progressTrackRing];

		_progressFillRing = [CAShapeLayer layer];
		_progressFillRing.path = ringPath.CGPath;
		_progressFillRing.fillColor = [UIColor clearColor].CGColor;
		_progressFillRing.strokeColor = [MLTheme primary].CGColor;
		_progressFillRing.lineWidth = 2.5f;
		_progressFillRing.strokeStart = 0.0f;
		_progressFillRing.strokeEnd = 0.0f;
		_progressFillRing.lineCap = kCALineCapRound;
		[_playButton.layer addSublayer:_progressFillRing];

		_nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[_nextButton setImage:[MLIcon icon:@"skip_next" size:24.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
		[_nextButton addTarget:self action:@selector(nextTap:) forControlEvents:UIControlEventTouchUpInside];
		[_cardView addSubview:_nextButton];

		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewTap:)];
		[_cardView addGestureRecognizer:tap];

		UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
		[_cardView addGestureRecognizer:pan];

		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(themeChanged:)
		                                             name:MLThemeDidChangeNotification
		                                           object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)themeChanged:(NSNotification *)note
{
	_cardView.backgroundColor = [MLTheme surfaceContainerHigh];
	_cardView.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.28f].CGColor;
	_titleLabel.textColor = [MLTheme onSurface];
	_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
	_progressFillRing.strokeColor = [MLTheme primary].CGColor;
	_progressTrackRing.strokeColor = [[MLTheme outline] colorWithAlphaComponent:0.25f].CGColor;
	NSString *icon = [MLPlaybackManager sharedManager].playing ? @"pause" : @"play_arrow";
	[_playButton setImage:[MLIcon icon:icon size:22.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_nextButton setImage:[MLIcon icon:@"skip_next" size:24.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.bounds;
	_cardView.frame = b;
	_cardView.layer.cornerRadius = MIN(24.0f, b.size.height / 2.0f);

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_gradientLayer.frame = b;
	[CATransaction commit];

	_thumb.frame = CGRectMake(10.0f, (b.size.height - 42.0f) / 2.0f, 42.0f, 42.0f);
	_nextButton.frame = CGRectMake(b.size.width - 44.0f, (b.size.height - 40.0f) / 2.0f, 38.0f, 40.0f);
	_playButton.frame = CGRectMake(_nextButton.frame.origin.x - 42.0f, (b.size.height - 40.0f) / 2.0f, 40.0f, 40.0f);

	CGFloat textX = 60.0f;
	CGFloat textW = MAX(40.0f, _playButton.frame.origin.x - textX - 6.0f);
	_titleLabel.frame = CGRectMake(textX, (b.size.height / 2.0f) - 17.0f, textW, 18.0f);
	_subtitleLabel.frame = CGRectMake(textX, (b.size.height / 2.0f) + 1.0f, textW, 15.0f);
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

- (void)viewTap:(UITapGestureRecognizer *)g
{
	if (_delegate && [_delegate respondsToSelector:@selector(miniPlayerTapped:)])
		[_delegate miniPlayerTapped:self];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan
{
	CGPoint trans = [pan translationInView:self];
	if (pan.state == UIGestureRecognizerStateChanged) {
		_cardView.transform = CGAffineTransformMakeTranslation(trans.x * 0.65f, 0.0f);
	} else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		CGPoint vel = [pan velocityInView:self];
		if (trans.x < -55.0f || vel.x < -500.0f) {
			[[MLPlaybackManager sharedManager] next];
		} else if (trans.x > 55.0f || vel.x > 500.0f) {
			[[MLPlaybackManager sharedManager] previous];
		} else if (trans.y < -40.0f || vel.y < -450.0f) {
			if (_delegate && [_delegate respondsToSelector:@selector(miniPlayerTapped:)])
				[_delegate miniPlayerTapped:self];
		}
		[UIView animateWithDuration:0.22f animations:^{
			_cardView.transform = CGAffineTransformIdentity;
		}];
	}
}

- (void)reload
{
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	MLYTItem *item = pm.currentItem;
	if (!item)
		return;
	_titleLabel.text = item.title;
	_subtitleLabel.text = item.artists.count ? [item.artists componentsJoinedByString:@", "] : item.subtitle;
	NSString *icon = pm.playing ? @"pause" : @"play_arrow";
	[_playButton setImage:[MLIcon icon:icon size:22.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];

	if (item.thumbnailUrl && ![item.thumbnailUrl isEqualToString:_lastThumbUrl]) {
		_lastThumbUrl = [item.thumbnailUrl copy];
		__weak MLMiniPlayerView *wself = self;
		[MLImageCache loadImageAtURLString:item.thumbnailUrl
		                          intoView:_thumb
		                           fitSize:_thumb.frame.size
		                      cornerRadius:10.0f
		                       placeholder:[MLImageCache placeholderImageWithSize:_thumb.frame.size]
		                        completion:^(UIImage *image) {
			MLMiniPlayerView *s = wself;
			if (!s || !image)
				return;
			UIColor *dom = [MLTheme dominantColorForImage:image];
			[MLTheme setDynamicAccentColor:dom];
			UIColor *top = [MLTheme blendColor:dom overBackground:[MLTheme surfaceContainer] alpha:0.35f];
			s->_gradientLayer.colors = @[
				(id)top.CGColor,
				(id)[MLTheme surfaceContainerHigh].CGColor
			];
		}];
	}

	CGFloat dur = pm.duration ?: item.duration;
	CGFloat prog = (dur > 0) ? MIN(1.0f, MAX(0.0f, pm.currentTime / dur)) : 0.0f;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_progressFillRing.strokeEnd = prog;
	[CATransaction commit];
}

@end
