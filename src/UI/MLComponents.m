#import "MLComponents.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLImageCache.h"
#import "MLLibraryManager.h"
#import "MLLocalization.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Chips row

@interface MLChipsRowView () <UIScrollViewDelegate>
{
	UIScrollView *_scroll;
	NSMutableArray *_buttons;
	NSArray *_chips;
	NSUInteger _selected;
}
@end

@implementation MLChipsRowView

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		_scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
		_scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_scroll.showsHorizontalScrollIndicator = NO;
		_scroll.showsVerticalScrollIndicator = NO;
		_scroll.alwaysBounceVertical = NO;
		_scroll.alwaysBounceHorizontal = YES;
		_scroll.directionalLockEnabled = YES;
		_scroll.delegate = self;
		[self addSubview:_scroll];
		_buttons = [NSMutableArray array];

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
	[self applyStates];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
	if (scrollView.contentOffset.y != 0.0f) {
		scrollView.contentOffset = CGPointMake(scrollView.contentOffset.x, 0.0f);
	}
}

- (void)setChips:(NSArray *)chips
{
	_chips = chips;
	for (UIView *v in _scroll.subviews)
		[v removeFromSuperview];
	[_buttons removeAllObjects];

	CGFloat x = 14.0f;
	CGFloat h = 34.0f;
	CGFloat y = floorf((self.bounds.size.height - h) / 2.0f);
	if (y < 4.0f)
		y = 7.0f;
	for (NSUInteger i = 0; i < chips.count; i++) {
		MLChip *chip = chips[i];
		UIFont *font = [MLTheme fontTitleSmall];
		CGSize ts = [chip.title sizeWithFont:font constrainedToSize:CGSizeMake(400, h) lineBreakMode:NSLineBreakByTruncatingTail];
		CGFloat w = MAX(60.0f, ts.width + 28.0f);
		UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
		btn.frame = CGRectMake(x, y, w, h);
		btn.titleLabel.font = font;
		btn.titleEdgeInsets = UIEdgeInsetsZero;
		btn.layer.cornerRadius = h / 2.0f;
		btn.clipsToBounds = YES;
		[btn setTitle:chip.title forState:UIControlStateNormal];
		btn.tag = i;
		[btn addTarget:self action:@selector(chipTap:) forControlEvents:UIControlEventTouchUpInside];
		[_scroll addSubview:btn];
		[_buttons addObject:btn];
		x += w + 8.0f;
	}
	_scroll.contentInset = UIEdgeInsetsZero;
	_scroll.contentSize = CGSizeMake(MAX(x + 6.0f, self.bounds.size.width), 0.0f);
	[self applyStates];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	_scroll.frame = self.bounds;
	_scroll.contentInset = UIEdgeInsetsZero;
	CGFloat h = 34.0f;
	CGFloat y = floorf((self.bounds.size.height - h) / 2.0f);
	for (UIButton *b in _buttons) {
		CGRect f = b.frame;
		f.origin.y = y;
		b.frame = f;
	}
	_scroll.contentSize = CGSizeMake(_scroll.contentSize.width, 0.0f);
}

- (void)setSelectedIndex:(NSUInteger)index
{
	_selected = index;
	[self applyStates];
}

- (void)chipTap:(UIButton *)sender
{
	_selected = sender.tag;
	[self applyStates];
	if (_onChange && sender.tag < _chips.count)
		_onChange(_chips[sender.tag]);
}

- (void)applyStates
{
	for (NSUInteger i = 0; i < _buttons.count; i++) {
		UIButton *b = _buttons[i];
		BOOL sel = (i == _selected);
		if (sel) {
			[b setBackgroundColor:[MLTheme primary]];
			[b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
			b.titleLabel.font = [MLTheme fontTitleSmall];
			b.layer.borderWidth = 0.0f;
		} else {
			[b setBackgroundColor:[MLTheme surfaceContainer]];
			[b setTitleColor:[MLTheme onSurfaceVariant] forState:UIControlStateNormal];
			b.titleLabel.font = [MLTheme fontBodyMedium];
			b.layer.borderWidth = 1.0f;
			b.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.32f].CGColor;
		}
	}
}

@end

#pragma mark - Card button

@implementation MLCardButton
{
	UIImageView *_thumb;
	UIView *_playBadge;
	UIImageView *_playBadgeIcon;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	MLYTItem *_item;
}

