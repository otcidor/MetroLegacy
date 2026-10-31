#import "MLEqualizerViewController.h"
#import "MLEqualizerManager.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLLocalization.h"

@interface MLEqualizerViewController () <UIScrollViewDelegate>

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISwitch *masterSwitch;

@property (nonatomic, strong) UIScrollView *presetsScrollView;
@property (nonatomic, strong) NSMutableArray *presetButtons;

@property (nonatomic, strong) UIView *slidersCard;
@property (nonatomic, strong) NSMutableArray *bandSliders;
@property (nonatomic, strong) NSMutableArray *bandValueLabels;
@property (nonatomic, strong) NSMutableArray *bandFreqLabels;

@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, assign) BOOL previousNavBarHidden;

@end

@implementation MLEqualizerViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.view.backgroundColor = [MLTheme background];

	if (self.navigationController) {
		self.navigationController.navigationBarHidden = YES;
	}

	[self buildHeader];
	[self buildPresetSelector];
	[self buildSlidersCard];
	[self buildBottomControls];

	[self updateUIForEnabledStateAnimated:NO];
	[self reloadSliders];
	[self reloadPresetChips];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(handleThemeChanged:)
	                                             name:MLThemeDidChangeNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(handleEqualizerChanged:)
	                                             name:MLEqualizerDidChangeNotification
	                                           object:nil];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	if (self.navigationController) {
		_previousNavBarHidden = self.navigationController.navigationBarHidden;
		[self.navigationController setNavigationBarHidden:YES animated:animated];
	}
	[self reloadSliders];
	[self reloadPresetChips];
	[self updateUIForEnabledStateAnimated:NO];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	if (self.navigationController) {
		[self.navigationController setNavigationBarHidden:_previousNavBarHidden animated:animated];
	}
}

// MARK: - View Construction

