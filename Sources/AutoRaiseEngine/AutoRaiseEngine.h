#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Configuration for one AutoRaise engine session. Field meanings mirror the AutoRaise CLI
/// parameters (see README of the original project).
@interface AutoRaiseConfig : NSObject
@property (nonatomic) NSInteger pollMillis;          // >= 20, default 50
@property (nonatomic) NSInteger delay;               // 0 = no raise, 1 = no delay, n = (n-1)*pollMillis
@property (nonatomic) NSInteger focusDelay;          // FOCUS_FIRST only; 0 = disabled
@property (nonatomic) float warpX;                   // 0..1
@property (nonatomic) float warpY;                   // 0..1
@property (nonatomic) float scale;                   // cursor scale after warp (>= 1)
@property (nonatomic) BOOL warpEnabled;              // warp mouse on cmd-tab / cmd-grave
@property (nonatomic) BOOL altTaskSwitcher;
@property (nonatomic) BOOL requireMouseStop;
@property (nonatomic) BOOL ignoreSpaceChanged;
@property (nonatomic) BOOL invertDisableKey;
@property (nonatomic) BOOL invertIgnoreApps;
@property (nonatomic, copy, nullable) NSString *ignoreApps;            // comma-separated
@property (nonatomic, copy, nullable) NSString *ignoreTitles;         // comma-separated regexes
@property (nonatomic, copy, nullable) NSString *stayFocusedBundleIds; // comma-separated
@property (nonatomic, copy, nullable) NSString *disableKey;           // "control" | "option" | "disabled"
@property (nonatomic) float mouseDelta;              // 0 = most sensitive
@property (nonatomic) BOOL verbose;
@end

/// Controllable wrapper around the AutoRaise focus-follows-mouse engine. The engine uses
/// process-global state, so only one may run at a time (Quiver creates exactly one). `start`/`stop`
/// install and fully tear down the CGEventTap, AX observers, workspace notifications, and poll timer
/// on the current (main) run loop, so it can be toggled repeatedly without leaking or crashing.
@interface AutoRaiseEngine : NSObject

/// YES if the binary was compiled with the experimental FOCUS_FIRST (focus-before-raise) support.
@property (class, readonly) BOOL focusFirstAvailable;

/// Accessibility permission helpers.
+ (BOOL)isAccessibilityTrusted;
+ (BOOL)promptAccessibility;              // triggers the system "grant Accessibility" prompt
+ (void)openAccessibilitySettings;        // opens System Settings → Privacy → Accessibility

- (BOOL)isRunning;
- (void)startWithConfig:(AutoRaiseConfig *)config NS_SWIFT_NAME(start(config:));
- (void)stop;

@end

NS_ASSUME_NONNULL_END
