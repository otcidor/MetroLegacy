#import "MLBottomSheet.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLLocalization.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - MLBottomSheetItem

@implementation MLBottomSheetItem

+ (instancetype)itemWithTitle:(NSString *)title handler:(void (^)(void))handler
{
	return [self itemWithTitle:title subtitle:nil iconName:nil isDestructive:NO handler:handler];
}

+ (instancetype)itemWithTitle:(NSString *)title iconName:(NSString *)iconName handler:(void (^)(void))handler
{
	return [self itemWithTitle:title subtitle:nil iconName:iconName isDestructive:NO handler:handler];
}

+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle iconName:(NSString *)iconName handler:(void (^)(void))handler
{
	return [self itemWithTitle:title subtitle:subtitle iconName:iconName isDestructive:NO handler:handler];
}

+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle iconName:(NSString *)iconName isDestructive:(BOOL)destructive handler:(void (^)(void))handler
{
	MLBottomSheetItem *it = [[MLBottomSheetItem alloc] init];
	it.title = title;
	it.subtitle = subtitle;
	it.iconName = iconName;
	it.destructive = destructive;
	it.handler = handler;
	return it;
}

+ (instancetype)itemWithTitle:(NSString *)title swatchColor:(UIColor *)swatch selected:(BOOL)selected handler:(void (^)(void))handler
{
	MLBottomSheetItem *it = [[MLBottomSheetItem alloc] init];
	it.title = title;
	it.swatchColor = swatch;
	it.selected = selected;
	it.handler = handler;
	return it;
}

+ (instancetype)radioItemWithTitle:(NSString *)title subtitle:(NSString *)subtitle selected:(BOOL)selected handler:(void (^)(void))handler
{
	MLBottomSheetItem *it = [[MLBottomSheetItem alloc] init];
	it.title = title;
	it.subtitle = subtitle;
	it.selected = selected;
	it.isRadio = YES;
	it.handler = handler;
	return it;
}

@end

#pragma mark - MLBottomSheetCell

@interface MLBottomSheetCell : UITableViewCell
@property (nonatomic, retain) MLBottomSheetItem *item;
@end

@implementation MLBottomSheetCell
{
	UIView *_highlightCard;
	UIView *_swatchView;
	UIImageView *_iconView;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UIImageView *_trailingView;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;

		_highlightCard = [[UIView alloc] initWithFrame:CGRectZero];
		_highlightCard.layer.cornerRadius = 14.0f;
		_highlightCard.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_highlightCard];

		_swatchView = [[UIView alloc] initWithFrame:CGRectMake(14.0f, 14.0f, 24.0f, 24.0f)];
		_swatchView.layer.cornerRadius = 12.0f;
		_swatchView.layer.borderWidth = 1.0f;
		_swatchView.clipsToBounds = YES;
		[_highlightCard addSubview:_swatchView];

		_iconView = [[UIImageView alloc] initWithFrame:CGRectMake(14.0f, 14.0f, 24.0f, 24.0f)];
		_iconView.contentMode = UIViewContentModeCenter;
		[_highlightCard addSubview:_iconView];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = [MLTheme fontBodyLarge];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[_highlightCard addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.font = [MLTheme fontBodySmall];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		[_highlightCard addSubview:_subtitleLabel];

		_trailingView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 24.0f, 24.0f)];
		_trailingView.contentMode = UIViewContentModeCenter;
		[_highlightCard addSubview:_trailingView];
	}
	return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
	[super setHighlighted:highlighted animated:animated];
	_highlightCard.backgroundColor = highlighted ? [MLTheme surfaceContainerHigh] : [UIColor clearColor];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_highlightCard.frame = CGRectMake(12.0f, 2.0f, b.size.width - 24.0f, b.size.height - 4.0f);
	CGFloat cw = _highlightCard.bounds.size.width;
	CGFloat ch = _highlightCard.bounds.size.height;

	CGFloat leftX = 14.0f;
	if (!_swatchView.hidden) {
		_swatchView.frame = CGRectMake(14.0f, (ch - 24.0f) / 2.0f, 24.0f, 24.0f);
		leftX = 48.0f;
	} else if (!_iconView.hidden) {
		_iconView.frame = CGRectMake(14.0f, (ch - 24.0f) / 2.0f, 24.0f, 24.0f);
		leftX = 48.0f;
	} else {
		leftX = 16.0f;
	}

	CGFloat rightX = cw - 14.0f;
	if (!_trailingView.hidden) {
		_trailingView.frame = CGRectMake(cw - 38.0f, (ch - 24.0f) / 2.0f, 24.0f, 24.0f);
		rightX = _trailingView.frame.origin.x - 8.0f;
	}

	CGFloat textW = MAX(40.0f, rightX - leftX);
	if (_subtitleLabel.text.length > 0 && !_subtitleLabel.hidden) {
		_titleLabel.frame = CGRectMake(leftX, (ch / 2.0f) - 18.0f, textW, 20.0f);
		_subtitleLabel.frame = CGRectMake(leftX, (ch / 2.0f) + 2.0f, textW, 16.0f);
	} else {
		_titleLabel.frame = CGRectMake(leftX, (ch - 22.0f) / 2.0f, textW, 22.0f);
	}
}

