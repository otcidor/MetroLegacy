#import <UIKit/UIKit.h>
#import "MLAppDelegate.h"

int main(int argc, char *argv[])
{
	@autoreleasepool {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *docsDir = [paths firstObject];
		if (docsDir) {
			[[NSFileManager defaultManager] createDirectoryAtPath:docsDir withIntermediateDirectories:YES attributes:nil error:NULL];
			NSString *logPath = [docsDir stringByAppendingPathComponent:@"MetroLegacy.log"];
			freopen([logPath UTF8String], "a", stderr);
			setvbuf(stderr, NULL, _IOLBF, 0);
			NSLog(@"\n\n=======================================================");
			NSLog(@"=== MetroLegacy Launched === (iOS %@)", [[UIDevice currentDevice] systemVersion]);
			NSLog(@"=======================================================");
		}
		return UIApplicationMain(argc, argv, nil, @"MLAppDelegate");
	}
}
