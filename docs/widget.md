# macOS widget: what we learned (tried October 2026, removed)

We built a WidgetKit widget (desktop and Notification Center) showing a camera snapshot and the print progress. It worked, but we removed it: macOS refreshes widgets too rarely for it to be useful. This page keeps what we learned so a second attempt does not start from zero. Names below use the app's current name (Pique); the experiment ran when it was still called BambuCam.

## Why it was removed

- **Widgets cannot be real time.** macOS decides when a widget redraws. An app can request a reload (`WidgetCenter.shared.reloadAllTimelines()`), but reloads come out of a budget of roughly 40–70 per day; past that, macOS ignores them.
- In practice the image and the percentage lagged 10–15 minutes behind. Only the countdown stayed accurate.

## Ideas not tried yet

1. **Precomputed timeline (free).** On each reload, return one entry per minute for the next 15 minutes, with the percentage estimated from the ETA (`percent0 + (100 - percent0) × elapsed / remaining`). macOS shows entries at their dates without spending budget.
   Simpler for the progress bar: `ProgressView(timerInterval: start...eta)`. macOS animates it continuously without waking the widget, like `Text(date, style: .timer)`. That is how the Clock widget appears live: anything that depends only on time is animated by the system. Printer data (image, real percentage, temperatures, state) still needs a reload. (The Clock's analog hands use private API.)
2. **One image every 10 minutes while printing** (about 24 reloads for a 4-hour print, within budget).
3. **Show the snapshot's time** on the widget, so the lag is visible.
4. For real time on the desktop, skip WidgetKit: a borderless window at desktop level (`NSWindow` with `level = .init(Int(CGWindowLevelForKey(.desktopWindow)))`) fed by the existing camera stream. Not tested.

## Architecture that worked

- **The widget never talks to the printer.** The app, already connected over MQTT in the background, writes two files to a shared App Group container:
  - `status.json`: state, file, percent, ETA, layers, temperatures, AMS spools, online flag, language, update time.
  - `frame.jpg`: a single camera frame.
- Container: `~/Library/Group Containers/<TEAM_ID>.com.loicbisiere.Pique/`. The group id depends on the signing team, so `bundle.sh` injected it into both `Info.plist` files (custom key) and the code read it with `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`.
- The app only exported when a widget was placed: `WidgetCenter.shared.getCurrentConfigurations` (local and cheap), checked on every export (at most every 5 s). Checking only at launch did not work: a widget added later stayed empty for up to 15 minutes.
- New frame on every state change, then every 15 minutes **only while printing** (no video while idle), using `Camera.grabFrame` (connect for one frame) or the live frame when a window was streaming.
- The countdown stayed live without reloads thanks to `Text(eta, style: .relative)`.
- Language: the app wrote its language into `status.json` and the widget applied it with `.environment(\.locale, …)`, falling back to `Locale.current`. The app's `.lproj` folders were copied into the extension.

## Building the extension without an Xcode project

SwiftPM cannot build app extensions, so `bundle.sh` compiled it by hand. What cost time:

- **The entry point is mandatory.** Without it, the extension registers (`pluginkit` lists it) but never shows up in the widget gallery, and nothing in the logs says why. These are Xcode's settings for the app-extension product type (`LD_ENTRY_POINT = _NSExtensionMain`, `APPLICATION_EXTENSION_API_ONLY = YES`):
  ```sh
  xcrun swiftc -parse-as-library -O -target arm64-apple-macos14.0 -module-name PiqueWidget \
    -application-extension -Xlinker -e -Xlinker _NSExtensionMain \
    Widget/PiqueWidget.swift Sources/Pique/Shared.swift \
    -o Pique.app/Contents/PlugIns/PiqueWidget.appex/Contents/MacOS/PiqueWidget
  ```
  (`Shared.swift` held the types used by both the app and the widget.)
- **Extension `Info.plist`**: `CFBundlePackageType = XPC!`, bundle id `com.loicbisiere.Pique.widget`, and
  ```xml
  <key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
  ```
- **Entitlements.** Extension: `com.apple.security.app-sandbox = true` and `com.apple.security.application-groups = [<TEAM_ID>.com.loicbisiere.Pique]`. App: the same group, not sandboxed. A team-prefixed group needs no provisioning profile on macOS.
- **Signing**: extension first, then the app, with the "Apple Development" identity (`security find-identity -v -p codesigning`). The team id is the `OU` field of the certificate.
- **After installing**: `lsregister -f /Applications/Pique.app`, then `killall chronod` so the gallery and already-placed widgets load the new binary. Without `killall chronod`, a widget sometimes keeps its old rendering, which made us wrongly think a fix did not work.

## One-time signing setup

- Xcode installed, Apple Account added (Settings > Apple Accounts > Sign In…; a free account gives a "Personal Team"), "Apple Development" certificate created.
- Pitfall: the certificate showed up but `find-identity -v` reported "0 valid identities". The **Apple WWDR G3** intermediate certificate was missing from the keychain. Fix:
  ```sh
  curl -O https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
  security import AppleWWDRCAG3.cer -k ~/Library/Keychains/login.keychain-db
  ```
- `sudo xcode-select -s /Applications/Xcode.app` is not needed: `xcrun` with the Command Line Tools was enough.

## Rendering on the desktop

- When macOS **dims** desktop widgets (System Settings > Desktop & Dock > "Dim widgets on desktop": Automatically), it renders them in **`accented`** mode (not `vibrant`; checked with a diagnostic overlay in the widget). Any image becomes a flat tinted block.
- Fix (macOS 15+): `Image(nsImage:).resizable().widgetAccentedRenderingMode(.fullColor)`. Verified: the image stays visible. `luminanceToAlpha()` does not help.
- Text, icons and shapes stay tinted in dimmed mode; with "Never", everything keeps its colors.
- To diagnose: display `@Environment(\.widgetRenderingMode)` and `@Environment(\.showsWidgetContainerBackground)` in a corner of the widget.

## Misc

- `containerBackground(for: .widget)` is required since macOS 14; `.contentMarginsDisabled()` lets the image reach the edges.
- Families used: `.systemSmall` (image with state and percent overlaid), `.systemMedium` (image plus a summary column), `.systemLarge` (image, summary, temperatures, AMS).
- WidgetKit ships in the Command Line Tools SDK, so the widget code can be type-checked without Xcode: `xcrun swiftc -typecheck … -application-extension`.
