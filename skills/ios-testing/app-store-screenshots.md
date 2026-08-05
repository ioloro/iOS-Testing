# App Store Screenshot Pipeline

An end-to-end, runnable playbook for generating App Store screenshots from an
iOS app: drive the app through every interesting visual state with XCUITest,
capture deterministic PNGs with a `9:41` status bar, extract them from the
`.xcresult`, and composite them into framed store tiles with a baked headline.

This is app-agnostic. The worked example throughout is **Top3** (a SwiftUI +
SwiftData app), but the shape transfers to any app: an XCUITest matrix harness,
launch-arg-driven deterministic seeding, `simctl` status-bar override, an
`xcresulttool` extraction step, and a PIL framing script.

The core idea: **the app itself renders every screenshot** (real UI, real
fonts, real theme), so the harness only decides *which state* to show and
*when* to snap. Framing is a thin cosmetic layer on top of true captures.

## Pipeline at a Glance

```
XCUITest matrix          simctl status_bar          xcresulttool export       PIL framing
Config × ScreenKind  →   9:41 / wifi / 100%    →     UUID → slug/screen.png →  store tiles
(launch args seed        (set on booted sim,        (manifest maps names)     (1320×2868,
 the app state)           before the run)                                      baked headline)
```

Four stages, each independently re-runnable:

1. **Capture** — an XCUITest iterates a config matrix, drives the app via launch
   args, saves each `XCUIScreenshot` as an xcresult attachment.
2. **Status bar** — override the simulator status bar to `9:41` etc. *before*
   the run so every capture shows the canonical clock.
3. **Extract** — pull attachments out of the newest `.xcresult`, mapping UUID
   filenames back to `slug/screen.png`.
4. **Frame** — composite raw captures onto store-sized canvases with a headline,
   brand ground, and device bezel.

---

## Stage 1 — The Capture Harness

### Harness shape

