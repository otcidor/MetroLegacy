#import "MLLyricsView.h"
#import "MLTheme.h"
#import "MLLocalization.h"

@interface MLLyricsCell : UITableViewCell
@property (nonatomic, strong) UILabel *lyricLabel;
- (void)setText:(NSString *)text active:(BOOL)active synced:(BOOL)synced;
@end

@implementation MLLyricsCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		_lyricLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_lyricLabel.backgroundColor = [UIColor clearColor];
		_lyricLabel.numberOfLines = 0;
		_lyricLabel.textAlignment = NSTextAlignmentCenter;
		[self.contentView addSubview:_lyricLabel];
	}
	return self;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	_lyricLabel.frame = CGRectMake(20.0f, 6.0f, self.contentView.bounds.size.width - 40.0f, self.contentView.bounds.size.height - 12.0f);
}

- (void)setText:(NSString *)text active:(BOOL)active synced:(BOOL)synced
{
	_lyricLabel.text = text;
	if (!synced) {
		_lyricLabel.font = [UIFont systemFontOfSize:16.0f];
		_lyricLabel.textColor = [MLTheme onSurface];
		_lyricLabel.alpha = 0.90f;
	} else if (active) {
		_lyricLabel.font = [UIFont boldSystemFontOfSize:19.0f];
		_lyricLabel.textColor = [UIColor whiteColor];
		_lyricLabel.alpha = 1.0f;
	} else {
		_lyricLabel.font = [UIFont systemFontOfSize:16.0f];
		_lyricLabel.textColor = [MLTheme onSurfaceVariant];
		_lyricLabel.alpha = 0.40f;
	}
}

@end

@implementation MLLyricsView
{
	UITableView *_tableView;
	UILabel *_statusLabel;
	UIActivityIndicatorView *_spinner;
	NSArray *_lines;
	NSInteger _currentLineIndex;
	NSString *_currentVideoId;
	BOOL _userIsDragging;
}

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		_currentLineIndex = -1;

		_tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
		_tableView.backgroundColor = [UIColor clearColor];
		_tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
		_tableView.showsVerticalScrollIndicator = NO;
		_tableView.dataSource = self;
		_tableView.delegate = self;
		_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		if ([_tableView respondsToSelector:@selector(setEstimatedRowHeight:)]) {
			[_tableView setValue:@0 forKey:@"estimatedRowHeight"];
		}
		[self addSubview:_tableView];

		_statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(24.0f, 0, frame.size.width - 48.0f, frame.size.height)];
		_statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_statusLabel.backgroundColor = [UIColor clearColor];
		_statusLabel.textColor = [MLTheme onSurfaceVariant];
		_statusLabel.textAlignment = NSTextAlignmentCenter;
		_statusLabel.font = [MLTheme fontBodyMedium];
		_statusLabel.numberOfLines = 0;
		_statusLabel.hidden = YES;
		[self addSubview:_statusLabel];

		_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
		_spinner.center = CGPointMake(frame.size.width / 2.0f, frame.size.height / 2.0f);
		_spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
		                            UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
		_spinner.hidesWhenStopped = YES;
		[self addSubview:_spinner];
	}
	return self;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGFloat h = self.bounds.size.height;
	if (h > 0) {
		UIEdgeInsets insets = UIEdgeInsetsMake(floorf(h * 0.35f), 0, ceilf(h * 0.55f), 0);
		if (!UIEdgeInsetsEqualToEdgeInsets(_tableView.contentInset, insets)) {
			_tableView.contentInset = insets;
		}
	}
}

- (BOOL)hasLyrics
{
	return _lines.count > 0;
}

- (void)clear
{
	_currentVideoId = nil;
	_lines = @[];
	_currentLineIndex = -1;
	_isSynced = NO;
	_statusLabel.hidden = YES;
	[_spinner stopAnimating];
	[_tableView reloadData];
}