- (void)setItem:(MLBottomSheetItem *)item
{
	_item = item;

	// Title & Subtitle
	_titleLabel.text = item.title;
	_titleLabel.textColor = item.destructive ? [UIColor colorWithRed:0.95f green:0.35f blue:0.35f alpha:1.0f] : [MLTheme onSurface];

	if (item.subtitle.length > 0) {
		_subtitleLabel.text = item.subtitle;
		_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
		_subtitleLabel.hidden = NO;
	} else {
		_subtitleLabel.text = nil;
		_subtitleLabel.hidden = YES;
	}

	// Leading: Swatch vs Icon
	if (item.swatchColor) {
		_swatchView.hidden = NO;
		_swatchView.backgroundColor = item.swatchColor;
		_swatchView.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.35f].CGColor;
		_iconView.hidden = YES;
	} else if (item.iconName.length > 0) {
		_swatchView.hidden = YES;
		_iconView.hidden = NO;
		UIColor *icColor = item.destructive ? [UIColor colorWithRed:0.95f green:0.35f blue:0.35f alpha:1.0f] : (item.iconColor ?: [MLTheme onSurfaceVariant]);
		_iconView.image = [MLIcon icon:item.iconName size:20.0f color:icColor];
	} else {
		_swatchView.hidden = YES;
		_iconView.hidden = YES;
	}

	// Trailing: Radio vs Checkmark
	if (item.isRadio) {
		_trailingView.hidden = NO;
		NSString *radIcon = item.selected ? @"radio_button_checked" : @"radio_button_unchecked";
		UIColor *radColor = item.selected ? [MLTheme primary] : [[MLTheme onSurfaceVariant] colorWithAlphaComponent:0.6f];
		_trailingView.image = [MLIcon icon:radIcon size:22.0f color:radColor];
	} else if (item.selected) {
		_trailingView.hidden = NO;
		_trailingView.image = [MLIcon icon:@"check" size:22.0f color:[MLTheme primary]];
	} else {
		_trailingView.hidden = YES;
		_trailingView.image = nil;
	}

	[self setNeedsLayout];
}

@end

#pragma mark - MLBottomSheetMenu

@implementation MLBottomSheetMenu
{
	UIView *_scrimView;
	UIView *_containerView;
	UIView *_dragHandle;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UIView *_divider;
	UITableView *_tableView;
	UIButton *_cancelButton;
	CGFloat _sheetHeight;
	BOOL _dismissing;
}

+ (instancetype)menuWithTitle:(NSString *)title items:(NSArray *)items
{
	return [self menuWithTitle:title subtitle:nil items:items];
}