A single XCUITest iterates a `Config` (theme × accent × mode × font, or whatever
your app's personalization axes are) crossed with a `ScreenKind` enum. For each
combination it relaunches a fresh `XCUIApplication` with the right launch args,
lets the app settle, snaps `app.screenshot()`, and adds the PNG as an
`XCTAttachment` named `<platform>__<slug>__<screen>.png` (the `__` separators
expand into directories at extraction time).

```swift
final class ScreenshotMatrixUITests: XCTestCase {
    struct Config: Sendable {
        let theme: String, accent: String, mode: String, font: String
        var slug: String { "\(theme)_\(accent)_\(mode)_\(font)" }
    }

    enum ScreenKind: String, CaseIterable {
        case todayEmpty = "today_empty"
        case todayComplete = "today_complete"
        case settings, appearance
        case shareToday = "share_today"
        // ... one case per interesting visual state
    }

    // Hand-pick a matrix that touches each axis without exploding to the full
    // cartesian product. Top3's full cross would be 6·5·3·4 = 360 configs; the
    // curated matrix is 15 configs × ~14 screens ≈ 180 captures.
    static let matrix: [Config] = { /* themes sweep + mode swing + accent swing + font swing */ }()
}
```

**Keep it one test method, not one-per-screen.** Each `func test_...` pays the
full fixed cost (simulator boot, app install) again. ~180 captures in a single
`testCaptureMatrix()` loop is far cheaper than 180 methods. Persist the manifest
after *each* capture so a mid-run crash still leaves a usable partial.

**Write a tiny smoke test first.** Before committing 20+ minutes to the full
matrix, prove the harness end-to-end on one config × three screens:

```swift
@MainActor func testSmokeCapture() throws {
    let cfg = Config(theme: "modern", accent: "iris", mode: "dark", font: "plusJakartaSans")
    for screen in [ScreenKind.todayEmpty, .todayLocked, .settings] {
        try captureScreen(screen, config: cfg)
    }
    try writeManifest()
}
```

Run it with `-only-testing:AppUITests/ScreenshotMatrixUITests/testSmokeCapture`.

### Per-capture flow

```swift
@MainActor private func captureScreen(_ screen: ScreenKind, config: Config) throws {
    let app = XCUIApplication()
    app.launchArguments = launchArgs(for: screen, config: config)
    app.launch()
    defer { app.terminate() }   // tear down on every exit path

    // Drive to the target state using accessibility identifiers, never
    // localized display text. waitForExistence guards each step.
    // ... navigate / wait ...

    // Share sheets render a card preview through ImageRenderer, which needs a
    // beat longer than a plain view.
    let settle: TimeInterval = (screen == .shareToday) ? 1.8 : 0.4
    Thread.sleep(forTimeInterval: settle)

    let png = app.screenshot().pngRepresentation
    let path = "ios/\(config.slug)/\(screen.rawValue).png"
    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
    attachment.name = path.replacingOccurrences(of: "/", with: "__")  // ios__slug__screen.png
    attachment.lifetime = .keepAlways
    add(attachment)
}
```

`XCUIScreenshot` includes the status bar, so the `9:41` override (Stage 2) must
be in place before this runs.

### Config scoping: the `TEST_RUNNER_` env-forwarding gotcha

To heal a partial matrix run (say, five configs failed), you want to re-run only
those slugs. The test reads an env var:

```swift
let envConfigs = ProcessInfo.processInfo.environment["SCREENSHOT_CONFIGS"]
if let envConfigs, !envConfigs.isEmpty {
    let wanted = Set(envConfigs.split(separator: ",").map(String.init))
    configsToRun = Self.matrix.filter { wanted.contains($0.slug) }  // only matches existing slugs
}
```

**`xcodebuild` does NOT forward shell env vars to the UI-test runner process.**
Setting `SCREENSHOT_CONFIGS=...` on the command line lands it as a *build
setting*, which the runner never sees. The working form is the `TEST_RUNNER_`
prefix — `xcodebuild` strips `TEST_RUNNER_` and injects the remainder into the
runner's environment:

```bash
xcodebuild test-without-building \
  -only-testing:AppUITests/ScreenshotMatrixUITests/testCaptureMatrix \
  TEST_RUNNER_SCREENSHOT_CONFIGS=modern_cyan_dark_plusJakartaSans,leather_iris_dark_plusJakartaSans \
  ...
```

The filter only matches slugs already present in the test's `matrix` — it can
scope down, never inject new configs.

---

## Stage 2 — The 9:41 Status Bar

App Store screenshots use a clean status bar: `9:41`, full WiFi, 100% battery.
Override it on the **booted simulator** with `simctl`:

```bash
xcrun simctl status_bar <udid> override \
  --time "9:41" \
  --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100
```

The override lives on the booted sim and is **cleared by a reboot**. This is the
single most common way to silently capture wall-clock time instead of `9:41`: if
you let `xcodebuild test` boot or reboot the simulator, it wipes your override
before the captures happen.

### Reliable ordering

Split build from run so you control the boot:

```bash
UDID=<your-sim-udid>

# 1. Build the test bundle (does not need the sim booted).
xcodebuild build-for-testing -scheme App \
  -destination "id=$UDID" -derivedDataPath ./DerivedData

# 2. Boot the sim yourself, THEN set the override.
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi \
  --wifiBars 3 --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100

# 3. Run WITHOUT building, pinned to that exact booted sim.
xcodebuild test-without-building -scheme App \
  -destination "id=$UDID" -derivedDataPath ./DerivedData \
  -only-testing:AppUITests/ScreenshotMatrixUITests/testCaptureMatrix
```

`test-without-building` on the already-booted `id=<udid>` reuses your sim and
keeps the override intact. Never use a name-only destination here — it can boot a
*different* clone and reboot away your status bar.

---

## Stage 3 — Deterministic Seeding

Screenshots must show fixed, hand-crafted content, not whatever happens to be in
the store. Drive state through launch args, and seed the data layer **before the
SwiftUI scene renders** so `@Query` reflects the seed on the first frame.

### Seed before first render

Invoke the seeder once from `App.init()` (before `AppPreferences.shared` or any
`@Query` reads). Theme/accent/mode/font overrides must land in the App Group
`UserDefaults` here too, or the app reads the old theme before you override it
and the screenshot lands in the wrong appearance:

```swift
// UITestSupport.configureIfNeeded(), called first thing in App.init()
if let theme = value(after: "-UITestMode_Theme", in: args) {
    defaults.set(theme, forKey: "preferences.themeID")   // wins because it runs first
}
// ... accent / mode / font ...
if let seed = value(after: "-UITestMode_Seed", in: args) {
    UITestSeed.applySeed(seed)   // writes SwiftData rows before the scene exists
}
```

### Wipe ALL prior rows for full-history seeds

Per-day seeds (a "today" state) only need to clear today's rows. But a
**full-history seed** — e.g. a year of streak data for a yearly summary card —
must wipe **every** prior row first, not just today's:

```swift
case .year:
    // Full reseed: clear ALL FocusItems. wipeToday() only clears today, so
    // without this a re-run ACCUMULATES duplicate per-day rows — and days that
    // now hold 6 items instead of 3 stop matching the "exactly 3 complete = hit"
    // classifier, silently degrading from "hit" to "attempted".
    if let existing = try? context.fetch(FetchDescriptor<FocusItem>()) {
        for item in existing { context.delete(item) }
    }
    // ... then write today + 365 days of history ...
```

This is a subtle correctness trap: the build still succeeds, the screenshot
still renders — it's just *wrong*, and only in a way you'd catch by counting
heatmap cells. **Uninstall the app between seed-shape changes** for a clean
slate rather than trusting the wipe.

### Auto-presenting transient UI

Some screens (share sheets, modals) can't be reached by a deterministic tap
sequence — the element isn't reliably hittable across OS versions. Auto-present
them via a dedicated launch arg and give them a longer settle:

```swift
static var shouldAutoOpenShareToday: Bool {
    ProcessInfo.processInfo.arguments.contains("-UITestMode_OpenShareToday")
}
```

For the **full-bleed share artifact** (the actual thing users share, not a
screenshot of the sheet), export it directly with SwiftUI `ImageRenderer` behind
an export flag, write it to the app's Documents dir, then pull it from the
simulator container:

```swift
let renderer = ImageRenderer(content: shareCard)
renderer.scale = 2                        // 2× for crisp text
if let ui = renderer.uiImage, let png = ui.pngData() {
    try? png.write(to: documentsURL.appendingPathComponent("share_today_card.png"))
}
```

```bash
CONTAINER=$(xcrun simctl get_app_container <udid> <bundle-id> data)
cp "$CONTAINER/Documents/share_today_card.png" ./cards/
```

### The `fileSystemSynchronizedGroup` landmine

**Write screenshots OUTSIDE the app target's source tree.** Top3 writes to a
repo-root `screenshots/` directory — a *sibling* of `Top3/`, not inside it.

If PNGs land under a folder covered by an Xcode `fileSystemSynchronizedGroup`,
the build ingests them as bundle resources. Two configs that both produce a
`today_empty.png` then collide on the same resource name and **break the build**.
Keeping the output tree outside any synchronized group avoids this entirely.

---

## Stage 4 — Extraction

`app.screenshot()` attachments live inside the `.xcresult` bundle under UUID
filenames. `xcresulttool` exports them plus a manifest mapping each UUID to its
`suggestedHumanReadableName` (your `ios__slug__screen.png`, with an Xcode-appended
`_<idx>_<uuid>` suffix).

An extraction script points at the newest `*.xcresult` under DerivedData (or a
path you pass), exports attachments, strips the Xcode suffix, and expands `__`
back into directories:

```bash
# Top3/Scripts/extract_screenshots.sh [path/to/result.xcresult]
xcrun xcresulttool export attachments --path "$XCRESULT" --output-path "$EXPORT_DIR"
# then: for each attachment, original = strip "_<idx>_<uuid>.ext" suffix;
#       rel = original.replace("__", "/");  copy to  screenshots/ios/<slug>/<screen>.png
```

Finding the newest bundle:

```bash
find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 5 -type d \
  -name '*.xcresult' -path '*App*' \
  | xargs -I{} stat -f '%m %N' {} | sort -rn | head -n1 | cut -d' ' -f2-
```

Always **rebuild the manifest from disk** after extraction (a `rebuild_manifest.py`
that scans `screenshots/ios/<slug>/*.png` and decomposes each slug back into
`{theme, accent, mode, font}`). The in-test manifest attachment can be clobbered
if the run crashed; the disk scan is the source of truth and is idempotent.

---

## Stage 5 — Framing into Store Tiles

Raw captures get composited onto store-sized canvases with a baked headline, a
brand-colored ground, and a device bezel. Use PIL.

### Sizes

| Device class | Capture (iPhone 17 Pro) | Store canvas (6.9") |
|---|---|---|
| Pixels | 1206 × 2622 | 1320 × 2868 |
| Display type | 6.3" | 6.9" (`APP_IPHONE_69`) |

**Capturing at 6.3" and compositing onto the 6.9" canvas is a stopgap.** It
works — the device screenshot is inset with a bezel, so the aspect mismatch
hides inside the frame — but a native 6.9" capture (run the harness on a 6.9"
simulator) is cleaner and avoids any resample. Document which you did.

**ImageRenderer vs PIL split:** the *content inside the phone* (share cards) is
rendered by the app via `ImageRenderer` — real fonts, real theme, 2× scale. The
*frame around the phone* (headline, ground, bezel, shadow) is PIL. Never redraw
app UI in PIL; only ever decorate around a true capture.

### Distilled framing snippet

A reusable single-tile framer: brand gradient ground, subtle accent glow,
rounded device bezel with a drop shadow, and a headline in the app's own font.

```python
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1320, 2868                       # 6.9" store canvas
INK  = (236, 243, 249)                  # near-white headline
ACC  = (34, 211, 238)                   # brand accent (cyan here)
FONT = "PlusJakartaSans-ExtraBold.ttf"  # the app's OWN display face
HEAD = ImageFont.truetype(FONT, 112)

def gradient(top, bot):
    b = Image.new("RGB", (W, H), top); d = ImageDraw.Draw(b)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i]-top[i]) * t) for i in range(3)))
    return b

def glow(base, cx, cy, rad=560, a=52):          # soft brand ambience
    g = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse([cx-rad, cy-rad, cx+rad, cy+rad], fill=(*ACC, a))
    g = g.filter(ImageFilter.GaussianBlur(200))
    base = base.convert("RGBA"); base.alpha_composite(g); return base.convert("RGB")

def rounded(im, rad):                            # round a screenshot's corners
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, *im.size], rad, fill=255)
    o = im.convert("RGBA"); o.putalpha(m); return o

def frame_tile(shot_path, lines, out_path):
    canvas = glow(gradient((15, 27, 42), (8, 16, 27)), W - 260, 420).convert("RGBA")
    d = ImageDraw.Draw(canvas)

    # headline — one ink color, each line stacked; small accent underline
    x, y, lh = 96, 168, 126
    for line in lines:
        d.text((x, y), line, font=HEAD, fill=INK); y += lh
    d.rounded_rectangle([x, y + 18, x + 128, y + 31], 6, fill=ACC)

    # device screenshot -> rounded -> bezel -> drop shadow -> composite
    shot = Image.open(shot_path).convert("RGB")
    dev_w = 1060; dev_h = int(shot.height * dev_w / shot.width)
    shot = rounded(shot.resize((dev_w, dev_h), Image.LANCZOS), 70)
    bez = Image.new("RGBA", (dev_w + 18, dev_h + 18), (0, 0, 0, 0))
    ImageDraw.Draw(bez).rounded_rectangle([0, 0, dev_w + 18, dev_h + 18], 79, fill=(6, 11, 18, 255))
    bez.alpha_composite(shot, (9, 9))
    px = (W - bez.width) // 2; py = y + 96

    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([px, py + 26, px + bez.width, py + bez.height + 26], 79, fill=(0, 0, 0, 150))
    sh = sh.filter(ImageFilter.GaussianBlur(38))
    canvas.alpha_composite(sh); canvas.alpha_composite(bez, (px, py))
    canvas.convert("RGB").save(out_path)
```

### Glyph-centering gotcha

To center a glyph inside a shaped background (e.g. a rounded box around the "3"
in a wordmark), **measure the real ink bounding box** and center with `anchor="mm"`
plus uniform padding. Do **not** size the box off `textlength` (that's the
*advance width*, which includes side bearing) and do **not** place text at a raw
offset — either gives visibly uneven padding.

```python
wf = ImageFont.truetype(FONT, 150)
pad = 32                                              # uniform on all four sides
hb = d.textbbox((0, 0), "3", font=wf, anchor="ls")    # real ink bbox (left/baseline origin)
three_w = hb[2] - hb[0]
box_l, box_t = x0, baseline + hb[1] - pad
box_r, box_b = x0 + three_w + pad*2, baseline + hb[3] + pad
d.rounded_rectangle([box_l, box_t, box_r, box_b], radius=int((box_b-box_t)*0.26), fill=ACC)
d.text(((box_l+box_r)/2, (box_t+box_b)/2), "3", font=wf, fill=DARK, anchor="mm")  # dead center
```

### Theme variety for the strip

Keep **most** tiles on one hero theme so the store strip reads as one cohesive
set. Then deliberately vary a couple of slots to prove range:

- One **light-mode** shot, so reviewers see it isn't dark-only.
- One **warm / alternate theme** on the personalization shot, so "make it yours"
  reads as real range.

Crucially, keep the **frame** (ground gradient + accent + bezel) uniform across
*all* tiles even when the phone content's theme varies. Only the pixels inside
the bezel change; the surrounding brand furniture stays constant.

```python
# most tiles use the hero theme dir; two slots pull from a different capture
SHOT_THEME = {"today_empty": "light", "appearance": "leather"}   # everything else: hero
def src_for(name): return THEME_DIR[SHOT_THEME.get(name, "hero")]
```

---

## Cross-References for Submission

Once the tiles exist, these are the App Store Connect specifics for getting them
uploaded and the binary accepted.

### Upload buckets

The 6.9" screenshot bucket is display type `APP_IPHONE_69`; the 6.7" bucket is
`APP_IPHONE_67`. **Both accept 1320 × 2868**, so one framed set covers both:

```bash
asc screenshots upload \
  --version-localization <LOC-ID> \
  --path ./tiles/en-US \
  --device-type IPHONE_69
```

### Archive with a STABLE Xcode

App Store review **rejects binaries archived with a BETA Xcode** (ITMS error
`90534`). Always archive/export the submission build with a stable Xcode,
regardless of what you develop against:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme App archive -archivePath ./build/App.xcarchive ...
```

(Screenshot *capture* itself is fine on a beta Xcode — this constraint is only
about the archived binary you submit.)

### Artifact preview CSP

If you assemble an HTML review artifact of the tiles (a contact sheet to eyeball
the strip before uploading), the host's CSP blocks `file://` and external
images. **Embed each PNG as a base64 data-URI:**

```python
import base64, io
from PIL import Image

def uri(path, w=560, q=86):
    im = Image.open(path).convert("RGB")
    im = im.resize((w, int(im.height * w / im.width)), Image.LANCZOS)
    buf = io.BytesIO(); im.save(buf, "JPEG", quality=q)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()

# <img src="{uri('tiles/framed_hero.png')}">
```

---

## Checklist

- [ ] Smoke test passes (one config × three screens) before the full matrix.
- [ ] Screenshots write OUTSIDE any `fileSystemSynchronizedGroup` (repo-root sibling dir).
- [ ] `9:41` status-bar override set on the booted sim, and the run uses
      `test-without-building` on `id=<udid>` so no reboot wipes it.
- [ ] Full-history seeds wipe ALL prior rows; app uninstalled between seed changes.
- [ ] Config re-scoping uses `TEST_RUNNER_SCREENSHOT_CONFIGS=...`, not a bare env var.
- [ ] Extraction rebuilds the manifest from disk afterward.
- [ ] Tiles are 1320 × 2868; frame furniture uniform across the strip; 1–2 variety slots.
- [ ] Glyph-in-box centered via ink bbox + `anchor="mm"`, not `textlength`.
- [ ] Submission binary archived with a STABLE Xcode (`DEVELOPER_DIR=...`).
- [ ] Upload to `IPHONE_69` (and `IPHONE_67` reuses the same 1320×2868 set).
