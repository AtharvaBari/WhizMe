# Report

What the AI has done to this app, in plain words. Newest first.

Each entry says what was wrong, what changed, and whether it was actually tested.

---

## 2026-08-17 — Full-screen welcome, and Settings was broken

Added the full-screen first-run sequence: the desktop dims, the logo assembles itself from
particles in the middle of the screen, slides left, and "WhizMe" slides out from behind
it. A Continue button arrives at the bottom when it finishes. Escape or Return skip it.

After Continue it opens Settings on the Home page, waits for that to land, and only then
asks for permissions — and only if something is actually missing. On a Mac where
everything is already granted, no permission window appears at all.

Removed, as redundant: the small onboarding window's own logo intro (the full-screen one
does that job now, so users were greeted twice), and the "Setup walkthrough" row in
Settings. Added a temporary "Replay welcome animation" button under a Testing group in
Settings, marked for removal before 1.0.

### Settings could not be opened at all

This is the big one, and it was pre-existing. Every route into Settings — including the
menu bar's own "Settings…" item — called `showSettingsWindow:`. That reports success and
opens nothing in this app. Confirmed it was not a permissions or activation problem by
retesting with the app active and promoted; still nothing. The cause is that SwiftUI never
realises the Settings scene, because a menu-bar-only app has no window-bearing scene to
connect it to.

Settings is now hosted in its own window, the same way the other windows already were.
Verified: the window now appears, titled and on the Home page.

### Two SwiftUI traps found by tracing

The welcome kept dismissing itself the instant it finished. Two separate causes, both
found by instrumenting the code rather than guessing:

1. A `Button` with `.keyboardShortcut(.defaultAction)` in a borderless key window **fires
   its own action** with no keypress at all.
2. A `Button` whose `.disabled` flips from true to false also self-fires.

The Continue button now uses neither — it is inserted when ready, and Return is handled by
the window directly.

**Not verified:** nobody has looked at the animation. Screenshots need Screen Recording
permission the terminal does not have, so timing, scale, and whether the slide reads well
all need human eyes.

---

## 2026-08-17 — Custom onboarding window

Onboarding opened as a plain macOS window — traffic lights, an empty title bar — which
made the first thing a new user sees look like a settings dialog that opened by accident.

It is now a rounded floating panel that draws its own edge, shadow, and close button. It
scales up gently when it opens and shrinks away when dismissed, rather than blinking in
and out. Escape closes it, and you can drag it from anywhere on the panel since there is
no title bar to grab.

The permission rows now arrive as one movement travelling down the list — each row 45ms
after the one above it — instead of the whole page fading in at once.

**Found a bug that was already there:** pressing Return on the welcome screen *skipped
onboarding completely*. The permission list sits behind the intro the whole time so the
two can cross-fade, and its "Done" button was still live and also registered as the
default Return action. So Return pressed the invisible Done instead of Continue. Fixed —
and confirmed by driving it with the keyboard: Return now moves to the permission list,
and a second Return finishes.

Also chose a titled-but-stripped window over a fully borderless one. A borderless window
is invisible to VoiceOver and disappears from Mission Control; hiding the parts of a real
window gets the same look without that cost. Confirmed the window is now announced as
"Welcome to WhizMe" at the right size.

**Not verified:** nobody has looked at it yet. Taking a screenshot needs Screen Recording
permission the terminal does not have, so the visual result — spacing, shadow weight,
whether the entrance feels right — needs human eyes.

---

## 2026-08-17 — Full bug scan

Read all 7,000 lines and fixed six real bugs. Most of the code is genuinely careful —
continuations resume exactly once, the sleep assertion has a fallback release, the
coordinate conversion is correct. The bugs were in specific corners.

### 1. A crash waiting to happen (Advanced Paste)

`ClipboardService` had `element as! AXUIElement` — a forced cast. If macOS ever handed
back something that wasn't a UI element, the app would **quit instantly**. The
accessibility API is supposed to return an element, but a crashing or half-closed app
isn't obliged to cooperate.

Now it checks the type first and gives up on the paste instead of taking the app down.

### 2. Advanced Paste pasted into the wrong place

The paste HUD called `NSApp.activate`, which made WhizMe the frontmost app. Then it
simulated ⌘V — which goes to whatever is frontmost. So it pasted into WhizMe itself,
not the app you were typing in.

The panel is already the kind that can be clicked without stealing focus, so the
activate call was removed. Your original app stays in front and gets the paste.

### 3. Text Extractor could die permanently

If macOS reported no displays — which happens during a display change or when the screen
is locked — the region selector put up nothing, and the code waited forever for a
selection that could never come. Text Extractor stayed stuck "capturing" for the rest of
the session. Restarting the app was the only fix.

Now it gives up immediately if there is no display to draw on.

### 4. Clean Keyboard could leave your keyboard dead

