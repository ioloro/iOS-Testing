enum Examples {
    static let simList = """
    # List every available simulator
    iostesting sim list

    # Just iOS 26
    iostesting sim list --runtime "iOS 26"

    # Only booted devices, as JSON
    iostesting sim list --state Booted --json
    """

    static let simBoot = """
    # By name
    iostesting sim boot "iPhone 17 Pro"

    # By UDID
    iostesting sim boot B3AC0B66-4AB6-471B-A9BA-D1CC78670018

    # Idempotent — already-booted sims succeed silently
    """

    static let simShutdown = """
    iostesting sim shutdown "iPhone 17 Pro"
    iostesting sim shutdown <udid> --json
    """

    static let simErase = """
    # Destructive — wipes all data on the sim
    iostesting sim erase "iPhone 17 Pro"
    """

    static let simCreate = """
    iostesting sim create \\
      --name "Test iPhone" \\
      --device-type "iPhone 17 Pro" \\
      --runtime "iOS26.4"
    """

    static let simPrune = """
    # Removes simulators marked unavailable (typically left from old Xcode versions)
    iostesting sim prune
    """

    static let simMediaAdd = """
    # Inject a single photo
    iostesting sim media-add -s "iPhone 17 Pro" ./fixtures/test.jpg

    # Multiple files
    iostesting sim media-add -s "iPhone 17 Pro" ./a.jpg ./b.jpg ./video.mov
    """

    static let simLocation = """
    # Set a single point
    iostesting sim location -s "iPhone 17 Pro" --set "37.7749,-122.4194"

    # Clear (revert to default/real)
    iostesting sim location -s "iPhone 17 Pro" --clear

    # Replay a GPX track. Default interval=1s between points, default cap=1500.
    iostesting sim location -s "iPhone 17 Pro" --gpx ./round.gpx

    # Faster replay, more points
    iostesting sim location -s "iPhone 17 Pro" --gpx ./round.gpx --interval 0.25 --max-waypoints 5000

    # What's currently happening?
    iostesting sim location -s "iPhone 17 Pro" --status
    iostesting sim location -s "iPhone 17 Pro" --status --json
    """

    static let simEnv = """
    # Set a launchd env var (newly-launched apps inherit it)
    iostesting sim env -s "iPhone 17 Pro" --set DEWY_CI_DEV_TOKEN=abc123

    # Set multiple at once
    iostesting sim env -s "iPhone 17 Pro" \\
      --set API_HOST=http://localhost:3000 --set FEATURE_FOO=1

    # Unset
    iostesting sim env -s "iPhone 17 Pro" --unset DEWY_CI_DEV_TOKEN

    # Background: these shell to `simctl spawn <udid> launchctl setenv KEY VALUE`.
    # Existing processes are NOT affected — relaunch the app after setting.
    """

    static let simButton = """
    iostesting sim button -s "iPhone 17 Pro" home
    iostesting sim button -s "iPhone 17 Pro" lock
    iostesting sim button -s "iPhone 17 Pro" siri
    """

    static let simAppearance = """
    iostesting sim appearance -s "iPhone 17 Pro" light
    iostesting sim appearance -s "iPhone 17 Pro" dark

    # Take screenshots of both for visual regression:
    iostesting sim appearance light && iostesting screenshot -o light.png
    iostesting sim appearance dark  && iostesting screenshot -o dark.png
    """

    static let simOpenURL = """
    # Universal link
    iostesting sim open-url -s "iPhone 17 Pro" https://example.com/path

    # Custom scheme
    iostesting sim open-url -s "iPhone 17 Pro" myapp://reset-password?token=abc
    """

    static let install = """
    iostesting install -s "iPhone 17 Pro" ./build/Debug-iphonesimulator/MyApp.app
    """

    static let uninstall = """
    iostesting uninstall -s "iPhone 17 Pro" com.example.MyApp

    # With config defaults, no flags needed:
    iostesting config set --sim "iPhone 17 Pro" --bundle-id com.example.MyApp
    iostesting uninstall
    """

    static let launch = """
    # Basic launch
    iostesting launch -s "iPhone 17 Pro" com.example.MyApp

    # With launch args + env
    iostesting launch -s "iPhone 17 Pro" com.example.MyApp \\
      --arg --UITesting --arg --skipOnboarding \\
      --env API_HOST=http://localhost:3000

    # Wait for debugger
    iostesting launch -s "iPhone 17 Pro" com.example.MyApp --wait-for-debugger
    """

    static let stop = """
    # By short ID from `iostesting apps`
    iostesting stop abc1f2

    # By bundle id (uses config sim)
    iostesting stop com.example.MyApp

    # By PID
    iostesting stop -s "iPhone 17 Pro" 12345
    """

    static let logs = """
    # All logs from the sim
    iostesting logs -s "iPhone 17 Pro"

    # Filter to one app
    iostesting logs -s "iPhone 17 Pro" --bundle-id com.example.MyApp

    # Short ID from `iostesting apps` resolves sim + bundle automatically
    iostesting logs --bundle-id abc1f2

    # NDJSON for piping
    iostesting logs --bundle-id com.example.MyApp --json | jq '.message'

    # Raw NSPredicate
    iostesting logs -s "iPhone 17 Pro" --predicate 'eventMessage CONTAINS "Error"'
    """

    static let screenshot = """
    iostesting screenshot -s "iPhone 17 Pro" -o ./shot.png

    # Default output is ./screenshot.png
    iostesting screenshot
    """

    static let appsList = """
    iostesting apps list
    iostesting apps list --all          # include terminated
    iostesting apps list --json
    """

    static let appsPrune = """
    iostesting apps prune
    """

    static let deviceList = """
    iostesting device list
    iostesting device list --json
    """

    static let deviceInstall = """
    iostesting device install -d <device-id> ./build/MyApp.ipa
    """

    static let deviceLaunch = """
    iostesting device launch -d <device-id> com.example.MyApp
    """

    static let testList = """
    iostesting test list ./build/Debug-iphonesimulator/MyAppTests.xctest
    """

    static let testRun = """
    # Run every test in a bundle on the saved sim
    iostesting test run ./build/MyAppTests.xctest

    # Filter by suite/method (repeatable)
    iostesting test run ./build/MyAppTests.xctest \\
      --filter MyParserTests/testValid \\
      --filter MyParserTests/testInvalid

    # NDJSON event stream for agents
    iostesting test run ./build/MyAppTests.xctest --json

    # Bump the post-test termination wait (default 120s, max 600s). Useful when
    # the host app holds background subscriptions or in-flight requests that
    # delay clean shutdown.
    IOSTESTING_BACKEND=fb iostesting test run ./build/MyAppUITests-Runner.app/PlugIns/MyAppUITests.xctest \\
      --termination-timeout 300

    # Bridge a sim env var into launchd before the runner boots (newly-launched
    # apps inherit it). Repeatable. Equivalent to `iostesting sim env --set ...`
    # then `test run`.
    iostesting test run ./build/MyAppUITests.xctest \\
      --sim-env DEWY_CI_DEV_TOKEN=abc123 --sim-env FEATURE_FOO=1

    # Pre-grant location-always BEFORE the runner launches. Pre-empts iOS 26's
    # "Allow X to ALSO use your location even when you are not using the app?"
    # upgrade prompt — SpringBoard-owned, XCUITest's addUIInterruptionMonitor
    # cannot catch it. `all-location` grants both `location` AND `location-always`.
    IOSTESTING_BACKEND=fb iostesting test run \\
      ./build/MyAppUITests-Runner.app/PlugIns/MyAppUITests.xctest \\
      --privacy-grant all-location

    # Belt-and-suspenders: pre-grant privacy AND run a background watcher that
    # OCRs the screen every 2s and taps system prompts as they fire. Catches the
    # subset of modals that simctl-grant can't suppress (e.g. tracking, notifs).
    IOSTESTING_BACKEND=fb iostesting test run \\
      ./build/MyAppUITests-Runner.app/PlugIns/MyAppUITests.xctest \\
      --privacy-grant all-location \\
      --auto-dismiss-alerts \\
      --termination-timeout 300

    # Custom dismiss labels (defaults cover the common iOS prompts).
    IOSTESTING_BACKEND=fb iostesting test run ./MyUITests.xctest \\
      --auto-dismiss-alerts \\
      --auto-dismiss-label "Keep Only While Using" \\
      --auto-dismiss-label "Allow"

    # Default backend (simctl) runs logic tests only. For app-hosted XCTest +
    # Swift Testing bundles, set IOSTESTING_BACKEND=fb.
    """

    static let configShow = """
    iostesting config show
    iostesting config show --json
    """

    static let configSet = """
    # Project (writes ./.iostesting/config.json):
    iostesting config set --sim "iPhone 17 Pro" --bundle-id com.example.MyApp

    # Global (writes ~/.config/iostesting/config.json):
    iostesting config set --global --sim "iPhone 17 Pro"

    # CI: skip the file and set env vars instead
    IOSTESTING_SIM="iPhone 17 Pro" IOSTESTING_BUNDLE_ID=com.example.MyApp iostesting test run ...
    """

    static let configGet = """
    iostesting config get sim
    iostesting config get bundleId
    """

    static let configReset = """
    iostesting config reset           # project
    iostesting config reset --global  # global
    """

    static let licenses = """
    iostesting licenses
    """

    static let clean = """
    # DerivedData (default)
    iostesting clean

    # Dry-run to see what'd be touched
    iostesting clean --all --dry-run

    # Targeted cleans
    iostesting clean --registry            # just ~/Library/Application Support/iostesting/
    iostesting clean --project-config      # just ./.iostesting/
    iostesting clean --all                 # everything iostesting + Xcode
    """

    static let setup = """
    # First-time setup. Merges iostesting permissions into ~/.claude/settings.json.
    # Run once after installing the @ioloro/ios-testing plugin to stop the
    # Claude Code permission prompts for xcrun simctl spawn, swift build, etc.
    iostesting setup

    # Preview the changes without writing
    iostesting setup --dry-run

    # See exactly what file would be written
    iostesting setup --print

    # Test against a different settings file
    iostesting setup --path ./test-settings.json

    # JSON output for scripting (records added + alreadyPresent)
    iostesting setup --json

    # Idempotent. Running twice is a no-op the second time.
    """

    static let context = """
    # In a directory containing .xcodeproj or .xcworkspace
    iostesting context
    iostesting context --json

    # Point at a specific project
    iostesting context --project ./MyApp.xcodeproj
    """

    static let uiTap = """
    # Requires IOSTESTING_BACKEND=fb and a booted simulator.
    IOSTESTING_BACKEND=fb iostesting ui tap --x 200 --y 400
    IOSTESTING_BACKEND=fb iostesting ui tap -s "iPhone 17 Pro" --x 200 --y 400
    """

    static let uiSwipe = """
    # Scroll down 400pt
    IOSTESTING_BACKEND=fb iostesting ui swipe --x1 200 --y1 600 --x2 200 --y2 200

    # Slow swipe (1 second)
    IOSTESTING_BACKEND=fb iostesting ui swipe --x1 0 --y1 400 --x2 400 --y2 400 --duration 1.0
    """

    static let privacyGrant = """
    # Pre-empt iOS 26's "Allow X to ALSO use your location even when you are not
    # using the app?" upgrade prompt — SpringBoard-owned, addUIInterruptionMonitor
    # cannot catch it. Grant both `location` AND `location-always` AFTER the app
    # is installed (locationd needs the bundle path to write the auth record).
    iostesting privacy grant --all-location com.example.MyApp

    # Single service
    iostesting privacy grant location-always com.example.MyApp
    iostesting privacy grant photos com.example.MyApp
    iostesting privacy grant microphone com.example.MyApp

    # All recognized services: all, calendar, contacts, contacts-limited,
    # location, location-always, photos, photos-add, media-library,
    # microphone, motion, reminders, siri
    """

    static let privacyRevoke = """
    iostesting privacy revoke location-always com.example.MyApp
    iostesting privacy revoke photos com.example.MyApp
    """

    static let privacyReset = """
    # Reset every grant for one app (next request will prompt)
    iostesting privacy reset all com.example.MyApp

    # Reset device-wide (drop the bundle id)
    iostesting privacy reset all

    # Reset just the location grants
    iostesting privacy reset location com.example.MyApp
    """

    static let alertsDismiss = """
    # One-shot: screenshot + OCR + tap. Returns exit 0 on a match, 2 on none.
    # Default labels include "Keep Only While Using" (iOS 26 location upgrade
    # prompt), "Allow While Using App", "Don't Allow", "OK", "Allow".
    IOSTESTING_BACKEND=fb iostesting alerts dismiss

    # Custom label — taps the first button whose OCR'd text contains this.
    IOSTESTING_BACKEND=fb iostesting alerts dismiss --label "Allow"
    IOSTESTING_BACKEND=fb iostesting alerts dismiss --label "Keep Only While Using"

    # JSON output for scripting
    IOSTESTING_BACKEND=fb iostesting alerts dismiss --json
    """

    static let alertsWatch = """
    # Background watcher: poll the sim every 2s for system alerts; tap any
    # matching button. Catches SpringBoard-owned modals XCUITest's
    # addUIInterruptionMonitor misses. Defaults: duration=600s, interval=2.0s.
    IOSTESTING_BACKEND=fb iostesting alerts watch &
    WATCHER=$!
    # ... run your tests ...
    kill $WATCHER

    # Bounded duration + JSON event stream
    IOSTESTING_BACKEND=fb iostesting alerts watch --duration 120 --json

    # Only watch for the location-upgrade prompt
    IOSTESTING_BACKEND=fb iostesting alerts watch --label "Keep Only While Using"

    # Prefer the integrated path: `test run --auto-dismiss-alerts` spawns this
    # watcher for you and tears it down when the test finishes.
    """
}
