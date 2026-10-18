#import "MLTokenEditorViewController.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLInnerTube.h"
#import "MLLocalization.h"

@implementation MLTokenEditorViewController
{
	UIScrollView *_scrollView;
	UIView *_infoCard;
	UIView *_btnRow;
	UIButton *_pasteBtn;
	UIButton *_copyBtn;
	UIButton *_clearBtn;
	UIView *_textContainer;
	UITextView *_textView;
	UIActivityIndicatorView *_spinner;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
	return UIStatusBarStyleLightContent;
}

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.backgroundColor = [MLTheme background];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = MLLocalizedString(@"token_editor_title", nil);

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:MLLocalizedString(@"cancel", nil)
	                                                                         style:UIBarButtonItemStylePlain
	                                                                        target:self
	                                                                        action:@selector(cancelTap)];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:MLLocalizedString(@"save", nil)
	                                                                          style:UIBarButtonItemStyleDone
	                                                                         target:self
	                                                                         action:@selector(saveTap)];

	_scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
	_scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_scrollView.alwaysBounceVertical = YES;
	_scrollView.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_scrollView];

	CGFloat w = self.view.bounds.size.width;

	// Info card (M3 style)
	_infoCard = [[UIView alloc] init];
	_infoCard.backgroundColor = [MLTheme surfaceContainer];
	_infoCard.layer.cornerRadius = 12;

	UIImageView *keyIcon = [[UIImageView alloc] initWithFrame:CGRectMake(12, 12, 22, 22)];
	keyIcon.image = [MLIcon icon:@"vpn_key" size:22 color:[MLTheme primary]];
	[_infoCard addSubview:keyIcon];

	UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 12, w - 24 - 50, 22)];
	titleLabel.backgroundColor = [UIColor clearColor];
	titleLabel.font = [MLTheme fontTitleSmall];
	titleLabel.textColor = [MLTheme onSurface];
	titleLabel.text = MLLocalizedString(@"adv_login_title", nil);
	[_infoCard addSubview:titleLabel];

	UILabel *descLabel = [[UILabel alloc] init];
	descLabel.backgroundColor = [UIColor clearColor];
	descLabel.font = [MLTheme fontBodySmall];
	descLabel.textColor = [MLTheme onSurfaceVariant];
	descLabel.numberOfLines = 0;
	descLabel.text = MLLocalizedString(@"adv_login_desc", nil);

	CGSize maxDescSize = CGSizeMake(w - 48, 1000);
	CGSize descSize = [descLabel.text sizeWithFont:descLabel.font constrainedToSize:maxDescSize lineBreakMode:NSLineBreakByWordWrapping];
	descLabel.frame = CGRectMake(12, 40, w - 48, descSize.height);
	[_infoCard addSubview:descLabel];

	CGFloat cardH = 48 + descSize.height;
	_infoCard.frame = CGRectMake(12, 12, w - 24, cardH);
	[_scrollView addSubview:_infoCard];

	// Action buttons row (Paste, Copy, Clear)
	_btnRow = [[UIView alloc] initWithFrame:CGRectMake(12, CGRectGetMaxY(_infoCard.frame) + 10, w - 24, 36)];
	_btnRow.backgroundColor = [UIColor clearColor];

	CGFloat btnW = (w - 24 - 16) / 3.0f;

	_pasteBtn = [self makeButtonWithTitle:MLLocalizedString(@"paste", nil) icon:@"content_paste" frame:CGRectMake(0, 0, btnW, 36) action:@selector(pasteTap)];
	[_btnRow addSubview:_pasteBtn];

	_copyBtn = [self makeButtonWithTitle:MLLocalizedString(@"copy", nil) icon:@"content_copy" frame:CGRectMake(btnW + 8, 0, btnW, 36) action:@selector(copyTap)];
	[_btnRow addSubview:_copyBtn];

	_clearBtn = [self makeButtonWithTitle:MLLocalizedString(@"clear", nil) icon:@"close" frame:CGRectMake((btnW + 8) * 2, 0, btnW, 36) action:@selector(clearTap)];
	[_clearBtn setTitleColor:[MLTheme error] forState:UIControlStateNormal];
	[_btnRow addSubview:_clearBtn];

	[_scrollView addSubview:_btnRow];

	// Text view container
	CGFloat textY = CGRectGetMaxY(_btnRow.frame) + 10;
	CGFloat textH = self.view.bounds.size.height - textY - 20;
	if (textH < 180) textH = 180;

	_textContainer = [[UIView alloc] initWithFrame:CGRectMake(12, textY, w - 24, textH)];
	_textContainer.backgroundColor = [MLTheme surfaceContainer];
	_textContainer.layer.cornerRadius = 12;

	_textView = [[UITextView alloc] initWithFrame:CGRectInset(_textContainer.bounds, 6, 6)];
	_textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_textView.backgroundColor = [UIColor clearColor];
	_textView.textColor = [MLTheme onSurface];
	_textView.font = [UIFont fontWithName:@"Courier" size:12.0f] ?: [UIFont systemFontOfSize:12.0f];
	_textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
	_textView.autocorrectionType = UITextAutocorrectionTypeNo;
	_textView.delegate = self;

	// Prefill
	if ([MLInnerTube sharedClient].loggedIn) {
		_textView.text = [[MLInnerTube sharedClient] exportSessionTokenString];
	} else {
		_textView.text = [NSString stringWithFormat:
			@"***INNERTUBE COOKIE*** =\n"
			@"***VISITOR DATA*** =\n"
			@"***DATASYNC ID*** =\n"
			@"***AUTH USER*** =0\n"
			@"***ACCOUNT NAME*** =\n"
			@"***ACCOUNT EMAIL*** =\n"
			@"***ACCOUNT CHANNEL HANDLE*** ="];
	}

	[_textContainer addSubview:_textView];
	[_scrollView addSubview:_textContainer];

	_scrollView.contentSize = CGSizeMake(w, CGRectGetMaxY(_textContainer.frame) + 20);

	// Keyboard observers
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(keyboardWillShow:)
	                                             name:UIKeyboardWillShowNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(keyboardWillHide:)
	                                             name:UIKeyboardWillHideNotification
	                                           object:nil];
}