- (void)buildHeader
{
	_headerView = [[UIView alloc] init];
	_headerView.backgroundColor = [MLTheme surfaceContainerHigh];
	[self.view addSubview:_headerView];

	_backButton = [UIButton buttonWithType:UIButtonTypeCustom];
	BOOL isModalRoot = (self.navigationController == nil || self.navigationController.viewControllers.firstObject == self);
	NSString *iconName = isModalRoot ? @"close" : @"arrow_back";
	[_backButton setImage:[MLIcon icon:iconName size:24.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_backButton addTarget:self action:@selector(backTapped:) forControlEvents:UIControlEventTouchUpInside];
	[_headerView addSubview:_backButton];

	_titleLabel = [[UILabel alloc] init];
	_titleLabel.backgroundColor = [UIColor clearColor];
	_titleLabel.text = MLLocalizedString(@"equalizer_title", nil);
	_titleLabel.font = [MLTheme fontTitleMedium];
	_titleLabel.textColor = [MLTheme onSurface];
	[_headerView addSubview:_titleLabel];

	_masterSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
	[_masterSwitch sizeToFit];
	if ([_masterSwitch respondsToSelector:@selector(setOnTintColor:)]) {
		_masterSwitch.onTintColor = [MLTheme primary];
	}
	_masterSwitch.on = [MLEqualizerManager sharedManager].enabled;
	[_masterSwitch addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
	[_headerView addSubview:_masterSwitch];
}

- (void)buildPresetSelector
{
	_presetsScrollView = [[UIScrollView alloc] init];
	_presetsScrollView.showsHorizontalScrollIndicator = NO;
	_presetsScrollView.bounces = YES;
	[self.view addSubview:_presetsScrollView];

	_presetButtons = [NSMutableArray array];
	NSArray *presets = [MLEqualizerManager sharedManager].presets;
	for (NSUInteger i = 0; i < presets.count; i++) {
		MLEQPreset *p = presets[i];
		UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
		btn.tag = i;
		btn.layer.cornerRadius = 15.0f;
		btn.layer.masksToBounds = YES;
		btn.titleLabel.font = [MLTheme fontLabelMedium];
		btn.contentEdgeInsets = UIEdgeInsetsMake(6.0f, 14.0f, 6.0f, 14.0f);
		[btn setTitle:MLLocalizedString(p.nameKey, nil) forState:UIControlStateNormal];
		[btn addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
		[_presetsScrollView addSubview:btn];
		[_presetButtons addObject:btn];
	}
}

- (void)buildSlidersCard
{
	_slidersCard = [[UIView alloc] init];
	_slidersCard.backgroundColor = [MLTheme surfaceContainer];
	_slidersCard.layer.cornerRadius = MLRadiusCard;
	_slidersCard.layer.borderWidth = 1.0f;
	_slidersCard.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.18f].CGColor;
	_slidersCard.layer.masksToBounds = YES;
	[self.view addSubview:_slidersCard];

	_bandSliders = [NSMutableArray array];
	_bandValueLabels = [NSMutableArray array];
	_bandFreqLabels = [NSMutableArray array];

	MLEqualizerManager *mgr = [MLEqualizerManager sharedManager];
	NSInteger numBands = [mgr numberOfBands];

	for (NSInteger i = 0; i < numBands; i++) {
		// dB Value Label
		UILabel *valLabel = [[UILabel alloc] init];
		valLabel.backgroundColor = [UIColor clearColor];
		valLabel.font = [UIFont systemFontOfSize:9.0f];
		valLabel.textColor = [MLTheme onSurfaceVariant];
		valLabel.textAlignment = NSTextAlignmentCenter;
		valLabel.adjustsFontSizeToFitWidth = YES;
		[_slidersCard addSubview:valLabel];
		[_bandValueLabels addObject:valLabel];

		// Slider
		UISlider *slider = [[UISlider alloc] init];
		slider.tag = i;
		slider.minimumValue = -12.0f;
		slider.maximumValue = 12.0f;
		slider.value = [mgr gainForBand:i];
		slider.minimumTrackTintColor = [MLTheme primary];
		slider.maximumTrackTintColor = [[MLTheme outline] colorWithAlphaComponent:0.25f];
		[slider setThumbImage:[MLTheme circleThumbWithColor:[MLTheme primary] diameter:14.0f] forState:UIControlStateNormal];
		[slider setThumbImage:[MLTheme circleThumbWithColor:[MLTheme primary] diameter:18.0f] forState:UIControlStateHighlighted];
		slider.transform = CGAffineTransformMakeRotation((CGFloat)(-M_PI_2));
		[slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
		[slider addTarget:self action:@selector(sliderTouchEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
		[_slidersCard addSubview:slider];
		[_bandSliders addObject:slider];

		// Frequency Label
		UILabel *freqLabel = [[UILabel alloc] init];
		freqLabel.backgroundColor = [UIColor clearColor];
		freqLabel.font = [UIFont boldSystemFontOfSize:10.0f];
		freqLabel.textColor = [MLTheme onSurface];
		freqLabel.textAlignment = NSTextAlignmentCenter;
		freqLabel.adjustsFontSizeToFitWidth = YES;
		freqLabel.text = [mgr shortFrequencyStringForBand:i];
		[_slidersCard addSubview:freqLabel];
		[_bandFreqLabels addObject:freqLabel];
	}
}

- (void)buildBottomControls
{
	_resetButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_resetButton.layer.cornerRadius = 18.0f;
	_resetButton.layer.masksToBounds = YES;
	_resetButton.layer.borderWidth = 1.0f;
	_resetButton.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.3f].CGColor;
	_resetButton.backgroundColor = [MLTheme surfaceContainerHigh];
	_resetButton.titleLabel.font = [MLTheme fontLabelMedium];
	[_resetButton setTitleColor:[MLTheme onSurface] forState:UIControlStateNormal];
	[_resetButton setTitle:[NSString stringWithFormat:@"  %@", MLLocalizedString(@"equalizer_reset", nil)] forState:UIControlStateNormal];
	[_resetButton setImage:[MLIcon icon:@"cached" size:16.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	_resetButton.contentEdgeInsets = UIEdgeInsetsMake(8.0f, 20.0f, 8.0f, 20.0f);
	[_resetButton addTarget:self action:@selector(resetTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_resetButton];

	_hintLabel = [[UILabel alloc] init];
	_hintLabel.backgroundColor = [UIColor clearColor];
	_hintLabel.font = [MLTheme fontBodySmall];
	_hintLabel.textColor = [MLTheme onSurfaceVariant];
	_hintLabel.textAlignment = NSTextAlignmentCenter;
	_hintLabel.text = MLLocalizedString(@"equalizer_hint", nil);
	_hintLabel.numberOfLines = 0;
	[self.view addSubview:_hintLabel];
}

// MARK: - Layout

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];

	CGFloat topInset = [MLTheme safeAreaTopInsetForView:self.view];
	CGFloat bottomInset = [MLTheme safeAreaBottomInsetForView:self.view];
	CGFloat width = self.view.bounds.size.width;
	CGFloat height = self.view.bounds.size.height;

	// Header
	CGFloat headerHeight = topInset + 54.0f;
	_headerView.frame = CGRectMake(0, 0, width, headerHeight);

	_backButton.frame = CGRectMake(12.0f, topInset + 7.0f, 40.0f, 40.0f);
	CGSize swSize = _masterSwitch.bounds.size;
	if (swSize.width < 1.0f || swSize.height < 1.0f) {
		[_masterSwitch sizeToFit];
		swSize = _masterSwitch.bounds.size;
	}
	if (swSize.width < 1.0f) swSize = CGSizeMake(51.0f, 31.0f);
	_masterSwitch.frame = CGRectMake(width - swSize.width - 16.0f,
	                                 topInset + (54.0f - swSize.height) / 2.0f,
	                                 swSize.width,
	                                 swSize.height);

	CGFloat titleLeft = CGRectGetMaxX(_backButton.frame) + 8.0f;
	CGFloat titleRight = _masterSwitch.frame.origin.x - 8.0f;
	_titleLabel.frame = CGRectMake(titleLeft, topInset + 12.0f, titleRight - titleLeft, 30.0f);

	// Presets Bar
	CGFloat presetsY = headerHeight + 12.0f;
	_presetsScrollView.frame = CGRectMake(0, presetsY, width, 40.0f);

	CGFloat chipX = 16.0f;
	for (UIButton *btn in _presetButtons) {
		CGSize sz = [btn sizeThatFits:CGSizeMake(CGFLOAT_MAX, 32.0f)];
		sz.width = MAX(sz.width + 16.0f, 54.0f);
		btn.frame = CGRectMake(chipX, 4.0f, sz.width, 32.0f);
		chipX += sz.width + 8.0f;
	}
	_presetsScrollView.contentSize = CGSizeMake(chipX + 8.0f, 40.0f);

	// Bottom Area sizing
	CGFloat resetH = 36.0f;
	CGFloat hintH = 22.0f;
	CGFloat bottomAreaH = resetH + hintH + 24.0f + bottomInset;

	CGFloat cardY = CGRectGetMaxY(_presetsScrollView.frame) + 12.0f;
	CGFloat cardH = height - cardY - bottomAreaH;
	if (cardH < 180.0f) {
		cardH = 180.0f;
	}
	_slidersCard.frame = CGRectMake(16.0f, cardY, width - 32.0f, cardH);

	// Layout sliders inside card
	NSInteger numBands = _bandSliders.count;
	CGFloat cardW = _slidersCard.bounds.size.width;
	CGFloat colW = cardW / (CGFloat)numBands;
	CGFloat sliderTravel = cardH - 84.0f;
	if (sliderTravel < 100.0f) sliderTravel = 100.0f;
	CGFloat centerY = cardH / 2.0f - 2.0f;

	for (NSInteger i = 0; i < numBands; i++) {
		CGFloat colCenterX = colW * (i + 0.5f);

		UILabel *valLabel = _bandValueLabels[i];
		valLabel.frame = CGRectMake(colW * i, 12.0f, colW, 20.0f);

		UISlider *slider = _bandSliders[i];
		slider.bounds = CGRectMake(0, 0, sliderTravel, 32.0f);
		slider.center = CGPointMake(colCenterX, centerY);

		UILabel *freqLabel = _bandFreqLabels[i];
		freqLabel.frame = CGRectMake(colW * i, cardH - 34.0f, colW, 22.0f);
	}

	// Reset button
	CGFloat resetY = CGRectGetMaxY(_slidersCard.frame) + 12.0f;
	CGSize rSize = [_resetButton sizeThatFits:CGSizeMake(width - 40.0f, resetH)];
	_resetButton.frame = CGRectMake((width - (rSize.width + 24.0f)) / 2.0f, resetY, rSize.width + 24.0f, resetH);

	// Hint
	_hintLabel.frame = CGRectMake(20.0f, CGRectGetMaxY(_resetButton.frame) + 8.0f, width - 40.0f, hintH);
}

// MARK: - State & Updates

- (void)updateUIForEnabledStateAnimated:(BOOL)animated
{
	BOOL enabled = [MLEqualizerManager sharedManager].enabled;
	CGFloat alpha = enabled ? 1.0f : 0.45f;

	void (^apply)(void) = ^{
		self->_presetsScrollView.alpha = alpha;
		self->_slidersCard.alpha = alpha;
		self->_resetButton.alpha = alpha;
		self->_presetsScrollView.userInteractionEnabled = enabled;
		self->_slidersCard.userInteractionEnabled = enabled;
		self->_resetButton.userInteractionEnabled = enabled;
	};

	if (animated) {
		[UIView animateWithDuration:0.25f animations:apply];
	} else {
		apply();
	}
}

- (void)reloadSlidersAnimated:(BOOL)animated
{
	MLEqualizerManager *mgr = [MLEqualizerManager sharedManager];
	NSInteger numBands = [mgr numberOfBands];
	for (NSInteger i = 0; i < numBands; i++) {
		float gain = [mgr gainForBand:i];
		if (i < (NSInteger)_bandSliders.count) {
			UISlider *sl = _bandSliders[i];
			[sl setValue:gain animated:animated];
		}
		if (i < (NSInteger)_bandValueLabels.count) {
			UILabel *lbl = _bandValueLabels[i];
			lbl.text = [self formattedGain:gain];
			if (fabsf(gain) > 0.05f) {
				lbl.textColor = [MLTheme primary];
			} else {
				lbl.textColor = [MLTheme onSurfaceVariant];
			}
		}
	}
}

- (void)reloadSliders
{
	[self reloadSlidersAnimated:NO];
}

- (void)reloadPresetChips
{
	MLEqualizerManager *mgr = [MLEqualizerManager sharedManager];
	NSString *currentId = mgr.currentPresetId;
	NSArray *presets = mgr.presets;

	for (NSUInteger i = 0; i < _presetButtons.count; i++) {
		UIButton *btn = _presetButtons[i];
		MLEQPreset *p = (i < presets.count) ? presets[i] : nil;
		BOOL isSelected = [p.presetId isEqualToString:currentId];

		if (isSelected) {
			btn.backgroundColor = [MLTheme primary];
			[btn setTitleColor:[MLTheme onPrimary] forState:UIControlStateNormal];
			btn.layer.borderWidth = 0.0f;
		} else {
			btn.backgroundColor = [MLTheme surfaceContainer];
			[btn setTitleColor:[MLTheme onSurface] forState:UIControlStateNormal];
			btn.layer.borderWidth = 1.0f;
			btn.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.25f].CGColor;
		}
	}
}

- (NSString *)formattedGain:(float)gain
{
	if (fabsf(gain) < 0.05f) {
		return @"0";
	} else if (gain > 0.0f) {
		return [NSString stringWithFormat:@"+%.1f", gain];
	} else {
		return [NSString stringWithFormat:@"%.1f", gain];
	}
}

// MARK: - Actions

- (void)backTapped:(UIButton *)sender
{
	if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
		[self.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissViewControllerAnimated:YES completion:nil];
	}
}

- (void)switchToggled:(UISwitch *)sender
{
	[MLTheme triggerImpactHaptic];
	[MLEqualizerManager sharedManager].enabled = sender.on;
	[self updateUIForEnabledStateAnimated:YES];
}

- (void)presetTapped:(UIButton *)sender
{
	[MLTheme triggerImpactHaptic];
	NSArray *presets = [MLEqualizerManager sharedManager].presets;
	if (sender.tag < presets.count) {
		MLEQPreset *p = presets[sender.tag];
		[[MLEqualizerManager sharedManager] applyPresetWithId:p.presetId];
		[self reloadSlidersAnimated:YES];
		[self reloadPresetChips];
		[_presetsScrollView scrollRectToVisible:CGRectInset(sender.frame, -20.0f, 0.0f) animated:YES];
	}
}

- (void)sliderChanged:(UISlider *)sender
{
	NSInteger band = sender.tag;
	float raw = sender.value;

	// Snap near zero for convenience
	if (fabsf(raw) < 0.35f) {
		raw = 0.0f;
		sender.value = 0.0f;
	}

	// Step in 0.5 dB increments
	float stepped = roundf(raw * 2.0f) / 2.0f;
	sender.value = stepped;

	if (band < (NSInteger)_bandValueLabels.count) {
		UILabel *lbl = _bandValueLabels[band];
		lbl.text = [self formattedGain:stepped];
		lbl.textColor = (fabsf(stepped) > 0.05f) ? [MLTheme primary] : [MLTheme onSurfaceVariant];
	}

	[[MLEqualizerManager sharedManager] setGain:stepped forBand:band notify:NO];
	[self reloadPresetChips];
}

- (void)sliderTouchEnded:(UISlider *)sender
{
	[[MLEqualizerManager sharedManager] synchronizeSettings];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLEqualizerDidChangeNotification object:self];
}

- (void)resetTapped:(UIButton *)sender
{
	[MLTheme triggerImpactHaptic];
	[[MLEqualizerManager sharedManager] resetToFlat];
	[self reloadSlidersAnimated:YES];
	[self reloadPresetChips];
}

- (void)handleEqualizerChanged:(NSNotification *)note
{
	if (_masterSwitch.on != [MLEqualizerManager sharedManager].enabled) {
		_masterSwitch.on = [MLEqualizerManager sharedManager].enabled;
		[self updateUIForEnabledStateAnimated:YES];
	}
	[self reloadPresetChips];
}

- (void)handleThemeChanged:(NSNotification *)note
{
	self.view.backgroundColor = [MLTheme background];
	_headerView.backgroundColor = [MLTheme surfaceContainerHigh];
	_titleLabel.textColor = [MLTheme onSurface];
	if ([_masterSwitch respondsToSelector:@selector(setOnTintColor:)]) {
		_masterSwitch.onTintColor = [MLTheme primary];
	}
	_slidersCard.backgroundColor = [MLTheme surfaceContainer];
	_slidersCard.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.18f].CGColor;

	for (UISlider *sl in _bandSliders) {
		sl.minimumTrackTintColor = [MLTheme primary];
		sl.maximumTrackTintColor = [[MLTheme outline] colorWithAlphaComponent:0.25f];
		[sl setThumbImage:[MLTheme circleThumbWithColor:[MLTheme primary] diameter:14.0f] forState:UIControlStateNormal];
		[sl setThumbImage:[MLTheme circleThumbWithColor:[MLTheme primary] diameter:18.0f] forState:UIControlStateHighlighted];
	}
	for (UILabel *lbl in _bandFreqLabels) {
		lbl.textColor = [MLTheme onSurface];
	}

	_resetButton.backgroundColor = [MLTheme surfaceContainerHigh];
	_resetButton.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.3f].CGColor;
	[_resetButton setTitleColor:[MLTheme onSurface] forState:UIControlStateNormal];
	[_resetButton setImage:[MLIcon icon:@"cached" size:16.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];

	_hintLabel.textColor = [MLTheme onSurfaceVariant];

	[self reloadSliders];
	[self reloadPresetChips];
}

@end
