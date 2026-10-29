#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#define ML_EQ_NUM_BANDS 10

extern NSString *const MLEqualizerDidChangeNotification;

@interface MLEQPreset : NSObject

@property (nonatomic, copy) NSString *presetId;
@property (nonatomic, copy) NSString *nameKey;
@property (nonatomic, copy) NSArray *bandGains; // Array of 10 NSNumbers (float dB)

+ (instancetype)presetWithId:(NSString *)presetId nameKey:(NSString *)nameKey gains:(NSArray *)gains;

@end

@interface MLEqualizerManager : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSString *currentPresetId;
@property (nonatomic, readonly) NSArray *presets; // Array of MLEQPreset

+ (instancetype)sharedManager;

// Band configuration (10 bands: 31Hz, 62Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz)
- (NSInteger)numberOfBands;
- (float)frequencyForBand:(NSInteger)bandIndex;
- (NSString *)frequencyStringForBand:(NSInteger)bandIndex;
- (NSString *)shortFrequencyStringForBand:(NSInteger)bandIndex;
- (float)gainForBand:(NSInteger)bandIndex;
- (void)setGain:(float)gainDb forBand:(NSInteger)bandIndex;
- (NSArray *)allBandGains;
- (void)setAllBandGains:(NSArray *)gains;

// Presets (21 TuneShell calibrated presets + Flat + Custom)
- (void)applyPresetWithId:(NSString *)presetId;
- (NSString *)currentPresetLocalizedName;
- (void)resetToFlat;

// Audio tap attachment to player item
- (void)attachEqualizerToPlayerItem:(AVPlayerItem *)playerItem;

// Visualizer waveform data (reads recent post-EQ samples, range -1.0 to 1.0)
- (void)getScopeData:(float *)outBuffer length:(NSUInteger)len;

@end