- (MLYTItem *)item { return _item; }

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		CGFloat w = frame.size.width;
		CGFloat thumbSide = MIN(w - 14.0f, 134.0f);
		_thumb = [[UIImageView alloc] initWithFrame:CGRectMake(7.0f, 4.0f, thumbSide, thumbSide)];
		_thumb.contentMode = UIViewContentModeScaleAspectFill;
		_thumb.opaque = NO;
		[self addSubview:_thumb];

		_playBadge = [[UIView alloc] initWithFrame:CGRectMake(7.0f + thumbSide - 34.0f, 4.0f + thumbSide - 34.0f, 28.0f, 28.0f)];
		_playBadge.backgroundColor = [UIColor colorWithWhite:0.08f alpha:0.78f];
		_playBadge.layer.cornerRadius = 14.0f;
		_playBadge.userInteractionEnabled = NO;
		[self addSubview:_playBadge];

		_playBadgeIcon = [[UIImageView alloc] initWithFrame:CGRectMake(5.0f, 5.0f, 18.0f, 18.0f)];
		_playBadgeIcon.image = [MLIcon icon:@"play_arrow" size:18.0f color:[UIColor whiteColor]];
		[_playBadge addSubview:_playBadgeIcon];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(7.0f, thumbSide + 10.0f, thumbSide, 34.0f)];
		_titleLabel.font = [MLTheme fontTitleSmall];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		_titleLabel.numberOfLines = 2;
		_titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		[self addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(7.0f, thumbSide + 45.0f, thumbSide, 16.0f)];
		_subtitleLabel.font = [MLTheme fontBodySmall];
		_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		[self addSubview:_subtitleLabel];
	}
	return self;
}

- (void)setHighlighted:(BOOL)highlighted
{
	[super setHighlighted:highlighted];
	self.alpha = highlighted ? 0.75f : 1.0f;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGFloat w = self.bounds.size.width;
	CGFloat thumbSide = w - 4.0f;
	_thumb.frame = CGRectMake(2.0f, 2.0f, thumbSide, thumbSide);
	BOOL isArtist = (_item && (_item.kind == MLYTKindArtist || [_item.browseId hasPrefix:@"UC"]));
	_thumb.layer.cornerRadius = isArtist ? (thumbSide / 2.0f) : 10.0f;
	_thumb.clipsToBounds = YES;

	CGFloat badgeSize = MIN(28.0f, thumbSide * 0.28f);
	_playBadge.frame = CGRectMake(2.0f + thumbSide - badgeSize - 4.0f, 2.0f + thumbSide - badgeSize - 4.0f, badgeSize, badgeSize);
	_playBadge.layer.cornerRadius = badgeSize / 2.0f;
	CGFloat iconSize = MIN(18.0f, badgeSize * 0.65f);
	_playBadgeIcon.frame = CGRectMake((badgeSize - iconSize) / 2.0f, (badgeSize - iconSize) / 2.0f, iconSize, iconSize);

	_titleLabel.frame = CGRectMake(2.0f, thumbSide + 6.0f, thumbSide, 34.0f);
	_subtitleLabel.frame = CGRectMake(2.0f, thumbSide + 38.0f, thumbSide, 16.0f);
}

- (void)fillWithItem:(MLYTItem *)item
{
	_item = item;
	_titleLabel.text = item.title;
	BOOL isArtist = (item.kind == MLYTKindArtist || [item.browseId hasPrefix:@"UC"]);
	_titleLabel.textAlignment = isArtist ? NSTextAlignmentCenter : NSTextAlignmentLeft;
	_subtitleLabel.textAlignment = isArtist ? NSTextAlignmentCenter : NSTextAlignmentLeft;
	_playBadge.hidden = isArtist;

	NSString *sub = item.subtitle;
	if (!sub.length && item.artists.count > 0) {
		sub = [item.artists componentsJoinedByString:@", "];
	}
	if ([sub length] > 42)
		sub = [NSString stringWithFormat:@"%@…", [sub substringToIndex:42]];
	_subtitleLabel.text = sub;

	[self setNeedsLayout];
	[self layoutIfNeeded];

	CGFloat thumbSide = _thumb.frame.size.width;
	CGFloat radius = isArtist ? (thumbSide / 2.0f) : 10.0f;
	if (item.thumbnailUrl.length > 0)
		[MLImageCache loadImageAtURLString:item.thumbnailUrl intoView:_thumb fitSize:_thumb.frame.size cornerRadius:radius placeholder:[MLImageCache placeholderImageWithSize:_thumb.frame.size]];
	else
		_thumb.image = [MLImageCache placeholderImageWithSize:_thumb.frame.size];
}

@end

#pragma mark - Shelf cell

@interface MLShelfCell ()
{
	UILabel *_titleLabel;
	UIScrollView *_shelf;
	MLHomeSection *_section;
	NSMutableArray *_cards;
}
@end

@implementation MLShelfCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		_cards = [NSMutableArray array];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0f, 8.0f, 280.0f, 24.0f)];
		_titleLabel.font = [UIFont boldSystemFontOfSize:19.0f];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_titleLabel];

		_shelf = [[UIScrollView alloc] initWithFrame:CGRectZero];
		_shelf.showsHorizontalScrollIndicator = NO;
		_shelf.showsVerticalScrollIndicator = NO;
		_shelf.alwaysBounceVertical = NO;
		_shelf.directionalLockEnabled = YES;
		[self.contentView addSubview:_shelf];
	}
	return self;
}