Same root cause, worse effect. The keyboard block started *before* the overlay appeared.
If the overlay failed to appear, every key was swallowed and the only stop button was
invisible — you'd need the mouse and the menu bar to escape.

The overlay now goes up first. If it fails, the keyboard block is undone and you get a
message explaining why.

### 5. Advanced Paste read stale permissions

It checked the cached Accessibility status instead of re-reading it. Permission checking
stops once nothing is missing, so a permission you granted a minute ago could still read
as denied — and auto-paste would silently downgrade to "it's on your clipboard, paste it
yourself." Now it re-checks, like every other feature does.

### 6. Intel Macs could not run the app at all

The build only ever compiled for the machine doing the building — Apple Silicon. Intel
Macs couldn't run it, and the update feed even recorded "Apple Silicon only," so Sparkle
correctly refused to offer updates to them.

Release builds are now universal: both architectures compiled and joined together.
**Verified** — the binary reports `x86_64 arm64`, and the arch restriction has
disappeared from the feed.

Also fixed: the HTML-to-Markdown converter left multi-line `<script>` blocks in place, so
JavaScript could end up pasted as text.

### Tested

Universal release builds clean with warnings treated as errors, all nested Sparkle
components verify, the app launches, the Xcode build still works, and the app's signing
identity is unchanged — so nobody loses their Screen Recording permission.

**Not tested:** the Advanced Paste focus fix needs a human to click the HUD and confirm
text lands in the right app. It cannot be checked without a real click.

---

## 2026-08-17 — Update notifications

Added a notification when a new version is available, instead of a window appearing over
whatever you're doing. Clicking the banner installs. If you dismiss it, the update still
shows in Settings and in the menu bar, so it isn't lost.

Used Sparkle's built-in mechanism for this rather than inventing one. Confirmed all five
of its callbacks match the framework exactly — they're optional methods, so a typo would
mean silence rather than an error.

**Found a bug in earlier work:** a setting had been written as "don't check
automatically", with a comment claiming it would still ask the user. It doesn't — it means
never check and never ask, which would have made the notification unreachable no matter
how well it was built. Removed, so the app asks once.

**Not verified:** no banner has actually been watched appearing. The real test is
publishing a version and waiting for a scheduled check.

---

## 2026-08-17 — One DMG, and CI

Releases are now a single `.dmg` instead of a `.zip`. The same file is what a new user
opens and what the updater downloads — one upload per release, so there is no second file
to fall out of step with the update feed.

**Found a live bug:** the feed listed older versions under the *newest* release's tag, so
those links returned "not found". Each version now points at its own release.

Added two automatic checks:

- **Build** — compiles the public repo on a clean Mac. Its real job is catching the day
  the free code starts depending on the paid code, which breaks things for everyone
  downloading the repo but never on this machine.
- **Feed check** — confirms every download link works and every file size matches. A
  missing upload breaks updates silently for every user; this notices.

Both green. The feed check found the broken link above before it ever ran on GitHub.

---

## 2026-08-16 — Published to GitHub

Set up `github.com/AtharvaBari/WhizMe` and moved updates entirely onto GitHub — the feed
is read from the repo, downloads come from releases.

Split the folder into `Core/` (open, MIT) and `Pro/` (closed). **The repo is public**, so
`Pro/` is excluded from it entirely rather than trusted to be remembered. One build script
handles both: it compiles `Pro/` when present and skips it when absent.

Checked before pushing that no certificate, key, or private file was included.

---

## 2026-08-16 — Automatic updates

Added Sparkle so the app can update itself, plus the release tooling to publish updates.

This matters more here than in most apps. WhizMe isn't notarized by Apple, so a fresh
download makes macOS refuse the first launch until you allow it manually. Sparkle replaces
the app in place, so that annoyance happens once at install rather than on every release.

**Hit a real problem:** the app wouldn't launch — macOS refused to load Sparkle because
the app is signed with a self-made certificate rather than an Apple one. Diagnosed and
fixed with a specific permission for it. Worth knowing this was a genuine cost of not
having an Apple developer account, and it wasn't predicted.

Also set up: checksum-pinned download of Sparkle, correct signing of everything inside
it, key backup instructions, and secure timestamps so signatures outlive the certificate.

---

## 2026-08-16 — Renamed to WhizMe

Changed "Whiz.me" to "WhizMe" everywhere — 33 files.

Deliberately **not** renamed: the signing certificate's name and the app's internal id.
Both are what macOS uses to remember your Screen Recording permission. Renaming them
would make every user grant permission again. Verified the app's identity is unchanged.

---

## How to keep this file useful

Add a dated entry when something meaningful changes. Say what was wrong, what changed, and
whether it was actually tested — including what wasn't. The value of this file is that it
is honest about untested work, not that it looks impressive.