+ (instancetype)menuWithTitle:(NSString *)title subtitle:(NSString *)subtitle items:(NSArray *)items
{
	MLBottomSheetMenu *menu = [[MLBottomSheetMenu alloc] initWithFrame:[UIScreen mainScreen].bounds];
	menu.title = title;
	menu.subtitle = subtitle;
	menu.items = items;
	return menu;
}

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_showCancelButton = YES;

		// Scrim backdrop
		_scrimView = [[UIView alloc] initWithFrame:self.bounds];
		_scrimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_scrimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55f];
		_scrimView.alpha = 0.0f;
		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(scrimTap:)];
		[_scrimView addGestureRecognizer:tap];
		[self addSubview:_scrimView];

		// Container Card
		_containerView = [[UIView alloc] initWithFrame:CGRectZero];
		_containerView.backgroundColor = [MLTheme surfaceContainer];
		_containerView.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.20f].CGColor;
		_containerView.layer.borderWidth = 0.5f;
		[self addSubview:_containerView];

		// Drag Handle
		_dragHandle = [[UIView alloc] initWithFrame:CGRectMake(0, 10.0f, 36.0f, 4.0f)];
		_dragHandle.backgroundColor = [[MLTheme onSurfaceVariant] colorWithAlphaComponent:0.40f];
		_dragHandle.layer.cornerRadius = 2.0f;
		[_containerView addSubview:_dragHandle];

		// Header labels
		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = [MLTheme fontTitleMedium];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.textAlignment = NSTextAlignmentCenter;
		_titleLabel.backgroundColor = [UIColor clearColor];
		[_containerView addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.font = [MLTheme fontBodySmall];
		_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
		_subtitleLabel.textAlignment = NSTextAlignmentCenter;
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		[_containerView addSubview:_subtitleLabel];

		_divider = [[UIView alloc] initWithFrame:CGRectZero];
		_divider.backgroundColor = [[MLTheme outline] colorWithAlphaComponent:0.15f];
		[_containerView addSubview:_divider];

		// Table View
		_tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
		_tableView.backgroundColor = [UIColor clearColor];
		_tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
		_tableView.dataSource = self;
		_tableView.delegate = self;
		_tableView.showsVerticalScrollIndicator = YES;
		[_containerView addSubview:_tableView];

		// Cancel Button
		_cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
		_cancelButton.layer.cornerRadius = 22.0f;
		_cancelButton.backgroundColor = [MLTheme surfaceContainerHigh];
		_cancelButton.layer.borderWidth = 0.5f;
		_cancelButton.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.25f].CGColor;
		[_cancelButton setTitle:MLLocalizedString(@"cancel", nil) forState:UIControlStateNormal];
		[_cancelButton setTitleColor:[MLTheme onSurface] forState:UIControlStateNormal];
		_cancelButton.titleLabel.font = [UIFont boldSystemFontOfSize:15.0f];
		[_cancelButton addTarget:self action:@selector(cancelTap) forControlEvents:UIControlEventTouchUpInside];
		[_containerView addSubview:_cancelButton];

		// Pan gesture to dismiss
		UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
		pan.delegate = self;
		[_containerView addGestureRecognizer:pan];
	}
	return self;
}

- (void)dealloc
{
	_tableView.dataSource = nil;
	_tableView.delegate = nil;
}

- (void)applyTopCornerRadius:(CGFloat)radius bounds:(CGRect)rect
{
	if (rect.size.width <= 0 || rect.size.height <= 0) return;
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect
	                                           byRoundingCorners:(UIRectCornerTopLeft | UIRectCornerTopRight)
	                                                 cornerRadii:CGSizeMake(radius, radius)];
	CAShapeLayer *mask = [CAShapeLayer layer];
	mask.path = path.CGPath;
	_containerView.layer.mask = mask;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	_scrimView.frame = self.bounds;
	if (!_dismissing && _sheetHeight > 0) {
		CGFloat cw = self.bounds.size.width;
		_containerView.frame = CGRectMake(0, self.bounds.size.height - _sheetHeight, cw, _sheetHeight);
		[self applyTopCornerRadius:MLRadiusSheet bounds:_containerView.bounds];
	}
}

- (void)showInViewController:(UIViewController *)vc
{
	UIView *target = vc.view.window ?: vc.view;
	if (!target) {
		target = [UIApplication sharedApplication].keyWindow;
	}
	[self showInView:target];
}