- (void)fillWithSection:(MLHomeSection *)section
{
	BOOL sameSection = (_section == section);
	_section = section;
	_titleLabel.text = section.title;

	NSUInteger count = section.items.count;
	while (_cards.count < count) {
		MLCardButton *card = [[MLCardButton alloc] initWithFrame:CGRectMake(0, 0, 148.0f, 200.0f)];
		[card addTarget:self action:@selector(cardTap:) forControlEvents:UIControlEventTouchUpInside];
		[_shelf addSubview:card];
		[_cards addObject:card];
	}

	CGFloat x = 8.0f;
	for (NSUInteger i = 0; i < _cards.count; i++) {
		MLCardButton *card = _cards[i];
		if (i < count) {
			card.hidden = NO;
			card.frame = CGRectMake(x, 0, 148.0f, 200.0f);
			MLYTItem *item = section.items[i];
			if (!sameSection || card.item != item) {
				[card fillWithItem:item];
			}
			x += 150.0f;
		} else {
			card.hidden = YES;
		}
	}
	_shelf.contentSize = CGSizeMake(MAX(x + 8.0f, _shelf.frame.size.width), 200.0f);
	if (!sameSection) {
		_shelf.contentOffset = CGPointZero;
	}
}

- (void)cardTap:(MLCardButton *)sender
{
	if (_cardTapped)
		_cardTapped(sender.item);
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_titleLabel.frame = CGRectMake(14.0f, 8.0f, b.size.width - 28.0f, 24.0f);
	_shelf.frame = CGRectMake(0, 36.0f, b.size.width, 200.0f);
	CGFloat x = 8.0f + _section.items.count * 150.0f;
	_shelf.contentSize = CGSizeMake(MAX(x + 8.0f, b.size.width), 200.0f);
}

@end

#pragma mark - Quick Picks 3-row horizontal song shelf (Metrolist style)

@interface MLQuickPickRowControl : UIControl
@property (nonatomic, strong) MLYTItem *item;
@property (nonatomic, copy) void (^moreTapped)(MLYTItem *item);
- (void)fillWithItem:(MLYTItem *)item isPlaying:(BOOL)isPlaying;
@end

@implementation MLQuickPickRowControl
{
	UIImageView *_thumb;
	UIView *_playingOverlay;
	UIImageView *_eqIcon;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UIButton *_moreButton;
}

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.layer.cornerRadius = 10.0f;

		_thumb = [[UIImageView alloc] initWithFrame:CGRectMake(6.0f, 5.0f, 48.0f, 48.0f)];
		_thumb.contentMode = UIViewContentModeScaleAspectFill;
		_thumb.opaque = NO;
		[self addSubview:_thumb];

		_playingOverlay = [[UIView alloc] initWithFrame:_thumb.bounds];
		_playingOverlay.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.55f];
		_playingOverlay.layer.cornerRadius = MLRadiusThumbnail;
		_playingOverlay.clipsToBounds = YES;
		_playingOverlay.hidden = YES;
		[_thumb addSubview:_playingOverlay];

		_eqIcon = [[UIImageView alloc] initWithFrame:CGRectMake(14.0f, 14.0f, 20.0f, 20.0f)];
		_eqIcon.image = [MLIcon icon:@"equalizer" size:20.0f color:[MLTheme primary]];
		[_playingOverlay addSubview:_eqIcon];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = [MLTheme fontTitleSmall];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[self addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.font = [MLTheme fontBodySmall];
		_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		[self addSubview:_subtitleLabel];

		_moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[_moreButton setImage:[MLIcon icon:@"more_vert" size:20.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
		[_moreButton addTarget:self action:@selector(moreTap:) forControlEvents:UIControlEventTouchUpInside];
		[self addSubview:_moreButton];
	}
	return self;
}

- (void)setHighlighted:(BOOL)highlighted
{
	[super setHighlighted:highlighted];
	self.backgroundColor = highlighted ? [MLTheme surfaceContainerHigh] : (_playingOverlay.hidden ? [UIColor clearColor] : [MLTheme surfaceContainer]);
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.bounds;
	_thumb.frame = CGRectMake(6.0f, (b.size.height - 48.0f) / 2.0f, 48.0f, 48.0f);
	_playingOverlay.frame = _thumb.bounds;
	_moreButton.frame = CGRectMake(b.size.width - 36.0f, (b.size.height - 36.0f) / 2.0f, 34.0f, 36.0f);
	CGFloat textX = 62.0f;
	CGFloat textW = MAX(40.0f, _moreButton.frame.origin.x - textX - 4.0f);
	_titleLabel.frame = CGRectMake(textX, 10.0f, textW, 19.0f);
	_subtitleLabel.frame = CGRectMake(textX, 30.0f, textW, 16.0f);
}

- (void)fillWithItem:(MLYTItem *)item isPlaying:(BOOL)isPlaying
{
	_item = item;
	_playingOverlay.hidden = !isPlaying;
	self.backgroundColor = isPlaying ? [MLTheme surfaceContainer] : [UIColor clearColor];
	_titleLabel.text = item.title;
	_titleLabel.textColor = isPlaying ? [MLTheme primary] : [MLTheme onSurface];

	BOOL isContainer = (item.kind == MLYTKindPlaylist ||
	                    item.kind == MLYTKindAlbum ||
	                    item.kind == MLYTKindArtist ||
	                    [item.browseId hasPrefix:@"VL"] ||
	                    [item.browseId hasPrefix:@"MPRE"] ||
	                    [item.browseId hasPrefix:@"UC"] ||
	                    item.videoId.length == 0);
	NSString *rightIcon = isContainer ? @"chevron_right" : @"more_vert";
	[_moreButton setImage:[MLIcon icon:rightIcon size:20.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];

	NSString *sub = item.subtitle;
	if (item.artists.count > 0 && (!sub.length || [sub isEqualToString:item.title])) {
		sub = [item.artists componentsJoinedByString:@", "];
	}
	if (item.duration > 0 && sub.length > 0) {
		sub = [NSString stringWithFormat:@"%@ • %@", sub, MLFormatDuration(item.duration)];
	}
	_subtitleLabel.text = sub;

	if (item.thumbnailUrl.length > 0)
		[MLImageCache loadImageAtURLString:item.thumbnailUrl intoView:_thumb fitSize:_thumb.frame.size cornerRadius:MLRadiusThumbnail placeholder:[MLImageCache placeholderImageWithSize:_thumb.frame.size]];
	else
		_thumb.image = [MLImageCache placeholderImageWithSize:_thumb.frame.size];
}

- (void)moreTap:(UIButton *)sender
{
	if (_moreTapped && _item)
		_moreTapped(_item);
}

@end

@implementation MLQuickPicksShelfCell
{
	UILabel *_titleLabel;
	UIScrollView *_scroll;
	MLHomeSection *_section;
	NSMutableArray *_rowControls;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		_rowControls = [NSMutableArray array];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0f, 8.0f, 280.0f, 24.0f)];
		_titleLabel.font = [UIFont boldSystemFontOfSize:19.0f];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_titleLabel];

		_scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
		_scroll.showsHorizontalScrollIndicator = NO;
		_scroll.showsVerticalScrollIndicator = NO;
		_scroll.alwaysBounceVertical = NO;
		_scroll.alwaysBounceHorizontal = YES;
		_scroll.directionalLockEnabled = YES;
		_scroll.decelerationRate = UIScrollViewDecelerationRateFast;
		[self.contentView addSubview:_scroll];
	}
	return self;
}

