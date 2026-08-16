# ⚡ WhizMe

**The open-source PowerToys suite for macOS.** A native menu bar utility written in
pure Swift 6 and SwiftUI — no Electron, no WebViews, no telemetry. Exactly one
third-party dependency: [Sparkle](https://sparkle-project.org), for updates.

- **Bundle ID:** `me.whiz.app`
- **Requires:** macOS 14.0 (Sonoma) or later
- **Builds with:** Xcode 16+ / Swift 6
- **License:** MIT

## Repository layout — open core, closed Pro

```
WhizMe.MacOs/
├── Core/        MIT. Everything in this repository.
│   ├── WhizMe/      sources
│   └── Config/      Info.plist + entitlements
├── Pro/         Closed source. NOT in this repository (gitignored).
├── Scripts/     Build, signing, and release tooling (MIT)
└── appcast.xml  Sparkle update feed — committed, served from raw.githubusercontent
```

`Scripts/build.sh` compiles `Core/` plus `Pro/Sources/` **when that directory is
present**, and skips it silently when it is not. So this repository builds the free
app with the same script that builds the paid one — there is no second build system
and no forked copy of the shared code.

> **The shipped release binary includes Pro features, which are not open source.**
> Building from this repository gives you the free core. This is deliberate and
> disclosed rather than discovered: see [`whizme.md`](whizme.md) §3 for which
> utilities are free and which are Pro.

## Utilities in this build

| Utility | What it does | Default shortcut | Permission |
| --- | --- | --- | --- |
| **Awake** | Holds an IOKit power assertion so the Mac won't idle-sleep. Indefinite or timed (5m–4h) with a live countdown. | `⌃⇧⌘A` | none |
| **Color Picker** | System eyedropper; copies HEX/RGB/HSL to the clipboard and confirms with a banner. Keeps the last 12 swatches. | `⌃⇧⌘C` | none |
| **Text Extractor** | Drag-select any screen region, OCR it with Vision, land the text on the clipboard. | `⌃⇧⌘T` | Screen Recording |

Window Snapping, Crop & Lock, Advanced Paste, and Workspaces appear in the menu as
disabled placeholders — they are the next things to build.

## First-time setup — do this before anything else

```bash
./Scripts/setup-signing.sh
```

WhizMe **must not be ad-hoc signed** during development. macOS ties Screen Recording
and Accessibility grants to the app's *designated requirement*, and for an ad-hoc build
that requirement is a hash of the binary itself:

```
designated => cdhash H"9e246fd8359db746bc00dc853999a99347abe101"
```

Every rebuild changes that hash, so macOS sees a brand-new app and drops the grant —
while System Settings keeps showing the toggle as ON, because that row belongs to the
*previous* build. The result is an app that asks for a permission you can plainly see
is already granted, forever.

The script creates a self-signed certificate (no Apple ID, no admin password needed for
signing itself), which changes the requirement to something stable:

```
designated => identifier "me.whiz.app" and certificate root = H"29f0fd40..."
```

That hash belongs to the certificate, not the binary, so grants survive every rebuild.

## Building

```bash
./Scripts/build.sh debug && open build/WhizMe.app
```

`Scripts/build.sh` drives the toolchain directly (`swiftc` + `actool` + `codesign`)
and needs no working `xcodebuild`, which makes it the reliable path on a fresh
machine and in CI. Pass `release` for an optimized, whole-module build.

**Debug and Release are signed identically**, on purpose. Both set
`ENABLE_DEBUG_DYLIB = NO` and `ENABLE_HARDENED_RUNTIME = YES`, producing a single
self-contained, hardened binary.

That matters for privacy permissions. Xcode's default Debug layout makes
`Contents/MacOS/WhizMe` a ~58 KB stub that `dlopen`s the real code from
`WhizMe.debug.dylib`, and hardened runtime has to be off for that to load at all
(Library Validation rejects a dylib with no matching Team ID — the crash below).
macOS records a privacy grant against the code identity that requested it, so a Debug
build shaped differently from a Release build is a different app as far as TCC is
concerned, and each needs granting separately. Turning the stub off removes the
difference and lets one grant cover every build.

Disabling the debug dylib also permanently removes this launch failure:

```
'…/WhizMe.debug.dylib' not valid for use in process:
mapping process and mapped file (non-platform) have different Team IDs
```

The trade-off is that SwiftUI Previews for the app target rely on that dylib. If you
want previews back, set `ENABLE_DEBUG_DYLIB = YES` and `ENABLE_HARDENED_RUNTIME = NO`
on the Debug configuration — and expect to re-grant Screen Recording more often.

Check at any time that every build presents one identity:

```bash
./Scripts/check-signing.sh
```

Fetch Sparkle once before the first build, or the compiler stops at
`No such module 'Sparkle'`. `Scripts/build.sh` does this for you; Xcode does not:

```bash
./Scripts/fetch-sparkle.sh
```

The Xcode project builds and runs the same sources:

```bash
xcodebuild -project WhizMe.xcodeproj -scheme WhizMe -configuration Debug build
```

**It is not equivalent for shipping.** Xcode's Embed Frameworks phase signs the
Sparkle framework itself but leaves the helpers nested inside it — `Autoupdate`,
`Updater.app`, and the two XPC services — with the ad-hoc signature Sparkle ships.
`Scripts/build.sh` re-signs all of them with this project's certificate,
innermost-first. Both run, because `com.apple.security.cs.disable-library-validation`
admits the mismatch, but only one of them produces a bundle whose every component
presents one identity.

**Always cut releases with `./Scripts/release.sh`, never from Xcode's Archive.**

> If `xcodebuild` dies with *"failed to load a required plug-in"*, Xcode's
> first-launch components were never installed. Fix it once with
> `sudo xcodebuild -runFirstLaunch`.

## Releases and updates

WhizMe updates itself with [Sparkle 2](https://sparkle-project.org) — the project's
only third-party dependency, fetched and checksum-pinned by `Scripts/fetch-sparkle.sh`
rather than committed.

```bash
./Scripts/release.sh 0.2.0
```

That builds a release, packages `dist/WhizMe-<version>.zip` with `ditto`, verifies the
signature survived packaging, and regenerates `dist/appcast.xml` — signing each archive
with the EdDSA key in the maintainer's keychain. Then upload the zip to the GitHub
release tagged `v<version>`, **then** publish the appcast; a client that reads the feed
in between gets a 404.

### Why an updater matters more here than usual

WhizMe has no Apple Developer Program membership, so it is **not notarized**. A user who
downloads a release pays for that once: macOS refuses the first launch, and they have to
go to System Settings → Privacy & Security → *Open Anyway*.

Sparkle replaces the installed bundle in place instead of handing the user a fresh
download to open, so that cost is paid at install and never again. Shipping manual
downloads alone would inflict it on every single release.

### What makes an update trustworthy without Apple in the loop

Two independent checks:

1. **EdDSA signature** — every archive is signed with a private key held only by the
   maintainer, and Sparkle refuses anything that does not verify against `SUPublicEDKey`
   in `Config/Info.plist`.
2. **Code-signing continuity** — Sparkle rejects an update whose code signature does not
   match the running app's. This is also what protects privacy grants: Screen Recording
   is tied to the designated requirement, so an update signed by a different certificate
   would silently lose it.

### Two keys, and what losing each one costs

| Key | Lives in | If lost |
| --- | --- | --- |
| Code-signing cert (`Whiz.me Local Signing`) | login keychain | Every user's Screen Recording and Accessibility grants drop, and Sparkle rejects all further updates as a signature mismatch. |
| Sparkle EdDSA private key | login keychain | No further updates can ever be published to existing installs. |

**Both are single copies in one login keychain right now.** Export the certificate as a
`.p12` and back up the Sparkle key (`Vendor/Sparkle/bin/generate_keys -x <file>`), keep
them encrypted and offline. Neither is recoverable.

### Signing Sparkle is not optional

Sparkle ships ad-hoc signed (`TeamIdentifier=not set`) so integrators re-sign it. Under
the Hardened Runtime, Library Validation refuses to load a dylib whose Team ID differs
from the host process — the same failure as the debug-dylib note above. `build.sh` signs
every nested bundle innermost-first, because signing a container seals hashes of
everything inside it, so anything signed afterwards invalidates the seal above it.

## Architecture

Strict four-layer separation — see [`.cursorrules`](.cursorrules) for the rules that
AI agents and humans are both expected to follow.

```
WhizMe/
├── WhizMeApp.swift            MenuBarExtra + Settings scenes
├── AppDelegate.swift          Owns the object graph; bootstrap/teardown
├── Models/                    Pure data — no AppKit, no system frameworks
│   ├── WhizFeature.swift          Every utility, its metadata and required grants
│   ├── SystemPermission.swift     TCC permissions + System Settings deep links
│   ├── HotKey.swift               Key code + modifiers, Carbon-agnostic
│   ├── AwakeDuration.swift
│   ├── SampledColor.swift         sRGB value + HEX/RGB/HSL formatting
│   └── AppInfo.swift
├── Services/                  One system framework each, no state, no UI
│   ├── PermissionService.swift        AXIsProcessTrusted / CGPreflightScreenCaptureAccess
│   ├── KeepAwakeService.swift         IOKit.pwr_mgt assertions
│   ├── ColorSamplerService.swift      NSColorSampler
│   ├── ScreenCaptureService.swift     ScreenCaptureKit (+ CGWindowList fallback)
│   ├── TextRecognitionService.swift   Vision VNRecognizeTextRequest
│   ├── HotKeyService.swift            Carbon RegisterEventHotKey
│   ├── NotificationService.swift      UNUserNotificationCenter
│   ├── PasteboardService.swift        NSPasteboard
│   ├── LaunchAtLoginService.swift     SMAppService
│   └── UpdateService.swift            Sparkle — the only file that imports it
├── Managers/                  @MainActor @Observable state + orchestration
│   ├── AppEnvironment.swift       Composition root; single trigger(_:) entry point
│   ├── PermissionManager.swift    Polls TCC, degrades to System Settings
│   ├── AwakeManager.swift
│   ├── ColorPickerManager.swift
│   ├── OCRManager.swift
│   ├── HotKeyManager.swift
│   ├── PreferencesManager.swift
│   ├── UpdateManager.swift        Update state + Sparkle UI callbacks
│   └── OnboardingPresenter.swift
└── Views/                     Presentation only
    ├── MenuBarView.swift
    ├── MenuActionRow.swift
    ├── PermissionsOnboardingView.swift
    ├── RegionSelectionOverlay.swift   AppKit drag-select overlay
    ├── SettingsView.swift
    └── OnboardingEnvironment.swift
```

Both the menu bar and the global shortcuts call `AppEnvironment.trigger(_:)`, so a
utility has exactly one definition of "run me".

## Permissions

WhizMe ships **unsandboxed** by design: the App Sandbox forbids the Accessibility
API from driving other apps' windows and blocks whole-screen capture. Distribution is
therefore outside the Mac App Store, Developer ID signed and notarized.

Two grants matter, and the app degrades gracefully without either:

- **Screen Recording** — Text Extractor. macOS only re-reads this grant at process
  start, so the onboarding window offers a Relaunch button.
- **Accessibility** — Window Snapping and Workspaces (not yet implemented).

macOS shows each privacy prompt at most once per app identity; every later request is
a silent no-op. `PermissionManager` remembers that it has asked and sends repeat
requests straight to the correct System Settings pane instead of nowhere.

If a permission you granted stops working after a rebuild, the app is ad-hoc signed —
see [first-time setup](#first-time-setup--do-this-before-anything-else).
`CodeSigningService` detects this at runtime and the onboarding window says so, rather
than leaving you to re-grant Screen Recording after every build.

Verify the identity is stable at any time:

```bash
codesign -d -r- build/WhizMe.app
```

Note that macOS composes the Accessibility and Screen Recording prompt text itself —
unlike Camera or Microphone, it does not read a per-app usage string. The keys in
`Config/Info.plist` are documentation; the copy users actually read lives in
`SystemPermission.rationale`.

## Contributing

Adding a utility touches four places and nothing else: a `WhizFeature` case, one
service per system API, one manager, and a row in `MenuBarView`.

- [Issues](https://github.com/AtharvaBari/WhizMe/issues)
- [Discussions](https://github.com/AtharvaBari/WhizMe/discussions)
