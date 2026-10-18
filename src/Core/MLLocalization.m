#import "MLLocalization.h"
#import "MLInnerTube.h"

NSString *const MLLanguageChangedNotification = @"MLLanguageChangedNotification";
static NSString *const MLLanguagePrefKey = @"ml_language_pref";

@implementation MLLocalization
{
	NSBundle *_bundle;
	NSBundle *_fallbackBundle;
}

+ (instancetype)sharedManager
{
	static MLLocalization *m = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		m = [[MLLocalization alloc] init];
	});
	return m;
}

- (id)init
{
	self = [super init];
	if (self) {
		NSString *fbPath = [[NSBundle mainBundle] pathForResource:@"es" ofType:@"lproj"];
		if (fbPath) {
			_fallbackBundle = [NSBundle bundleWithPath:fbPath];
		}

		NSString *savedPref = [[NSUserDefaults standardUserDefaults] stringForKey:MLLanguagePrefKey];
		if (!savedPref.length) {
			savedPref = @"auto";
		}
		_languagePreference = [savedPref copy];
		[self applyLanguage];
	}
	return self;
}

- (void)setLanguagePreference:(NSString *)languagePreference
{
	if (!languagePreference.length) {
		languagePreference = @"auto";
	}
	_languagePreference = [languagePreference copy];
	[[NSUserDefaults standardUserDefaults] setObject:_languagePreference forKey:MLLanguagePrefKey];
	[[NSUserDefaults standardUserDefaults] synchronize];

	[self applyLanguage];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLLanguageChangedNotification object:self];
}

- (void)applyLanguage
{
	NSString *effective = nil;
	if ([_languagePreference isEqualToString:@"es"] ||
	    [_languagePreference isEqualToString:@"en"] ||
	    [_languagePreference isEqualToString:@"ru"]) {
		effective = _languagePreference;
	} else {
		// Auto: detect from system preferred languages
		NSArray *prefs = [NSLocale preferredLanguages];
		NSString *first = prefs.count ? [prefs[0] lowercaseString] : @"es";
		if ([first hasPrefix:@"ru"]) {
			effective = @"ru";
		} else if ([first hasPrefix:@"en"]) {
			effective = @"en";
		} else {
			effective = @"es";
		}
	}

	_currentLanguage = [effective copy];

	NSString *bundlePath = [[NSBundle mainBundle] pathForResource:_currentLanguage ofType:@"lproj"];
	if (bundlePath) {
		_bundle = [NSBundle bundleWithPath:bundlePath];
	} else {
		_bundle = _fallbackBundle ?: [NSBundle mainBundle];
	}

	// Synchronize InnerTube API hl and gl parameters
	MLInnerTube *tube = [MLInnerTube sharedClient];
	tube.hl = _currentLanguage;
	if ([_currentLanguage isEqualToString:@"ru"]) {
		tube.gl = @"RU";
	} else if ([_currentLanguage isEqualToString:@"es"]) {
		tube.gl = @"ES";
	} else {
		tube.gl = @"US";
	}
}

- (NSString *)localizedStringForKey:(NSString *)key
{
	if (!key.length)
		return @"";

	NSString *val = [_bundle localizedStringForKey:key value:nil table:nil];
	if (val && ![val isEqualToString:key]) {
		return val;
	}

	if (_fallbackBundle && _fallbackBundle != _bundle) {
		val = [_fallbackBundle localizedStringForKey:key value:nil table:nil];
		if (val && ![val isEqualToString:key]) {
			return val;
		}
	}

	return key;
}

- (NSString *)displayNameForLanguageCode:(NSString *)code
{
	if ([code isEqualToString:@"es"])
		return @"Español";
	if ([code isEqualToString:@"en"])
		return @"English";
	if ([code isEqualToString:@"ru"])
		return @"Русский";
	if ([code isEqualToString:@"auto"])
		return MLLocalizedString(@"lang_auto", nil);
	return code ?: @"";
}

@end
