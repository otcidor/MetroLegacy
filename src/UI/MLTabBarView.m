#import "MLTabBarView.h"
#import "MLTheme.h"

/*
 * One tab button: M3 pill indicator behind the selected icon,
 * filled icon when selected, outlined otherwise.
 */
@interface MLTabButton : UIControl

@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) BOOL selectedTab;

@end

@implementation MLTabButton
{
	UIImageView *_iconView;
	UILabel *_labelView;
	UIView *_pillView;
}

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

		_pillView = [[UIView alloc] initWithFrame:CGRectZero];
		_pillView.backgroundColor = [[MLTheme primary] colorWithAlphaComponent:0.20f];
		_pillView.layer.cornerRadius = 15.0f;
		_pillView.hidden = YES;
		_pillView.userInteractionEnabled = NO;
		[self addSubview:_pillView];

		_iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_iconView.contentMode = UIViewContentModeCenter;
		[self addSubview:_iconView];

		_labelView = [[UILabel alloc] initWithFrame:CGRectZero];
		_labelView.font = [UIFont systemFontOfSize:11.0f];
		_labelView.textAlignment = NSTextAlignmentCenter;
		_labelView.backgroundColor = [UIColor clearColor];
		[self addSubview:_labelView];
	}
	return self;
}

- (void)setSelectedTab:(BOOL)selected
{
	_selectedTab = selected;
	[self reloadVisuals];
}

- (void)setIconName:(NSString *)iconName
{
	_iconName = [iconName copy];
	[self reloadVisuals];
}

- (void)setLabel:(NSString *)label
{
	_label = [label copy];
	_labelView.text = _label;
}

- (void)reloadVisuals
{
	UIColor *color = _selectedTab ? [MLTheme primary] : [MLTheme onSurfaceVariant];
	int variant = _selectedTab ? MLIconVariantFilled : MLIconVariantOutlined;
	_iconView.image = [MLIcon icon:_iconName variant:variant size:24.0f color:color];
	_labelView.textColor = color;
	_labelView.font = _selectedTab ? [UIFont boldSystemFontOfSize:11.0f] : [UIFont systemFontOfSize:11.0f];
	_pillView.backgroundColor = [[MLTheme primary] colorWithAlphaComponent:0.22f];
	_pillView.hidden = !_selectedTab;
	[self setNeedsLayout];
}

- (void)layoutSubviews
{
	CGRect b = self.bounds;
	CGFloat pillW = 60.0f, pillH = 30.0f;
	CGFloat pillX = (b.size.width - pillW) / 2.0f;
	_pillView.frame = CGRectMake(pillX, 6.0f, pillW, pillH);
	_iconView.frame = CGRectMake(pillX + (pillW - 24.0f) / 2.0f, 9.0f, 24.0f, 24.0f);
	_labelView.frame = CGRectMake(0, 39.0f, b.size.width, 14.0f);
}

@end

@implementation MLTabBarView
{
	NSArray *_tabs;
	NSMutableArray *_buttons;
	UIView *_topDivider;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [MLTheme background];
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

		_topDivider = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 0.5f)];
		_topDivider.backgroundColor = [UIColor clearColor];
		_topDivider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self addSubview:_topDivider];

		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(themeChanged:)
		                                             name:MLThemeDidChangeNotification
		                                           object:nil];
	}
	return self;
}

- (void)themeChanged:(NSNotification *)note
{
	self.backgroundColor = [MLTheme background];
	for (MLTabButton *b in _buttons) {
		[b reloadVisuals];
	}
}

- (void)setTabs:(NSArray *)tabs
{
	_tabs = [tabs copy];
	_buttons = [NSMutableArray array];
	for (UIView *v in self.subviews) {
		if (v != _topDivider)
			[v removeFromSuperview];
	}

	CGFloat bw = self.bounds.size.width / MAX(tabs.count, 1);
	for (NSUInteger i = 0; i < tabs.count; i++) {
		NSDictionary *t = tabs[i];
		MLTabButton *btn = [[MLTabButton alloc] initWithFrame:CGRectMake(bw * i, 0, bw, self.bounds.size.height)];
		btn.iconName = t[@"icon"];
		btn.label = t[@"label"];
		btn.tag = i;
		[btn addTarget:self action:@selector(tabTap:) forControlEvents:UIControlEventTouchUpInside];
		[self addSubview:btn];
		[_buttons addObject:btn];
	}
	[self layoutIfNeeded];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex
{
	_selectedIndex = selectedIndex;
	for (NSUInteger i = 0; i < _buttons.count; i++) {
		MLTabButton *b = _buttons[i];
		b.selectedTab = (i == selectedIndex);
	}
}

- (void)tabTap:(MLTabButton *)sender
{
	self.selectedIndex = sender.tag;
	if ([_delegate respondsToSelector:@selector(tabBarView:didSelectIndex:)])
		[_delegate tabBarView:self didSelectIndex:sender.tag];
}

- (void)safeAreaInsetsDidChange
{
	[self setNeedsLayout];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	_topDivider.frame = CGRectMake(0, 0, self.bounds.size.width, 0.5f);
	CGFloat bottomInset = [MLTheme safeAreaBottomInsetForView:self];
	CGFloat contentH = MAX(44.0f, self.bounds.size.height - bottomInset);
	CGFloat bw = self.bounds.size.width / MAX(_buttons.count, 1);
	for (NSUInteger i = 0; i < _buttons.count; i++) {
		UIView *b = _buttons[i];
		b.frame = CGRectMake(bw * i, 0, bw, contentH);
	}
}

@end
