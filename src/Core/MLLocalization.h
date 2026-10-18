#import <Foundation/Foundation.h>

extern NSString *const MLLanguageChangedNotification;

#define MLLocalizedString(key, comment) [[MLLocalization sharedManager] localizedStringForKey:(key)]

@interface MLLocalization : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, copy, readonly) NSString *currentLanguage; // @"es", @"en", @"ru"
@property (nonatomic, copy) NSString *languagePreference;        // @"auto", @"es", @"en", @"ru"

- (NSString *)localizedStringForKey:(NSString *)key;
- (NSString *)displayNameForLanguageCode:(NSString *)code;

@end
