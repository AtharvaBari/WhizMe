# Ideas

Every feature WhizMe has, is building, or might build. The living list — `whizme.md` is
the original spec and does not change; this one does.

Last updated: 2026-08-17

---

## What WhizMe is

**The open-source PowerToys suite for macOS.** A native menu bar utility in Swift 6 and
SwiftUI. No Electron, no WebViews, no telemetry. One dependency (Sparkle, for updates).

The bet: macOS leaves obvious gaps — window zones, screen OCR, clipboard reformatting,
sleep control — and people currently fill them with five separate paid apps, several of
them Electron. One small native app that does all of it is worth having.

**Business model: open core.** The free tier is genuinely useful and MIT licensed. The
Pro tier is the power-user work that takes real engineering.

---

## Shipping today

| Utility | What it does | Shortcut | Needs |
| --- | --- | --- | --- |
| **Awake** | Holds an IOKit power assertion so the Mac won't idle-sleep. Indefinite or 5m–4h with a live countdown. | `⌃⇧⌘A` | — |
| **Color Picker** | System eyedropper. Copies HEX/RGB/HSL, keeps the last 12 swatches. | `⌃⇧⌘C` | — |
| **Text Extractor** | Drag-select any screen region, OCR it with Vision, text lands on the clipboard. | `⌃⇧⌘T` | Screen Recording |
| **Advanced Paste** | Reformat the clipboard on the way out — plain text, Markdown, JSON, case changes, OCR from an image. | `⌥⌘V` | Accessibility (to auto-paste) |
| **Clean Keyboard** | Swallows every key so you can wipe the keyboard. Exits by trackpad only — deliberately. | on demand | Accessibility |
| **Clean Screen** | Blacks out every display so you can clean the glass. Escape or Return exits. | on demand | — |

Plus: launch at login, light/dark/system theme, rebindable shortcuts, first-run
permission walkthrough, and automatic updates with a notification when one is available.

---

## Free tier — next up

**Window Snapping** *(announced, in the menu as "Soon")*
Left/right/quarter/grid snapping by keyboard. The single most requested macOS gap. Needs
Accessibility. This is the feature that gets the project noticed, so it should be free.

---

## Pro tier — planned

Paid because each one is substantial engineering, not because it is artificially withheld.

**PowerZones** — a FancyZones equivalent. Draw custom zone layouts, assign hotkeys, drag
a window into a zone. Per-display and per-Space layouts. The flagship Pro feature.

**Workspaces** — save a complete multi-app, multi-monitor window arrangement and restore
it in one click. "Start work" opening the right apps on the right screens at the right
sizes. Needs Accessibility and Apple Events.

**Crop & Lock** — turn any cropped screen region into a live floating always-on-top
window. Watch a build log or a video while working in front of it. Needs Screen Recording.

**AI Advanced Paste** — the current Advanced Paste plus summarise, translate, rewrite,
explain. Local model by default; cloud optional and off unless asked. Must never send
clipboard contents anywhere without explicit consent — that would break the no-telemetry
promise the project is built on.

**Cloud Sync** — shortcuts, zone layouts, and preferences across Macs.

---

## Unranked ideas

Not committed to. Kept here so they are not lost.

**Clipboard history** — searchable, with pinning. Big overlap with Advanced Paste's
plumbing; the hard parts are storage, privacy (never persist password-manager copies),
and search UI.

**Screenshot annotation** — Text Extractor already selects a region and captures it.
Arrows, boxes, blur-for-redaction is a short step from there.

**Battery / thermal readout** — a menu bar line for cycle count, health, throttling. Easy,
and it fits a utility suite.

**Quick file actions** — convert image formats, strip EXIF, resize, from the menu bar.

**Focus profiles** — one toggle that sets Do Not Disturb, quits Slack, opens the editor,
and turns Awake on. Composes existing utilities rather than adding a system integration.

**Do-not-sleep on conditions** — keep awake *while* a named app runs, or while a download
is active, instead of a fixed timer. A genuinely better Awake.

**Menu bar manager** — hide and reorder menu bar icons. Popular category, but crowded
(Bartender, Ice) and fiddly.

**Text snippets / expansion** — type `;addr` and get an address. Needs Accessibility
keystroke injection, which Advanced Paste already does.

---

## Deliberately not doing

Saying no matters as much as the list above.

**Anything Electron or WebView.** The whole point is that this is native.

**Telemetry or analytics.** Not even anonymous, not even opt-in-by-default. "Nothing
leaves your Mac" has to be literally true or it is worth nothing.

**A subscription for the free tier.** The free utilities stay free and MIT.

**Cloud processing by default.** If AI features arrive, local first, cloud only when
explicitly asked.

**Mac App Store.** The sandbox forbids the Accessibility API from driving other apps'
windows and blocks whole-screen capture — that is most of the suite.

---

## Known limits right now

Honest list of what is not good yet.

**Not notarized.** No Apple Developer Program membership, so first launch requires
System Settings → Privacy & Security → Open Anyway. Sparkle keeps this to a one-time
cost, and the install page should explain it plainly rather than let users discover a
scary dialog. $99/yr fixes it; a natural first use of sponsorship money.

**No install page or Homebrew tap yet.** Both matter more for adoption than any new
feature — a scary unexplained dialog loses more users than a missing utility.

**Advanced Paste is the least polished code in the app.** It works, but it was written
to a lower standard than everything around it and has no doc comments.

**The update notification has not been observed firing end to end.** The mechanism is
implemented and structurally verified; nobody has yet watched a banner appear from a real
scheduled check.

**No tests.** Nothing automated verifies behaviour. `WhizFeature`, `HotKey`,
`SampledColor`, and `ClipboardService`'s transformations are pure and easy to test — a
sensible place to start.

**Website says "Whiz.me" in places.** It is a separate repo and needs its own rename pass.
