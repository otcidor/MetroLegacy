#import "MLListenTogetherViewController.h"
#import "MLTheme.h"
#import "MLLocalization.h"

@interface MLListenTogetherViewController ()
{
	UILabel *_label;
}
@end

@implementation MLListenTogetherViewController

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.view.backgroundColor = [MLTheme background];

	_label = [[UILabel alloc] initWithFrame:CGRectMake(20, 160, self.view.bounds.size.width - 40, 60)];
	_label.font = [MLTheme fontBodyLarge];
	_label.textColor = [MLTheme onSurfaceVariant];
	_label.textAlignment = NSTextAlignmentCenter;
	_label.numberOfLines = 3;
	_label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:_label];

	[self updateLocalizedStrings];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(updateLocalizedStrings)
	                                             name:MLLanguageChangedNotification
	                                           object:nil];
}

- (void)updateLocalizedStrings
{
	self.title = MLLocalizedString(@"listen_together_title", nil);
	_label.text = MLLocalizedString(@"listen_together_soon", nil);
}

@end