- (void)loadLyricsForTitle:(NSString *)title
                    artist:(NSString *)artist
                  duration:(CGFloat)duration
                   videoId:(NSString *)videoId
{
	if ([videoId isEqualToString:_currentVideoId] && _lines.count > 0) {
		return;
	}

	[self clear];
	_currentVideoId = [videoId copy];
	_statusLabel.text = MLLocalizedString(@"lyrics_loading", nil);
	_statusLabel.hidden = NO;
	[_spinner startAnimating];

	__weak typeof(self) weakSelf = self;
	[[MLLyricsManager sharedManager] fetchLyricsForTitle:title
	                                              artist:artist
	                                            duration:duration
	                                             videoId:videoId
	                                          completion:^(NSArray *lines, BOOL synced, NSString *error) {
		MLLyricsView *s = weakSelf;
		if (!s || ![s->_currentVideoId isEqualToString:videoId]) return;
		[s->_spinner stopAnimating];
		s->_lines = lines ?: @[];
		s->_isSynced = synced;
		s->_currentLineIndex = -1;

		if (lines.count > 0) {
			s->_statusLabel.hidden = YES;
			[s->_tableView reloadData];
			[s updateContentInsets];
		} else {
			s->_statusLabel.text = MLLocalizedString(@"lyrics_not_found", nil);
			s->_statusLabel.hidden = NO;
			[s->_tableView reloadData];
		}
	}];
}

- (void)updateContentInsets
{
	CGFloat h = self.bounds.size.height;
	if (h > 0) {
		_tableView.contentInset = UIEdgeInsetsMake(floorf(h * 0.35f), 0, ceilf(h * 0.55f), 0);
	}
}

- (void)updateCurrentPlaybackTime:(CGFloat)currentTime
{
	if (!_isSynced || !_lines.count || _userIsDragging) {
		return;
	}

	NSInteger ms = (NSInteger)(currentTime * 1000.0f) + 300;
	NSInteger lineIdx = -1;
	for (NSUInteger i = 0; i < _lines.count; i++) {
		MLLyricLine *l = _lines[i];
		if (l.timeMs <= ms) {
			lineIdx = (NSInteger)i;
		} else {
			break;
		}
	}

	if (lineIdx != _currentLineIndex && lineIdx >= 0 && lineIdx < (NSInteger)_lines.count) {
		_currentLineIndex = lineIdx;
		[_tableView reloadData];
		NSIndexPath *ip = [NSIndexPath indexPathForRow:lineIdx inSection:0];
		[_tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
	}
}

#pragma mark - ScrollView & Dragging

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
	_userIsDragging = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
	if (!decelerate) {
		_userIsDragging = NO;
	}
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
	_userIsDragging = NO;
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _lines.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	MLLyricLine *line = _lines[indexPath.row];
	NSString *text = line.text ?: @"";
	CGSize max = CGSizeMake(self.bounds.size.width - 40.0f, CGFLOAT_MAX);
	UIFont *font = (indexPath.row == _currentLineIndex && _isSynced) ? [UIFont boldSystemFontOfSize:19.0f] : [UIFont systemFontOfSize:16.0f];
	CGSize sz = [text sizeWithFont:font constrainedToSize:max lineBreakMode:NSLineBreakByWordWrapping];
	return MAX(44.0f, sz.height + 18.0f);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *const CellId = @"MLLyricCell";
	MLLyricsCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
	if (!cell) {
		cell = [[MLLyricsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellId];
	}

	MLLyricLine *line = _lines[indexPath.row];
	BOOL active = (indexPath.row == _currentLineIndex);
	[cell setText:line.text active:active synced:_isSynced];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.row < (NSInteger)_lines.count) {
		MLLyricLine *line = _lines[indexPath.row];
		if (_isSynced && line.timeMs >= 0 && _onSeekRequested) {
			_onSeekRequested(line.timeMs / 1000.0f);
		}
	}
}

@end