- (void)fillWithSection:(MLHomeSection *)section playingVideoId:(NSString *)playingVideoId
{
	BOOL sameSection = (_section == section);
	_section = section;
	_titleLabel.text = section.title;

	NSUInteger count = section.items.count;
	__weak MLQuickPicksShelfCell *wself = self;
	while (_rowControls.count < count) {
		MLQuickPickRowControl *ctrl = [[MLQuickPickRowControl alloc] initWithFrame:CGRectMake(0, 0, 280.0f, 58.0f)];
		[ctrl addTarget:self action:@selector(rowTap:) forControlEvents:UIControlEventTouchUpInside];
		ctrl.moreTapped = ^(MLYTItem *tapped) {
			MLQuickPicksShelfCell *s = wself;
			if (s && s.moreTapped)
				s.moreTapped(tapped);
		};
		[_scroll addSubview:ctrl];
		[_rowControls addObject:ctrl];
	}

	for (NSUInteger i = 0; i < _rowControls.count; i++) {
		MLQuickPickRowControl *ctrl = _rowControls[i];
		if (i < count) {
			ctrl.hidden = NO;
			MLYTItem *item = section.items[i];
			BOOL isPlaying = (playingVideoId.length > 0 && [item.videoId isEqualToString:playingVideoId]);
			[ctrl fillWithItem:item isPlaying:isPlaying];
		} else {
			ctrl.hidden = YES;
		}
	}
	if (!sameSection) {
		_scroll.contentOffset = CGPointZero;
	}
	[self setNeedsLayout];
}

- (void)rowTap:(MLQuickPickRowControl *)sender
{
	if (_songTapped && sender.item) {
		_songTapped(sender.item, _section.items);
	}
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_titleLabel.frame = CGRectMake(14.0f, 8.0f, b.size.width - 28.0f, 24.0f);
	_scroll.frame = CGRectMake(0, 36.0f, b.size.width, 180.0f);

	CGFloat colW = MAX(250.0f, b.size.width - 36.0f);
	CGFloat rowH = 58.0f;
	NSUInteger rowsPerCol = 3;
	NSUInteger activeCount = _section.items.count;
	NSUInteger totalCols = (activeCount + rowsPerCol - 1) / rowsPerCol;

	for (NSUInteger idx = 0; idx < activeCount && idx < _rowControls.count; idx++) {
		NSUInteger col = idx / rowsPerCol;
		NSUInteger row = idx % rowsPerCol;
		MLQuickPickRowControl *ctrl = _rowControls[idx];
		CGFloat x = 10.0f + col * (colW + 8.0f);
		CGFloat y = row * (rowH + 2.0f);
		ctrl.frame = CGRectMake(x, y, colW, rowH);
	}

	CGFloat contentW = 10.0f + totalCols * (colW + 8.0f) + 8.0f;
	_scroll.contentSize = CGSizeMake(MAX(contentW, b.size.width), 0.0f);
}

