/*
 * FBBridge.m — clean ObjC facade over the Meta FB frameworks.
 *
 * Pattern:
 *   1. Bootstrap private SPIs via FBSimulatorControlFrameworkLoader.essentialFrameworks
 *   2. Hand out a cached FBSimulatorControl (constructed via +withConfiguration:error:),
 *      which exposes .set (FBSimulatorSet) — that's the entry point to .allSimulators
 *      and per-sim operations
 *   3. For each public method, find the FBSimulator by UDID, call the FBFuture-returning
 *      operation, synchronously await with awaitWithTimeout, bridge errors out
 */

#import "FBBridge.h"

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControlFrameworkLoader.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

// Selector exposed by FBSimulator's private surface (visible as a string in
// FBSimulatorControl). Declared here so we can call it without a compile
// warning; if a future framework drop drops the accessor we fall back to a
// runtime probe in the host-launch env builder below.
@interface FBSimulator (FBBridgePrivateRuntime)
@property (nonatomic, copy, readonly) NSString *runtimeRootDirectory;
@end

// FBXCTestReporter implementation — forwards events to a Swift block.
@interface FBBridgeReporter : NSObject <FBXCTestReporter>
@property (nonatomic, copy) FBBridgeTestEventBlock onEvent;
@property (nonatomic, strong) NSDate *runStart;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *caseStart;
- (instancetype)initWithBlock:(FBBridgeTestEventBlock)block;
@end

@implementation FBBridge

static FBSimulatorControl *gControl = nil;
static BOOL gBootstrapped = NO;
static NSError *gBootstrapError = nil;

+ (BOOL)bootstrapWithError:(NSError **)error {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Our build of facebook/idb applies scripts/patches/idb-xcode-select-macos26.patch
        // so the framework falls back to `xcode-select -p` when /var/db/xcode_select_link
        // is missing (macOS 26+). No precondition check needed here.
        id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
        NSError *loadErr = nil;
        // essentialFrameworks loads CoreSimulator. xcodeFrameworks loads
        // SimulatorKit (which holds the HID classes). Both are needed for the
        // full surface we expose.
        if (![FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworks:logger error:&loadErr]) {
            gBootstrapError = loadErr;
            return;
        }
        if (![FBSimulatorControlFrameworkLoader.xcodeFrameworks loadPrivateFrameworks:logger error:&loadErr]) {
            gBootstrapError = loadErr;
            return;
        }
        gBootstrapped = YES;
    });
    if (!gBootstrapped) {
        if (error) *error = gBootstrapError ?: [NSError errorWithDomain:@"FBBridge" code:1 userInfo:@{NSLocalizedDescriptionKey: @"bootstrap failed"}];
        return NO;
    }
    return YES;
}

+ (nullable FBSimulatorControl *)controlWithError:(NSError **)error {
    if (![self bootstrapWithError:error]) return nil;
    if (gControl) return gControl;
    FBSimulatorControlConfiguration *config = [FBSimulatorControlConfiguration
        configurationWithDeviceSetPath:nil
        logger:FBControlCoreGlobalConfiguration.defaultLogger
        reporter:nil];
    NSError *ctlErr = nil;
    gControl = [FBSimulatorControl withConfiguration:config error:&ctlErr];
    if (!gControl) {
        if (error) *error = ctlErr ?: [NSError errorWithDomain:@"FBBridge" code:2 userInfo:@{NSLocalizedDescriptionKey: @"FBSimulatorControl construction failed"}];
        return nil;
    }
    return gControl;
}

#pragma mark - listSimulators

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)listSimulatorsWithError:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return nil;
    NSArray<FBSimulator *> *sims = control.set.allSimulators;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:sims.count];
    for (FBSimulator *sim in sims) {
        NSString *udid = sim.udid ?: @"";
        NSString *name = sim.name ?: @"";
        NSString *state = FBiOSTargetStateStringFromState(sim.state) ?: @"";
        NSString *runtime = sim.osVersion.name ?: @"";
        NSString *deviceType = sim.deviceType.model ?: @"";
        [out addObject:@{
            @"udid": udid,
            @"name": name,
            @"state": state,
            @"runtime": runtime,
            @"deviceType": deviceType
        }];
    }
    return out;
}

#pragma mark - per-sim helpers