- (UIButton *)makeButtonWithTitle:(NSString *)title icon:(NSString *)icon frame:(CGRect)frame action:(SEL)action
{
	UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
	btn.frame = frame;
	btn.backgroundColor = [MLTheme surfaceContainer];
	btn.layer.cornerRadius = 8;
	btn.titleLabel.font = [MLTheme fontTitleSmall];
	[btn setTitle:[NSString stringWithFormat:@" %@", title] forState:UIControlStateNormal];
	[btn setTitleColor:[MLTheme primary] forState:UIControlStateNormal];
	if (icon) {
		[btn setImage:[MLIcon icon:icon size:16 color:[MLTheme primary]] forState:UIControlStateNormal];
	}
	[btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return btn;
}

#pragma mark - Actions

- (void)cancelTap
{
	[self.view endEditing:YES];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)pasteTap
{
	NSString *clip = [UIPasteboard generalPasteboard].string;
	if (clip.length == 0) {
		[[[UIAlertView alloc] initWithTitle:MLLocalizedString(@"clipboard_empty_title", nil)
		                            message:MLLocalizedString(@"clipboard_empty_msg", nil)
		                           delegate:nil
		                  cancelButtonTitle:MLLocalizedString(@"ok", nil)
		                  otherButtonTitles:nil] show];
		return;
	}

	_textView.text = clip;
}

- (void)copyTap
{
	NSString *text = _textView.text;
	if (text.length == 0)
		return;
	[UIPasteboard generalPasteboard].string = text;
	[[[UIAlertView alloc] initWithTitle:MLLocalizedString(@"copied_title", nil)
	                            message:MLLocalizedString(@"copied_msg", nil)
	                           delegate:nil
	                  cancelButtonTitle:MLLocalizedString(@"ok", nil)
	                  otherButtonTitles:nil] show];
}

- (void)clearTap
{
	_textView.text = @"";
}

- (void)saveTap
{
	[self.view endEditing:YES];

	NSString *token = _textView.text;
	NSString *error = nil;
	BOOL ok = [[MLInnerTube sharedClient] importSessionFromTokenString:token error:&error];
	if (!ok) {
		[[[UIAlertView alloc] initWithTitle:MLLocalizedString(@"token_invalid", nil)
		                            message:error ?: MLLocalizedString(@"token_format_error", nil)
		                           delegate:nil
		                  cancelButtonTitle:MLLocalizedString(@"ok", nil)
		                  otherButtonTitles:nil] show];
		return;
	}

	// Disable Save and show activity
	self.navigationItem.rightBarButtonItem.enabled = NO;
	self.navigationItem.title = MLLocalizedString(@"validating_account", nil);

	__weak MLTokenEditorViewController *wself = self;
	[[MLInnerTube sharedClient] accountMenu:^(NSDictionary *accountInfo, NSString *accErr) {
		MLTokenEditorViewController *s = wself;
		if (!s) return;

		NSString *name = accountInfo[@"accountName"] ?: [MLInnerTube sharedClient].accountName;
		if (name.length) {
			NSString *msg = [NSString stringWithFormat:MLLocalizedString(@"signed_in_as", nil), name];
			[[[UIAlertView alloc] initWithTitle:MLLocalizedString(@"success", nil)
			                            message:msg
			                           delegate:nil
			                  cancelButtonTitle:MLLocalizedString(@"ok", nil)
			                  otherButtonTitles:nil] show];
		} else {
			[[[UIAlertView alloc] initWithTitle:MLLocalizedString(@"token_saved_title", nil)
			                            message:MLLocalizedString(@"token_saved_msg", nil)
			                           delegate:nil
			                  cancelButtonTitle:MLLocalizedString(@"ok", nil)
			                  otherButtonTitles:nil] show];
		}

		if (s.completionHandler) {
			s.completionHandler(YES);
		}
		[s dismissViewControllerAnimated:YES completion:nil];
	}];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)note
{
	NSDictionary *info = note.userInfo;
	CGRect kbFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect kbInView = [self.view convertRect:kbFrame fromView:nil];
	CGFloat kbHeight = self.view.bounds.size.height - kbInView.origin.y;
	if (kbHeight < 0) kbHeight = 0;

	UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, kbHeight + 10, 0);
	_scrollView.contentInset = insets;
	_scrollView.scrollIndicatorInsets = insets;

	// Scroll text view to visible
	CGRect textFrame = [_scrollView convertRect:_textContainer.frame fromView:_textContainer.superview];
	[_scrollView scrollRectToVisible:textFrame animated:YES];
}

- (void)keyboardWillHide:(NSNotification *)note
{
	_scrollView.contentInset = UIEdgeInsetsZero;
	_scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

@end