@end

#pragma mark - Grid shelf cell (3-column MetroList-style)

@interface MLGridShelfCell ()
{
	UILabel *_titleLabel;
	MLHomeSection *_section;
	NSMutableArray *_cards; // MLCardButton
}
@end

@implementation MLGridShelfCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		_cards = [NSMutableArray array];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0f, 8.0f, 280.0f, 24.0f)];
		_titleLabel.font = [UIFont boldSystemFontOfSize:19.0f];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_titleLabel];
	}
	return self;
}

+ (CGFloat)heightForSection:(MLHomeSection *)section width:(CGFloat)width
{
	NSUInteger count = section.items.count;
	if (count == 0) return 0.0f;
	CGFloat pad = 12.0f;
	CGFloat gap = 8.0f;
	CGFloat colW = floorf((width - pad * 2.0f - gap * 2.0f) / 3.0f);
	CGFloat cardH = colW + 52.0f; // thumb + title + subtitle
	NSUInteger rows = (count + 2) / 3;
	return 38.0f + rows * (cardH + gap) + 4.0f;
}

- (void)fillWithSection:(MLHomeSection *)section
{
	BOOL sameSection = (_section == section);
	_section = section;
	_titleLabel.text = section.title;

	NSUInteger count = section.items.count;
	while (_cards.count < count) {
		MLCardButton *card = [[MLCardButton alloc] initWithFrame:CGRectMake(0, 0, 100.0f, 160.0f)];
		[card addTarget:self action:@selector(cardTap:) forControlEvents:UIControlEventTouchUpInside];
		[self.contentView addSubview:card];
		[_cards addObject:card];
	}

	for (NSUInteger i = 0; i < _cards.count; i++) {
		MLCardButton *card = _cards[i];
		if (i < count) {
			card.hidden = NO;
			MLYTItem *item = section.items[i];
			if (!sameSection || card.item != item) {
				[card fillWithItem:item];
			}
		} else {
			card.hidden = YES;
		}
	}
	[self setNeedsLayout];
}

- (void)cardTap:(MLCardButton *)sender
{
	if (_cardTapped)
		_cardTapped(sender.item);
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_titleLabel.frame = CGRectMake(14.0f, 8.0f, b.size.width - 28.0f, 24.0f);

	CGFloat pad = 12.0f;
	CGFloat gap = 8.0f;
	CGFloat colW = floorf((b.size.width - pad * 2.0f - gap * 2.0f) / 3.0f);
	CGFloat cardH = colW + 52.0f;
	CGFloat startY = 36.0f;
	NSUInteger count = _section.items.count;

	for (NSUInteger i = 0; i < count && i < _cards.count; i++) {
		NSUInteger col = i % 3;
		NSUInteger row = i / 3;
		CGFloat x = pad + col * (colW + gap);
		CGFloat y = startY + row * (cardH + gap);
		MLCardButton *card = _cards[i];
		card.frame = CGRectMake(x, y, colW, cardH);
	}
}

@end

#pragma mark - Speed Dial cell (3x3 paged grid, MetroList Home)

@interface MLSpeedDialItemView : UIControl
{
	UIImageView *_thumb;
	UIView *_gradientView;
	CAGradientLayer *_gradientLayer;
	UILabel *_titleLabel;
	UIImageView *_luckyIcon;
	BOOL _isLucky;
	MLYTItem *_item;
}
@property (nonatomic, readonly) MLYTItem *item;
@property (nonatomic, readonly) BOOL isLucky;
- (void)fillWithItem:(MLYTItem *)item isLucky:(BOOL)isLucky;
@end

@implementation MLSpeedDialItemView

- (MLYTItem *)item { return _item; }
- (BOOL)isLucky { return _isLucky; }

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [MLTheme surfaceContainer];
		self.layer.cornerRadius = 10.0f;
		self.clipsToBounds = YES;

		_thumb = [[UIImageView alloc] initWithFrame:self.bounds];
		_thumb.contentMode = UIViewContentModeScaleAspectFill;
		_thumb.clipsToBounds = YES;
		_thumb.opaque = NO;
		[self addSubview:_thumb];

		_gradientView = [[UIView alloc] initWithFrame:self.bounds];
		_gradientView.userInteractionEnabled = NO;
		_gradientLayer = [CAGradientLayer layer];
		_gradientLayer.colors = @[
			(id)[UIColor clearColor].CGColor,
			(id)[UIColor colorWithWhite:0.0f alpha:0.45f].CGColor,
			(id)[UIColor colorWithWhite:0.0f alpha:0.88f].CGColor
		];
		_gradientLayer.locations = @[ @0.0f, @0.50f, @1.0f ];
		[_gradientView.layer addSublayer:_gradientLayer];
		[self addSubview:_gradientView];

		_luckyIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
		_luckyIcon.contentMode = UIViewContentModeCenter;
		_luckyIcon.image = [MLIcon icon:@"casino" size:32.0f color:[UIColor whiteColor]];
		_luckyIcon.hidden = YES;
		[self addSubview:_luckyIcon];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = [UIFont boldSystemFontOfSize:11.5f];
		_titleLabel.textColor = [UIColor whiteColor];
		_titleLabel.backgroundColor = [UIColor clearColor];
		_titleLabel.numberOfLines = 2;
		_titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		_titleLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.7f];
		_titleLabel.shadowOffset = CGSizeMake(0, 1.0f);
		[self addSubview:_titleLabel];
	}
	return self;
}