+ (FBSimulator *)findSimulatorWithUDID:(NSString *)udid control:(FBSimulatorControl *)control {
    for (FBSimulator *sim in control.set.allSimulators) {
        if ([sim.udid isEqualToString:udid]) return sim;
    }
    return nil;
}

+ (BOOL)bootSimulatorWithUDID:(NSString *)udid error:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return NO;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return NO;
    }
    if (sim.state == FBiOSTargetStateBooted) return YES;
    FBFuture *future = [sim boot:FBSimulatorBootConfiguration.defaultConfiguration];
    NSError *waitErr = nil;
    [future awaitWithTimeout:120.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return NO;
    }
    return YES;
}

+ (BOOL)shutdownSimulatorWithUDID:(NSString *)udid error:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return NO;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return NO;
    }
    if (sim.state == FBiOSTargetStateShutdown) return YES;
    FBFuture *future = [sim shutdown];
    NSError *waitErr = nil;
    [future awaitWithTimeout:60.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return NO;
    }
    return YES;
}

+ (BOOL)eraseSimulatorWithUDID:(NSString *)udid error:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return NO;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return NO;
    }
    FBFuture *future = [sim erase];
    NSError *waitErr = nil;
    [future awaitWithTimeout:60.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return NO;
    }
    return YES;
}

#pragma mark - App lifecycle

+ (nullable NSString *)installAppAtPath:(NSString *)appPath
                            onSimulator:(NSString *)udid
                                  error:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return nil;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return nil;
    }
    FBFuture<FBInstalledApplication *> *future = [sim installApplicationWithPath:appPath];
    NSError *waitErr = nil;
    FBInstalledApplication *result = [future awaitWithTimeout:120.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return nil;
    }
    return result.bundle.identifier ?: @"";
}

+ (BOOL)uninstallBundleID:(NSString *)bundleID
              onSimulator:(NSString *)udid
                    error:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return NO;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return NO;
    }
    FBFuture *future = [sim uninstallApplicationWithBundleID:bundleID];
    NSError *waitErr = nil;
    [future awaitWithTimeout:60.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return NO;
    }
    return YES;
}

+ (nullable NSNumber *)launchBundleID:(NSString *)bundleID
                          onSimulator:(NSString *)udid
                            arguments:(NSArray<NSString *> *)arguments
                          environment:(NSDictionary<NSString *, NSString *> *)environment
                      waitForDebugger:(BOOL)waitForDebugger
                                error:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return nil;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return nil;
    }
    FBApplicationLaunchConfiguration *config = [[FBApplicationLaunchConfiguration alloc]
        initWithBundleID:bundleID
        bundleName:nil
        arguments:arguments ?: @[]
        environment:environment ?: @{}
        waitForDebugger:waitForDebugger
        io:[FBProcessIO outputToDevNull]
        launchMode:FBApplicationLaunchModeRelaunchIfRunning];
    FBFuture<id<FBLaunchedApplication>> *future = [sim launchApplication:config];
    NSError *waitErr = nil;
    id<FBLaunchedApplication> app = [future awaitWithTimeout:60.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return nil;
    }
    return @(app.processIdentifier);
}

+ (BOOL)killBundleID:(NSString *)bundleID
         onSimulator:(NSString *)udid
               error:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return NO;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return NO;
    }
    FBFuture *future = [sim killApplicationWithBundleID:bundleID];
    NSError *waitErr = nil;
    [future awaitWithTimeout:30.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return NO;
    }
    return YES;
}

#pragma mark - UI automation

/// Cache the per-simulator HID connection so consecutive UI events don't
/// reconnect. Key: simulator UDID. Reset when boot state changes.
static NSMutableDictionary<NSString *, FBSimulatorHID *> *gHIDCache = nil;

+ (nullable FBSimulatorHID *)hidForUDID:(NSString *)udid error:(NSError **)error {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gHIDCache = [NSMutableDictionary dictionary]; });
    @synchronized (gHIDCache) {
        if (gHIDCache[udid]) return gHIDCache[udid];
    }
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return nil;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return nil;
    }
    if (sim.state != FBiOSTargetStateBooted) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:6 userInfo:@{NSLocalizedDescriptionKey: @"simulator must be booted before UI events"}];
        return nil;
    }
    FBFuture<FBSimulatorHID *> *future = [sim connectToHID];
    NSError *waitErr = nil;
    FBSimulatorHID *hid = [future awaitWithTimeout:10.0 error:&waitErr];
    if (!hid) {
        if (error) *error = waitErr ?: [NSError errorWithDomain:@"FBBridge" code:7 userInfo:@{NSLocalizedDescriptionKey: @"HID connect failed"}];
        return nil;
    }
    @synchronized (gHIDCache) { gHIDCache[udid] = hid; }
    return hid;
}

