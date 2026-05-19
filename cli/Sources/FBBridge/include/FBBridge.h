/*
 * FBBridge.h — clean Objective-C facade over the four Meta-licensed iOS
 * automation frameworks (FBControlCore, FBSimulatorControl, FBDeviceControl,
 * XCTestBootstrap). Lets Swift call into the FB stack without inheriting
 * the public headers' transitive references to Apple's private SimDevice /
 * CoreSimulator types (which would otherwise break `import FBSimulatorControl`
 * from Swift because CoreSimulator ships without a Clang module map).
 *
 * Pattern: every method returns BOOL with NSError**, wraps a synchronous-
 * waited FBFuture<T>, and exposes only Foundation types in the public API.
 *
 * Status (1.2.0): listSimulators + boot + shutdown + erase implemented.
 * UI automation, XCTest, device control land in follow-up sessions.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBBridge : NSObject

/// One-time bootstrap: load Apple private SPIs (CoreSimulator, SimulatorKit, etc.)
/// that the FB frameworks dlopen on demand. Must be called once per process
/// before any other FBBridge method. Idempotent.
+ (BOOL)bootstrapWithError:(NSError * _Nullable * _Nullable)error;

/// Returns the same data shape SimctlBackend produces, sourced via
/// FBSimulatorControl rather than `xcrun simctl list`. Each dict carries:
///   udid: NSString
///   name: NSString
///   runtime: NSString    (e.g. "iOS 26.4")
///   deviceType: NSString (e.g. "iPhone 17 Pro")
///   state: NSString      ("Booted", "Shutdown", "Creating", ...)
+ (nullable NSArray<NSDictionary<NSString *, NSString *> *> *)listSimulatorsWithError:
    (NSError * _Nullable * _Nullable)error;

/// Boot a simulator by UDID. Idempotent: already-booted sims succeed silently.
+ (BOOL)bootSimulatorWithUDID:(NSString *)udid error:(NSError * _Nullable * _Nullable)error;

/// Shut down a simulator by UDID. Idempotent.
+ (BOOL)shutdownSimulatorWithUDID:(NSString *)udid error:(NSError * _Nullable * _Nullable)error;

/// Erase a simulator. Destructive — wipes the device's data container.
+ (BOOL)eraseSimulatorWithUDID:(NSString *)udid error:(NSError * _Nullable * _Nullable)error;

// MARK: - App lifecycle

/// Install a built `.app` bundle on a simulator. Returns the bundle id.
+ (nullable NSString *)installAppAtPath:(NSString *)appPath
                            onSimulator:(NSString *)udid
                                  error:(NSError * _Nullable * _Nullable)error;

/// Uninstall an app by bundle id.
+ (BOOL)uninstallBundleID:(NSString *)bundleID
              onSimulator:(NSString *)udid
                    error:(NSError * _Nullable * _Nullable)error;

/// Launch an app with optional env / arguments. Returns the PID wrapped in
/// an NSNumber (so Swift sees a `throws` method via the nullable+NSError pattern).
+ (nullable NSNumber *)launchBundleID:(NSString *)bundleID
                          onSimulator:(NSString *)udid
                            arguments:(NSArray<NSString *> *)arguments
                          environment:(NSDictionary<NSString *, NSString *> *)environment
                      waitForDebugger:(BOOL)waitForDebugger
                                error:(NSError * _Nullable * _Nullable)error;

/// Terminate a running app by bundle id.
+ (BOOL)killBundleID:(NSString *)bundleID
         onSimulator:(NSString *)udid
               error:(NSError * _Nullable * _Nullable)error;

// MARK: - UI automation (FBSimulatorHID)

/// Tap at point coordinates (no @2x scaling).
+ (BOOL)tapAtX:(double)x
             y:(double)y
   onSimulator:(NSString *)udid
         error:(NSError * _Nullable * _Nullable)error;

/// Swipe from (x1,y1) to (x2,y2). Delta = pixel step per intermediate event.
+ (BOOL)swipeFromX:(double)x1
                y:(double)y1
              toX:(double)x2
                y:(double)y2
         duration:(double)durationSeconds
      onSimulator:(NSString *)udid
            error:(NSError * _Nullable * _Nullable)error;

// MARK: - XCTest (XCTestBootstrap)

/// List test cases in an `.xctest` bundle. Pass `hostAppPath` for app-hosted
/// bundles (the test bundle's `@rpath/Host.dylib` references resolve through
/// the host app's `Frameworks/` dir); pass nil for pure logic-test bundles.
/// Returns an array of "ClassName/testMethod" strings.
+ (nullable NSArray<NSString *> *)listTestsInBundleAtPath:(NSString *)bundlePath
                                              hostAppPath:(nullable NSString *)hostAppPath
                                              onSimulator:(NSString *)udid
                                                  timeout:(double)timeoutSeconds
                                                    error:(NSError * _Nullable * _Nullable)error;

/// Event payload pushed to the runTests caller. One of:
///   `kind` = `"suiteStarted"`, `"suiteFinished"`, `"caseStarted"`,
///            `"casePassed"`, `"caseFailed"`, `"runFinished"`
/// `name` = test class + "/" + method, or suite name
/// `duration` = elapsed seconds (case/suite events only)
/// `message` = failure message (caseFailed only)
typedef void (^FBBridgeTestEventBlock)(NSDictionary<NSString *, id> *event);

/// Run an `.xctest` bundle to completion.
///
/// - `hostAppPath`: for app-hosted unit tests, the host `.app`. For UI tests,
///   the test-runner `.app` (e.g. `MyAppUITests-Runner.app`). For pure logic
///   bundles, pass nil.
/// - `targetAppPath`: for UI tests, the app being driven (e.g. `MyApp.app`).
///   Nil for unit tests.
/// - `uiTesting`: pass YES for XCUITest bundles. Sets
///   FBTestLaunchConfiguration.initializeUITesting.
/// - `testsToRun`: filter set (empty = run all).
+ (BOOL)runTestsInBundleAtPath:(NSString *)bundlePath
                   hostAppPath:(nullable NSString *)hostAppPath
                 targetAppPath:(nullable NSString *)targetAppPath
                     uiTesting:(BOOL)uiTesting
                    testsToRun:(NSSet<NSString *> *)testsToRun
                   onSimulator:(NSString *)udid
                       timeout:(double)timeoutSeconds
                       onEvent:(FBBridgeTestEventBlock)onEvent
                         error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