- (void)setHighlighted:(BOOL)highlighted
{
	[super setHighlighted:highlighted];
	self.alpha = highlighted ? 0.72f : 1.0f;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.bounds;
	_thumb.frame = b;
	_gradientView.frame = b;
	_gradientLayer.frame = b;

	if (_isLucky) {
		_luckyIcon.frame = CGRectMake((b.size.width - 36.0f) / 2.0f, (b.size.height - 48.0f) / 2.0f, 36.0f, 36.0f);
		_titleLabel.frame = CGRectMake(4.0f, b.size.height - 24.0f, b.size.width - 8.0f, 20.0f);
		_titleLabel.textAlignment = NSTextAlignmentCenter;
	} else {
		_titleLabel.frame = CGRectMake(6.0f, b.size.height - 32.0f, b.size.width - 12.0f, 28.0f);
		_titleLabel.textAlignment = NSTextAlignmentLeft;
	}
}

- (void)fillWithItem:(MLYTItem *)item isLucky:(BOOL)isLucky
{
	_item = item;
	_isLucky = isLucky;

	if (isLucky) {
		_thumb.hidden = YES;
		_gradientView.hidden = YES;
		_luckyIcon.hidden = NO;
		self.backgroundColor = [UIColor colorWithRed:0.20f green:0.24f blue:0.34f alpha:1.0f];
		_titleLabel.text = item.title.length ? item.title : MLLocalizedString(@"speed_dial_lucky", nil);
	} else {
		_thumb.hidden = NO;
		_gradientView.hidden = NO;
		_luckyIcon.hidden = YES;
		self.backgroundColor = [MLTheme surfaceContainer];
		_titleLabel.text = item.title;

		if (item.thumbnailUrl.length > 0) {
			[MLImageCache loadImageAtURLString:item.thumbnailUrl intoView:_thumb fitSize:self.bounds.size cornerRadius:0.0f placeholder:[MLImageCache placeholderImageWithSize:self.bounds.size]];
		} else {
			_thumb.image = [MLImageCache placeholderImageWithSize:self.bounds.size];
		}
	}
	[self setNeedsLayout];
}

@end

@interface MLSpeedDialCell () <UIScrollViewDelegate>
{
	UILabel *_titleLabel;
	UIScrollView *_scroll;
	UIPageControl *_pageControl;
	NSMutableArray *_itemViews;
	NSArray *_items;
}
@end

@implementation MLSpeedDialCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		_itemViews = [NSMutableArray array];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0f, 8.0f, 280.0f, 24.0f)];
		_titleLabel.font = [UIFont boldSystemFontOfSize:19.0f];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_titleLabel];

		_scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
		_scroll.pagingEnabled = YES;
		_scroll.showsHorizontalScrollIndicator = NO;
		_scroll.showsVerticalScrollIndicator = NO;
		_scroll.directionalLockEnabled = YES;
		_scroll.delegate = self;
		[self.contentView addSubview:_scroll];

		_pageControl = [[UIPageControl alloc] initWithFrame:CGRectZero];
		if ([_pageControl respondsToSelector:@selector(setCurrentPageIndicatorTintColor:)]) {
			_pageControl.currentPageIndicatorTintColor = [MLTheme primary];
			_pageControl.pageIndicatorTintColor = [[MLTheme onSurfaceVariant] colorWithAlphaComponent:0.35f];
		}
		_pageControl.userInteractionEnabled = NO;
		[self.contentView addSubview:_pageControl];
	}
	return self;
}

+ (CGFloat)heightForWidth:(CGFloat)width
{
	CGFloat pad = 12.0f;
	CGFloat gap = 6.0f;
	CGFloat colW = floorf((width - pad * 2.0f - gap * 2.0f) / 3.0f);
	CGFloat gridH = colW * 3.0f + gap * 2.0f;
	return 36.0f + gridH + 26.0f;
}