+ (BOOL)tapAtX:(double)x y:(double)y onSimulator:(NSString *)udid error:(NSError **)error {
    FBSimulatorHID *hid = [self hidForUDID:udid error:error];
    if (!hid) return NO;
    id<FBSimulatorHIDEventComposite> event = [FBSimulatorHIDEvent tapAtX:x y:y];
    FBFuture *future = [event performOnHID:hid];
    NSError *waitErr = nil;
    [future awaitWithTimeout:5.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return NO;
    }
    return YES;
}

+ (BOOL)swipeFromX:(double)x1 y:(double)y1 toX:(double)x2 y:(double)y2
         duration:(double)durationSeconds onSimulator:(NSString *)udid error:(NSError **)error {
    FBSimulatorHID *hid = [self hidForUDID:udid error:error];
    if (!hid) return NO;
    // Delta is the per-step distance in points. 10pt steps give smooth scrolls.
    id<FBSimulatorHIDEventProtocol> event = [FBSimulatorHIDEvent
        swipe:x1 yStart:y1 xEnd:x2 yEnd:y2 delta:10.0 duration:durationSeconds];
    FBFuture *future = [event performOnHID:hid];
    NSError *waitErr = nil;
    [future awaitWithTimeout:durationSeconds + 5.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return NO;
    }
    return YES;
}

#pragma mark - XCTest listing

+ (nullable NSArray<NSString *> *)listTestsInBundleAtPath:(NSString *)bundlePath
                                              hostAppPath:(nullable NSString *)hostAppPath
                                              onSimulator:(NSString *)udid
                                                  timeout:(double)timeoutSeconds
                                                    error:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return nil;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return nil;
    }
    FBFuture<NSArray *> *future = [sim listTestsForBundleAtPath:bundlePath
                                                        timeout:timeoutSeconds
                                                  withAppAtPath:hostAppPath];
    NSError *waitErr = nil;
    NSArray *names = [future awaitWithTimeout:timeoutSeconds + 10.0 error:&waitErr];
    if (!names) {
        if (error) *error = waitErr ?: [NSError errorWithDomain:@"FBBridge" code:8 userInfo:@{NSLocalizedDescriptionKey: @"listTests returned nil"}];
        return nil;
    }
    return names;
}

#pragma mark - XCTest run

/// Idempotent install: if the bundle id at appPath is already installed and
/// resolves at the same path, skip; otherwise (re-)install. The
/// FBManagedTestRunStrategy / FBTestRunnerConfiguration pipeline looks up
/// `installedApplication(bundleID:)` and uses its on-disk bundle to derive
/// `Frameworks/` search paths, so the runner + target app must both be
/// installed on the simulator before runTest can succeed.
+ (BOOL)ensureInstalled:(FBBundleDescriptor *)bundle
            onSimulator:(FBSimulator *)sim
                 logger:(id<FBControlCoreLogger>)logger
                  error:(NSError **)error {
    if (!bundle || !bundle.identifier || bundle.identifier.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:10 userInfo:@{NSLocalizedDescriptionKey: @"bundle has no identifier"}];
        return NO;
    }
    NSString *bundleId = bundle.identifier;
    [logger log:[NSString stringWithFormat:@"FBBridge.ensureInstalled: bundle=%@ path=%@", bundleId, bundle.path]];
    FBFuture<FBInstalledApplication *> *installedFuture = [sim installedApplicationWithBundleID:bundleId];
    NSError *checkErr = nil;
    FBInstalledApplication *existing = [installedFuture awaitWithTimeout:15.0 error:&checkErr];
    if (existing && [existing.bundle.path isEqualToString:bundle.path]) {
        [logger log:[NSString stringWithFormat:@"FBBridge.ensureInstalled: %@ already installed at same path, skipping", bundleId]];
        return YES;
    }
    // Either not installed, installed at a different path (stale), or the
    // lookup errored. In all cases install (the simctl device install is
    // idempotent and overwrites the existing record). This is what `idb` does
    // in CompanionLib/FBIDBStorageManager.swift.
    [logger log:[NSString stringWithFormat:@"FBBridge.ensureInstalled: installing %@ from %@", bundleId, bundle.path]];
    FBFuture<FBInstalledApplication *> *installFuture = [sim installApplicationWithPath:bundle.path];
    NSError *installErr = nil;
    FBInstalledApplication *installed = [installFuture awaitWithTimeout:120.0 error:&installErr];
    if (!installed) {
        if (error) *error = installErr ?: [NSError errorWithDomain:@"FBBridge" code:11 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"install of %@ failed", bundleId]}];
        return NO;
    }
    [logger log:[NSString stringWithFormat:@"FBBridge.ensureInstalled: %@ installed OK", bundleId]];
    return YES;
}