- (void)showInView:(UIView *)parentView
{
	if (!parentView) return;

	self.frame = parentView.bounds;
	[parentView addSubview:self];

	CGFloat w = parentView.bounds.size.width;
	CGFloat h = parentView.bounds.size.height;

	_titleLabel.text = _title;
	_subtitleLabel.text = _subtitle;

	CGFloat topY = 24.0f;
	if (_title.length > 0) {
		_titleLabel.frame = CGRectMake(20.0f, topY, w - 40.0f, 22.0f);
		topY += 24.0f;
		if (_subtitle.length > 0) {
			_subtitleLabel.frame = CGRectMake(20.0f, topY, w - 40.0f, 16.0f);
			topY += 20.0f;
		}
		_divider.frame = CGRectMake(16.0f, topY + 4.0f, w - 32.0f, 0.5f);
		topY += 10.0f;
	}

	_dragHandle.frame = CGRectMake((w - 36.0f) / 2.0f, 10.0f, 36.0f, 4.0f);

	// Calculate table content height
	CGFloat itemsH = 0.0f;
	for (MLBottomSheetItem *it in _items) {
		itemsH += (it.subtitle.length > 0 ? 58.0f : 50.0f);
	}

	CGFloat cancelH = _showCancelButton ? 52.0f : 0.0f;
	_cancelButton.hidden = !_showCancelButton;

	CGFloat bottomSafe = [MLTheme safeAreaBottomInsetForView:parentView];
	CGFloat bottomPadding = MAX(12.0f, bottomSafe + 8.0f);

	CGFloat totalNeededH = topY + itemsH + cancelH + bottomPadding;
	CGFloat maxAllowedH = h * 0.78f;

	_sheetHeight = MIN(totalNeededH, maxAllowedH);

	CGFloat tableH = _sheetHeight - topY - cancelH - bottomPadding;
	_tableView.frame = CGRectMake(0, topY, w, tableH);
	[_tableView reloadData];

	if (_showCancelButton) {
		_cancelButton.frame = CGRectMake(16.0f, topY + tableH + 6.0f, w - 32.0f, 44.0f);
	}

	// Prepare animation
	_containerView.frame = CGRectMake(0, h, w, _sheetHeight);
	[self applyTopCornerRadius:MLRadiusSheet bounds:CGRectMake(0, 0, w, _sheetHeight)];
	_scrimView.alpha = 0.0f;

	[MLTheme triggerImpactHaptic];

	void (^animations)(void) = ^{
		self->_scrimView.alpha = 1.0f;
		self->_containerView.frame = CGRectMake(0, h - self->_sheetHeight, w, self->_sheetHeight);
	};

	if ([UIView respondsToSelector:@selector(animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:)]) {
		[UIView animateWithDuration:0.32
		                      delay:0
		     usingSpringWithDamping:0.86f
		      initialSpringVelocity:0.5f
		                    options:UIViewAnimationOptionCurveEaseOut
		                 animations:animations
		                 completion:nil];
	} else {
		[UIView animateWithDuration:0.26
		                      delay:0
		                    options:UIViewAnimationOptionCurveEaseOut
		                 animations:animations
		                 completion:nil];
	}
}

- (void)dismissAnimated:(BOOL)animated
{
	if (_dismissing) return;
	_dismissing = YES;

	void (^animations)(void) = ^{
		self->_scrimView.alpha = 0.0f;
		self->_containerView.frame = CGRectMake(0, self.bounds.size.height, self.bounds.size.width, self->_sheetHeight);
	};

	void (^completion)(BOOL) = ^(BOOL finished) {
		[self removeFromSuperview];
	};

	if (!animated) {
		animations();
		completion(YES);
		return;
	}

	[UIView animateWithDuration:0.24
	                      delay:0
	                    options:UIViewAnimationOptionCurveEaseIn
	                 animations:animations
	                 completion:completion];
}

- (void)scrimTap:(UITapGestureRecognizer *)tap
{
	[self dismissAnimated:YES];
}

- (void)cancelTap
{
	[self dismissAnimated:YES];
}

#pragma mark - Pan Gesture

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
	if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
		if (_tableView.contentOffset.y <= 0) {
			return YES;
		}
	}
	return NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan
{
	CGPoint trans = [pan translationInView:_containerView];
	if (pan.state == UIGestureRecognizerStateChanged) {
		if (trans.y > 0) {
			_containerView.transform = CGAffineTransformMakeTranslation(0, trans.y);
			CGFloat progress = trans.y / _sheetHeight;
			_scrimView.alpha = MAX(0.2f, 1.0f - progress * 0.7f);
		}
	} else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		CGPoint vel = [pan velocityInView:_containerView];
		if (trans.y > 75.0f || vel.y > 500.0f) {
			[self dismissAnimated:YES];
		} else {
			[UIView animateWithDuration:0.25
			                      delay:0
			                    options:UIViewAnimationOptionCurveEaseOut
			                 animations:^{
				self->_containerView.transform = CGAffineTransformIdentity;
				self->_scrimView.alpha = 1.0f;
			} completion:nil];
		}
	}
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _items.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	MLBottomSheetItem *it = _items[indexPath.row];
	return (it.subtitle.length > 0 ? 58.0f : 50.0f);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	MLBottomSheetCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sheet_cell"];
	if (!cell) {
		cell = [[MLBottomSheetCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sheet_cell"];
	}
	cell.item = _items[indexPath.row];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[MLTheme triggerImpactHaptic];
	MLBottomSheetItem *it = _items[indexPath.row];
	void (^handler)(void) = it.handler;
	[self dismissAnimated:YES];
	if (handler) {
		handler();
	}
}

@end