- (void)fillWithItems:(NSArray *)items title:(NSString *)title
{
	_items = items;
	_titleLabel.text = title.length ? title : MLLocalizedString(@"speed_dial", nil);

	NSUInteger count = items.count;
	while (_itemViews.count < count) {
		MLSpeedDialItemView *v = [[MLSpeedDialItemView alloc] initWithFrame:CGRectZero];
		[v addTarget:self action:@selector(itemTap:) forControlEvents:UIControlEventTouchUpInside];
		[_scroll addSubview:v];
		[_itemViews addObject:v];
	}

	for (NSUInteger i = 0; i < _itemViews.count; i++) {
		MLSpeedDialItemView *v = _itemViews[i];
		if (i < count) {
			v.hidden = NO;
			MLYTItem *it = items[i];
			BOOL isLucky = [it.videoId isEqualToString:@"speed_dial_lucky"] || [it.browseId isEqualToString:@"speed_dial_lucky"];
			[v fillWithItem:it isLucky:isLucky];
		} else {
			v.hidden = YES;
		}
	}

	NSUInteger pages = (count + 8) / 9;
	_pageControl.numberOfPages = pages;
	_pageControl.currentPage = 0;
	_pageControl.hidden = (pages <= 1);
	[self setNeedsLayout];
}

- (void)itemTap:(MLSpeedDialItemView *)sender
{
	if (_itemTapped) {
		_itemTapped(sender.item, sender.isLucky);
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
	CGFloat pageWidth = scrollView.frame.size.width;
	if (pageWidth > 0.0f) {
		int page = floor((scrollView.contentOffset.x - pageWidth / 2.0f) / pageWidth) + 1;
		_pageControl.currentPage = page;
	}
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_titleLabel.frame = CGRectMake(14.0f, 8.0f, b.size.width - 28.0f, 24.0f);

	CGFloat pad = 12.0f;
	CGFloat gap = 6.0f;
	CGFloat colW = floorf((b.size.width - pad * 2.0f - gap * 2.0f) / 3.0f);
	CGFloat gridH = colW * 3.0f + gap * 2.0f;
	CGFloat startY = 36.0f;

	_scroll.frame = CGRectMake(0, startY, b.size.width, gridH);
	_pageControl.frame = CGRectMake(0, startY + gridH + 2.0f, b.size.width, 20.0f);

	NSUInteger count = _items.count;
	NSUInteger pages = (count + 8) / 9;

	for (NSUInteger i = 0; i < count && i < _itemViews.count; i++) {
		NSUInteger page = i / 9;
		NSUInteger indexInPage = i % 9;
		NSUInteger col = indexInPage % 3;
		NSUInteger row = indexInPage / 3;

		CGFloat pageX = page * b.size.width;
		CGFloat x = pageX + pad + col * (colW + gap);
		CGFloat y = row * (colW + gap);

		MLSpeedDialItemView *v = _itemViews[i];
		v.frame = CGRectMake(x, y, colW, colW);
	}

	_scroll.contentSize = CGSizeMake(pages * b.size.width, gridH);
}

@end

#pragma mark - Song cell

@interface MLSongCell ()
{
	UIView *_bgCard;
	UIImageView *_thumb;
	UIView *_playingOverlay;
	UIImageView *_eqIcon;
	UIImageView *_downloadedBadge;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UILabel *_durationLabel;
	UIButton *_moreButton;
	MLYTItem *_item;
	BOOL _isPlaying;
}
@end

@implementation MLSongCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;

		_bgCard = [[UIView alloc] initWithFrame:CGRectZero];
		_bgCard.backgroundColor = [MLTheme surfaceContainer];
		_bgCard.layer.cornerRadius = 12.0f;
		_bgCard.layer.borderWidth = 1.0f;
		_bgCard.layer.borderColor = [[MLTheme primary] colorWithAlphaComponent:0.35f].CGColor;
		_bgCard.hidden = YES;
		[self.contentView addSubview:_bgCard];

		_thumb = [[UIImageView alloc] initWithFrame:CGRectMake(12.0f, 8.0f, 48.0f, 48.0f)];
		_thumb.contentMode = UIViewContentModeScaleAspectFill;
		_thumb.opaque = NO;
		[self.contentView addSubview:_thumb];

		_playingOverlay = [[UIView alloc] initWithFrame:_thumb.bounds];
		_playingOverlay.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.55f];
		_playingOverlay.layer.cornerRadius = MLRadiusThumbnail;
		_playingOverlay.clipsToBounds = YES;
		_playingOverlay.hidden = YES;
		[_thumb addSubview:_playingOverlay];

		_eqIcon = [[UIImageView alloc] initWithFrame:CGRectMake(14.0f, 14.0f, 20.0f, 20.0f)];
		_eqIcon.image = [MLIcon icon:@"equalizer" size:20.0f color:[MLTheme primary]];
		[_playingOverlay addSubview:_eqIcon];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = [MLTheme fontTitleSmall];
		_titleLabel.textColor = [MLTheme onSurface];
		_titleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_titleLabel];

		_downloadedBadge = [[UIImageView alloc] initWithImage:[MLIcon icon:@"download_done" size:13.0f color:[UIColor colorWithRed:0.18f green:0.65f blue:0.45f alpha:1.0f]]];
		_downloadedBadge.hidden = YES;
		[self.contentView addSubview:_downloadedBadge];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.font = [MLTheme fontBodySmall];
		_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_subtitleLabel];

		_durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_durationLabel.font = [MLTheme fontLabelMedium];
		_durationLabel.textColor = [MLTheme onSurfaceVariant];
		_durationLabel.textAlignment = NSTextAlignmentRight;
		_durationLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_durationLabel];

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
	if (highlighted) {
		_bgCard.hidden = NO;
		_bgCard.backgroundColor = [MLTheme surfaceContainerHigh];
	} else {
		_bgCard.hidden = !_isPlaying;
		_bgCard.backgroundColor = [MLTheme surfaceContainer];
	}
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	_bgCard.frame = CGRectMake(6.0f, 2.0f, b.size.width - 12.0f, b.size.height - 4.0f);
	_thumb.frame = CGRectMake(12.0f, (b.size.height - 48.0f) / 2.0f, 48.0f, 48.0f);
	_playingOverlay.frame = _thumb.bounds;
	_moreButton.frame = CGRectMake(b.size.width - 40.0f, (b.size.height - 36.0f) / 2.0f, 36.0f, 36.0f);

	CGFloat rightMargin = _moreButton.frame.origin.x;
	if (!_durationLabel.hidden && _durationLabel.text.length > 0) {
		CGFloat durW = 42.0f;
		_durationLabel.frame = CGRectMake(_moreButton.frame.origin.x - durW, (b.size.height - 18.0f) / 2.0f, durW, 18.0f);
		rightMargin = _durationLabel.frame.origin.x - 4.0f;
	}

	CGFloat textX = 70.0f;
	CGFloat textW = MAX(40.0f, rightMargin - textX);
	_titleLabel.frame = CGRectMake(textX, 13.0f, textW, 19.0f);
	if (!_downloadedBadge.hidden) {
		_downloadedBadge.frame = CGRectMake(textX, 34.5f, 13.0f, 13.0f);
		_subtitleLabel.frame = CGRectMake(textX + 17.0f, 33.0f, MAX(20.0f, textW - 17.0f), 16.0f);
	} else {
		_subtitleLabel.frame = CGRectMake(textX, 33.0f, textW, 16.0f);
	}
}