+ (BOOL)runTestsInBundleAtPath:(NSString *)bundlePath
                   hostAppPath:(nullable NSString *)hostAppPath
                 targetAppPath:(nullable NSString *)targetAppPath
                     uiTesting:(BOOL)uiTesting
                    testsToRun:(NSSet<NSString *> *)testsToRun
                   onSimulator:(NSString *)udid
                       timeout:(double)timeoutSeconds
                       onEvent:(FBBridgeTestEventBlock)onEvent
                         error:(NSError **)error {
    FBSimulatorControl *control = [self controlWithError:error];
    if (!control) return NO;
    FBSimulator *sim = [self findSimulatorWithUDID:udid control:control];
    if (!sim) {
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no simulator with UDID %@", udid]}];
        return NO;
    }
    id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;

    NSError *bundleErr = nil;
    FBBundleDescriptor *testBundle = [FBBundleDescriptor bundleFromPath:bundlePath error:&bundleErr];
    if (!testBundle) {
        if (error) *error = bundleErr ?: [NSError errorWithDomain:@"FBBridge" code:9 userInfo:@{NSLocalizedDescriptionKey: @"could not read .xctest bundle"}];
        return NO;
    }

    // The host app is the process that LOADS the .xctest bundle. For UI tests
    // it's the *UITests-Runner.app; for app-hosted unit tests it's the host
    // application. Pure logic tests have no host (we don't support that path
    // through FBManagedTestRunStrategy — those go via FBListTestStrategy /
    // FBLogicTestRunStrategy upstream). The runner is launched by
    // FBManagedTestRunStrategy via `installedApplication(bundleID:)`, so it
    // MUST be installed on the simulator before we hand off.
    FBBundleDescriptor *hostBundle = nil;
    FBApplicationLaunchConfiguration *hostLaunch = nil;
    if (hostAppPath) {
        hostBundle = [FBBundleDescriptor bundleFromPath:hostAppPath error:&bundleErr];
        if (!hostBundle) {
            if (error) *error = bundleErr ?: [NSError errorWithDomain:@"FBBridge" code:9 userInfo:@{NSLocalizedDescriptionKey: @"could not read host .app bundle"}];
            return NO;
        }
        if (![self ensureInstalled:hostBundle onSimulator:sim logger:logger error:error]) {
            return NO;
        }
        // applicationLaunchConfiguration.bundleID MUST be the runner's bundle
        // id. FBTestRunnerConfiguration.prepareConfiguration looks it up via
        // installedApplication(bundleID:) to derive the runner binary, framework
        // search paths, and the launch environment (XCTestConfigurationFilePath,
        // DYLD_INSERT_LIBRARIES of libShimulator.dylib, etc.).
        //
        // Build the canonical host-app launch environment. Without these vars
        // (which `xcodebuild test` injects), storekitd rejects every
        // SKTestSession mutation with SKInternalErrorDomain Code=3, the test
        // hangs, and XCTestBootstrap eventually reports "host application
        // process stalled". Values mirror the .xctestrun produced by
        // `xcodebuild build-for-testing` for app-hosted unit test targets.
        NSMutableDictionary<NSString *, NSString *> *env = [NSMutableDictionary dictionary];
        env[@"APP_DISTRIBUTOR_ID_OVERRIDE"]              = @"com.apple.AppStore";
        env[@"OS_ACTIVITY_DT_MODE"]                      = @"YES";
        env[@"TERM"]                                     = @"dumb";
        env[@"SQLITE_ENABLE_THREAD_ASSERTIONS"]          = @"1";
        env[@"PERFC_ENABLE_EXTENDED_DIAGNOSTIC_FORMAT"]  = @"1";
        env[@"PERFC_ENABLE_PROFILE_MODE"]                = @"1";
        env[@"PERFC_RESET_INSERT_LIBRARIES"]             = @"1";
        env[@"PERFC_SUPPRESS_SYSTEM_REPORTS"]            = @"1";
        if (!uiTesting) {
            // App-hosted unit-test path. Inject the bundle-inject dylib + DYLD
            // paths so storekitd sees the XCTest client-environment-type marker
            // and so XCTest's own framework search paths resolve from inside
            // the host app.
            NSString *platformDir = [hostAppPath stringByDeletingLastPathComponent];
            NSString *developerDir = NSProcessInfo.processInfo.environment[@"DEVELOPER_DIR"];
            if (developerDir.length == 0) {
                NSTask *xcs = [[NSTask alloc] init];
                NSPipe *outPipe = [NSPipe pipe];
                xcs.launchPath = @"/usr/bin/xcode-select";
                xcs.arguments = @[@"-p"];
                xcs.standardOutput = outPipe;
                @try { [xcs launch]; [xcs waitUntilExit]; } @catch (NSException *e) {}
                NSData *outData = [outPipe.fileHandleForReading readDataToEndOfFile];
                developerDir = [[[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding]
                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            }
            if (developerDir.length == 0) developerDir = @"/Applications/Xcode.app/Contents/Developer";
            NSString *platforms = [developerDir stringByAppendingPathComponent:@"Platforms"];
            NSString *simRuntimeRoot = @"";
            if ([sim respondsToSelector:@selector(runtimeRootDirectory)]) {
                simRuntimeRoot = sim.runtimeRootDirectory ?: @"";
            }

            NSString *injectDylib = [hostAppPath stringByAppendingPathComponent:@"Frameworks/libXCTestBundleInject.dylib"];
            NSString *mtcDylib = simRuntimeRoot.length > 0
                ? [simRuntimeRoot stringByAppendingPathComponent:@"usr/lib/libMainThreadChecker.dylib"]
                : nil;
            NSMutableArray<NSString *> *inserts = [NSMutableArray array];
            if ([NSFileManager.defaultManager fileExistsAtPath:injectDylib]) {
                [inserts addObject:injectDylib];
            }
            if (mtcDylib && [NSFileManager.defaultManager fileExistsAtPath:mtcDylib]) {
                [inserts addObject:mtcDylib];
            }
            [inserts addObject:@"/usr/lib/libRPAC.dylib"];

            env[@"DYLD_INSERT_LIBRARIES"]               = [inserts componentsJoinedByString:@":"];
            env[@"DYLD_FRAMEWORK_PATH"]                 = [NSString stringWithFormat:@"%@:%@/PackageFrameworks:%@/iPhoneSimulator.platform/Developer/Library/Frameworks", platformDir, platformDir, platforms];
            env[@"DYLD_LIBRARY_PATH"]                   = [NSString stringWithFormat:@"%@:%@/iPhoneSimulator.platform/Developer/usr/lib", platformDir, platforms];
            env[@"XCInjectBundleInto"]                  = @"unused";
            env[@"XCODE_SCHEME_NAME"]                   = hostBundle.name ?: @"";
            env[@"XCODE_TEST_PLAN_NAME"]                = hostBundle.name ?: @"";
            env[@"__XCODE_BUILT_PRODUCTS_DIR_PATHS"]    = platformDir;
            env[@"__XPC_DYLD_FRAMEWORK_PATH"]           = platformDir;
            env[@"__XPC_DYLD_LIBRARY_PATH"]             = platformDir;
        }
        hostLaunch = [[FBApplicationLaunchConfiguration alloc]
            initWithBundleID:hostBundle.identifier ?: @""
                  bundleName:hostBundle.name
                   arguments:@[]
                 environment:env
             waitForDebugger:NO
                          io:[FBProcessIO outputToDevNull]
                  launchMode:FBApplicationLaunchModeRelaunchIfRunning];
    } else {
        // No host app — we can't run app-hosted or UI tests this way. The
        // managed run strategy is only for app-hosted execution; pure logic
        // tests need a different entry point that we don't expose here yet.
        if (error) *error = [NSError errorWithDomain:@"FBBridge" code:12 userInfo:@{NSLocalizedDescriptionKey: @"runTestsInBundleAtPath requires hostAppPath (logic-only tests not supported via this entry point)"}];
        return NO;
    }

    // For UI tests, the target app (the one being driven by XCUIApplication)
    // is separate from the runner. It must also be installed so that:
    //   1. testApplicationDependencies in the .xctestconfiguration resolves
    //   2. _XCT_launchProcessWithPath:bundleID: from the runner can launch it
    //   3. its Frameworks/ are reachable
    FBBundleDescriptor *targetBundle = nil;
    if (targetAppPath) {
        targetBundle = [FBBundleDescriptor bundleFromPath:targetAppPath error:&bundleErr];
        if (!targetBundle) {
            if (error) *error = bundleErr ?: [NSError errorWithDomain:@"FBBridge" code:9 userInfo:@{NSLocalizedDescriptionKey: @"could not read target .app bundle"}];
            return NO;
        }
        if (![self ensureInstalled:targetBundle onSimulator:sim logger:logger error:error]) {
            return NO;
        }
    }

    // Both UI and app-hosted unit tests go through the DIRECT DTX path
    // (useXcodebuild: NO). This mirrors idb's canonical flow in
    // CompanionLib/FBXCTestDescriptor.swift (FBXCTestBootstrapDescriptor): UI
    // tests are configured with `initializeUITesting: true, useXcodebuild:
    // false`. The xcodebuild path (useXcodebuild: YES) is ONLY used when the
    // caller supplies a pre-baked .xctestrun via FBXCodebuildTestRunDescriptor.
    // Upstream's FBXcodeBuildOperation.xctestRunProperties writes a "StubBundleId"
    // placeholder dict that xcodebuild can't actually consume, so we cannot
    // synthesize one from FBTestLaunchConfiguration fields alone — that path
    // is broken for any caller who doesn't already have a real .xctestrun.
    FBTestLaunchConfiguration *launchConfig = [[FBTestLaunchConfiguration alloc]
        initWithTestBundle:testBundle
        applicationLaunchConfiguration:hostLaunch
        testHostBundle:hostBundle
        timeout:timeoutSeconds
        initializeUITesting:uiTesting
        useXcodebuild:NO
        testsToRun:(testsToRun.count > 0 ? testsToRun : nil)
        testsToSkip:nil
        targetApplicationBundle:targetBundle
        xcTestRunProperties:nil
        resultBundlePath:nil
        reportActivities:YES
        coverageDirectoryPath:nil
        enableContinuousCoverageCollection:NO
        logDirectoryPath:nil
        reportResultBundle:NO];

    [logger log:[NSString stringWithFormat:@"FBBridge.runTests: host=%@ target=%@ uiTesting=%d filters=%lu",
        hostBundle.identifier ?: @"(none)",
        targetBundle.identifier ?: @"(none)",
        uiTesting ? 1 : 0,
        (unsigned long)testsToRun.count]];

    FBBridgeReporter *reporter = [[FBBridgeReporter alloc] initWithBlock:onEvent];

    FBFuture<NSNull *> *future = [sim runTestWithLaunchConfiguration:launchConfig
                                                            reporter:reporter
                                                              logger:logger];
    NSError *waitErr = nil;
    [future awaitWithTimeout:timeoutSeconds + 30.0 error:&waitErr];
    if (waitErr) {
        if (error) *error = waitErr;
        return NO;
    }
    return YES;
}

@end

// MARK: - FBBridgeReporter

@implementation FBBridgeReporter

- (instancetype)initWithBlock:(FBBridgeTestEventBlock)block {
    self = [super init];
    if (self) {
        _onEvent = [block copy];
        _runStart = [NSDate date];
        _caseStart = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid {}
- (void)didBeginExecutingTestPlan {}
- (void)didFinishExecutingTestPlan {}
- (void)processUnderTestDidExit {}

- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime {
    self.onEvent(@{@"kind": @"suiteStarted", @"name": testSuite ?: @""});
}

- (void)testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method {
    NSString *name = [NSString stringWithFormat:@"%@/%@", testClass ?: @"", method ?: @""];
    self.caseStart[name] = [NSDate date];
    self.onEvent(@{@"kind": @"caseStarted", @"name": name});
}

- (void)testCaseDidFinishForTestClass:(NSString *)testClass
                               method:(NSString *)method
                           withStatus:(FBTestReportStatus)status
                             duration:(NSTimeInterval)duration
                                 logs:(NSArray<NSString *> *)logs {
    NSString *name = [NSString stringWithFormat:@"%@/%@", testClass ?: @"", method ?: @""];
    NSString *kind = (status == FBTestReportStatusPassed) ? @"casePassed" :
                     (status == FBTestReportStatusFailed) ? @"caseFailed" : @"caseSkipped";
    NSMutableDictionary *evt = [@{@"kind": kind, @"name": name, @"duration": @(duration)} mutableCopy];
    if (logs.count > 0) evt[@"logs"] = logs;
    self.onEvent(evt);
    [self.caseStart removeObjectForKey:name];
}

- (void)testCaseDidFailForTestClass:(NSString *)testClass
                             method:(NSString *)method
                         exceptions:(NSArray<FBExceptionInfo *> *)exceptions {
    NSString *name = [NSString stringWithFormat:@"%@/%@", testClass ?: @"", method ?: @""];
    NSMutableString *msg = [NSMutableString string];
    for (FBExceptionInfo *e in exceptions) {
        if (msg.length) [msg appendString:@"\n"];
        [msg appendString:e.message ?: @""];
        if (e.file) [msg appendFormat:@" (%@:%lu)", e.file, (unsigned long)e.line];
    }
    self.onEvent(@{@"kind": @"caseFailureDetails", @"name": name, @"message": msg ?: @""});
}

- (void)finishedWithSummary:(FBTestManagerResultSummary *)summary {
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.runStart];
    NSInteger total = summary.runCount;
    NSInteger failed = summary.failureCount;
    NSInteger passed = total - failed;
    if (passed < 0) passed = 0;
    NSDictionary *evt = @{
        @"kind": @"runFinished",
        @"passed": @(passed),
        @"failed": @(failed),
        @"duration": @(elapsed),
    };
    self.onEvent(evt);
}

- (void)testHadOutput:(NSString *)output {
    if (output.length == 0) return;
    self.onEvent(@{@"kind": @"output", @"message": output});
}
- (void)handleExternalEvent:(NSString *)event {}
- (BOOL)printReportWithError:(NSError **)error { return YES; }
- (void)didCrashDuringTest:(NSError *)err {
    self.onEvent(@{@"kind": @"runCrashed", @"message": err.localizedDescription ?: @"unknown crash"});
}

// MARK: - Optional FBXCTestReporter (attachments + activities)

- (void)testCase:(NSString *)testClass method:(NSString *)method willStartActivity:(FBActivityRecord *)activity {
    NSString *name = [NSString stringWithFormat:@"%@/%@", testClass ?: @"", method ?: @""];
    self.onEvent(@{
        @"kind": @"activityStarted",
        @"name": name,
        @"activityTitle": activity.title ?: @"",
        @"activityType": activity.activityType ?: @""
    });
}

- (void)testCase:(NSString *)testClass method:(NSString *)method didFinishActivity:(FBActivityRecord *)activity {
    NSString *name = [NSString stringWithFormat:@"%@/%@", testClass ?: @"", method ?: @""];
    NSMutableArray *attachments = [NSMutableArray array];
    for (FBAttachment *a in activity.attachments) {
        NSMutableDictionary *att = [@{} mutableCopy];
        if (a.name) att[@"name"] = a.name;
        if (a.uniformTypeIdentifier) att[@"uti"] = a.uniformTypeIdentifier;
        if (a.payload) att[@"sizeBytes"] = @(a.payload.length);
        [attachments addObject:att];
    }
    NSDictionary *evt = @{
        @"kind": @"activityFinished",
        @"name": name,
        @"activityTitle": activity.title ?: @"",
        @"activityType": activity.activityType ?: @"",
        @"duration": @(activity.duration),
        @"attachments": attachments
    };
    self.onEvent(evt);
}

- (void)testPlanDidFailWithMessage:(NSString *)message {
    self.onEvent(@{@"kind": @"testPlanFailed", @"message": message ?: @""});
}

- (void)didRecordVideoAtPath:(NSString *)videoRecordingPath {
    self.onEvent(@{@"kind": @"videoRecorded", @"path": videoRecordingPath ?: @""});
}

- (void)didSaveOSLogAtPath:(NSString *)osLogPath {
    self.onEvent(@{@"kind": @"osLogSaved", @"path": osLogPath ?: @""});
}

- (void)didCopiedTestArtifact:(NSString *)artifactName toPath:(NSString *)path {
    self.onEvent(@{@"kind": @"artifactSaved", @"name": artifactName ?: @"", @"path": path ?: @""});
}

@end
