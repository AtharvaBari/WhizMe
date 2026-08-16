# ⚡ WHIZ.ME — PRODUCT BIBLE & TECHNICAL BLUEPRINT

> **Document Type:** Master System Architecture, Product Specification & Vibe-Coding Roadmap
> **App Name:** WhizMe
> **Bundle Identifier:** me.whiz.app
> **Tagline:** "The Open-Source PowerToys Suite for macOS."
> **Target Platform:** macOS 14.0+ (Sonoma, Sequoia, and beyond)
> **License Model:** Open-Core (MIT License for Free Core / Paid Pro Modules via LemonSqueezy)

---

## 1. EXECUTIVE SUMMARY & BRAND VISION

### 1.1 What is WhizMe?
WhizMe is a lightweight, native macOS menu bar application built with modern Swift and SwiftUI. It brings the power utilities of Microsoft PowerToys to the macOS ecosystem—filling system gaps like multi-zone window snapping, instant screen-to-clipboard OCR, custom color sampling, sleep management, and workspace restoration without requiring heavy third-party subscriptions.

### 1.2 Core Pillars
1. **Zero Telemetry & 100% Native:** Built with pure Swift, SwiftUI, and AppKit. Zero heavy electron wrappers, web views, or tracking.
2. **Open-Source Core:** Free forever core tools to establish developer trust, GitHub stars, and community adoption.
3. **Vibe-Coder Friendly:** Architected specifically to be built, maintained, and extended using AI coding agents (Cursor, Claude Code, ChatGPT, Antigravity).

---

## 2. ARCHITECTURAL BLUEPRINT & MACOS FRAMEWORK MAPPING

WhizMe interfaces directly with low-level macOS system APIs. The table below maps every feature to its precise native Apple framework:

| Feature Name | Primary Framework / API | Required System Permissions (TCC) |
| :--- | :--- | :--- |
| **App Shell** | `SwiftUI.MenuBarExtra`, `AppKit.NSStatusItem` | None |
| **Window Snapping (FancyZones)** | `Accessibility` (`AXUIElement`), `CoreGraphics` | **Accessibility** (`AXIsProcessTrusted`) |
| **Text Extractor (OCR)** | `Vision` (`VNRecognizeTextRequest`), `AppKit.NSPasteboard` | **Screen Recording** (`CGWindowListCreateImage`) |
| **System Color Picker** | `AppKit.NSColorSampler`, `NSPasteboard` | None |
| **Awake (Keep Alive)** | `IOKit.pwr_mgt` (`IOPMAssertionCreateWithName`) | None |
| **Crop & Lock (PIP)** | `ScreenCaptureKit`, `AppKit.NSWindow` (Level: `.floating`) | **Screen Recording** |
| **External Monitor Control** | `IOKit` (DDC/CI over I2C/DisplayPort) | None |
| **Advanced Paste & AI** | `AppKit.NSPasteboard`, `CoreGraphics` (`CGEvent`) | **Accessibility** (for simulated keypresses) |
| **PowerRename** | `Foundation.FileManager`, `NSRegularExpression` | File System Access (User Selected) |
| **Workspaces (Pro)** | `AppKit.NSWorkspace`, `Accessibility` (`AXUIElement`) | **Accessibility** |

---

## 3. FEATURE SPECIFICATION & FREEMIUM TIERING

To maximize community growth while building a sustainable revenue model, WhizMe uses an **Open-Core Model**.

### 3.1 Free Open-Source Core (MIT License)
- **Awake Service:** Prevent sleep via menu bar toggle or temporary timers.
- **Color Picker:** Global eyedropper returning HEX, RGB, HSL straight to clipboard with native notifications.
- **Text Extractor OCR:** Drag-to-select screen regions and extract text directly into clipboard via Vision framework.
- **Basic Window Snapping:** Essential left/right/grid snap shortcuts.
- **In-App Community & Support Hub:** Integrated settings view with links to GitHub Issues, Discussions, and Tip Jar.

### 3.2 Paid Pro Tier (Unlocked via License Key)
- **PowerZones (FancyZones Clone):** Custom drag-and-drop screen layout designer with hotkey zones.
- **Workspaces:** Save complete multi-app, multi-monitor window arrangements and restore them with 1-click.
- **Crop & Lock:** Create live, interactive floating PIP windows of any cropped screen region.
- **AI Advanced Paste:** Instant clipboard reformatting (Markdown, JSON, summarize, translate) via local or cloud LLMs.
- **Cloud Sync:** Cross-Mac synchronization of hotkeys and custom layouts.

---

## 4. VIBE-CODING STANDARDS (`.cursorrules` SPEC)

When generating code for WhizMe, AI agents must adhere strictly to these architectural constraints:

```markdown
# WhizMe Code Rules
- Language: Swift 6+
- Frameworks: SwiftUI, AppKit, Combine
- Target: macOS 14.0+
- Pattern: MVVM / Service-Oriented. Views must remain strictly presentation layers.
- File Separation: NEVER combine multiple services or managers in a single file.
  - UI Views -> `Views/`
  - Logic/Managers -> `Managers/`
  - System Wrappers -> `Services/`
- TCC Permissions: Always write graceful error handling when AXUIElement or Screen Recording permission is denied.
- Bundle Identifier: me.whiz.app