- (void)fillWithItem:(MLYTItem *)item
{
	[self fillWithItem:item isPlaying:NO];
}

- (void)fillWithItem:(MLYTItem *)item isPlaying:(BOOL)isPlaying
{
	_item = item;
	_isPlaying = isPlaying;
	_bgCard.hidden = !isPlaying;
	_bgCard.backgroundColor = [MLTheme surfaceContainer];
	_playingOverlay.hidden = !isPlaying;

	BOOL isDownloaded = (item.videoId.length > 0 && [[MLLibraryManager sharedManager] isSongDownloaded:item.videoId]);
	BOOL isDownloading = (item.videoId.length > 0 && [[MLLibraryManager sharedManager] isSongDownloading:item.videoId]);
	if (isDownloaded) {
		_downloadedBadge.image = [MLIcon icon:@"download_done" size:13.0f color:[UIColor colorWithRed:0.18f green:0.65f blue:0.45f alpha:1.0f]];
		_downloadedBadge.hidden = NO;
	} else if (isDownloading) {
		_downloadedBadge.image = [MLIcon icon:@"download" size:13.0f color:[MLTheme primary]];
		_downloadedBadge.hidden = NO;
	} else {
		_downloadedBadge.hidden = YES;
	}

	_titleLabel.text = item.title;
	_titleLabel.textColor = isPlaying ? [MLTheme primary] : [MLTheme onSurface];
	_titleLabel.font = isPlaying ? [MLTheme fontTitleSmall] : [MLTheme fontBodyLarge];

	NSString *sub = item.subtitle;
	if (item.artists.count > 0 && (!sub.length || [sub isEqualToString:item.title])) {
		sub = [item.artists componentsJoinedByString:@", "];
	}
	if (sub.length > 52)
		sub = [NSString stringWithFormat:@"%@…", [sub substringToIndex:52]];
	_subtitleLabel.text = sub;

	if (item.duration > 0) {
		_durationLabel.text = MLFormatDuration(item.duration);
		_durationLabel.textColor = isPlaying ? [MLTheme primary] : [MLTheme onSurfaceVariant];
		_durationLabel.hidden = NO;
	} else {
		_durationLabel.text = @"";
		_durationLabel.hidden = YES;
	}

	BOOL isArtist = (item.kind == MLYTKindArtist || [item.browseId hasPrefix:@"UC"]);
	CGFloat radius = isArtist ? 24.0f : MLRadiusThumbnail;

	if (item.thumbnailUrl.length > 0)
		[MLImageCache loadImageAtURLString:item.thumbnailUrl intoView:_thumb fitSize:_thumb.frame.size cornerRadius:radius placeholder:[MLImageCache placeholderImageWithSize:_thumb.frame.size]];
	else
		_thumb.image = [MLImageCache placeholderImageWithSize:_thumb.frame.size];

	[self setNeedsLayout];
}

- (void)moreTap:(UIButton *)sender
{
	if (_moreTapped && _item)
		_moreTapped(_item);
}

@end
