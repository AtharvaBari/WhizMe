import AppKit
import Observation

/// Composition root. Owns one instance of every manager and is injected into the
/// SwiftUI hierarchy via `.environment(_:)`.
///
/// This is also the single place a utility is *invoked* from: both the menu bar and
/// the global shortcuts funnel through `trigger(_:)`, so there is exactly one
/// definition of what "run Text Extractor" means.
@MainActor
@Observable
final class AppEnvironment {
    let preferences: PreferencesManager
    let permissions: PermissionManager
    let awake: AwakeManager
    let colorPicker: ColorPickerManager
    let ocr: OCRManager
    let advancedPaste: AdvancedPasteManager
    let cleanKeyboard: CleanKeyboardManager
    let cleanScreen: CleanScreenManager
    let hotKeys: HotKeyManager
    let clipboardHistory: ClipboardHistoryManager
    let power: PowerManager
    let updates: UpdateManager

    init() {
        let permissions = PermissionManager()
        self.permissions = permissions
        self.preferences = PreferencesManager()
        self.awake = AwakeManager()
        self.colorPicker = ColorPickerManager()
        self.ocr = OCRManager(permissions: permissions)
        self.advancedPaste = AdvancedPasteManager(permissions: permissions)
        self.cleanKeyboard = CleanKeyboardManager(permissions: permissions)
        self.cleanScreen = CleanScreenManager()

        // Mutually exclusive on purpose. A black screen dismissed only by Escape, with
        // a keyboard block swallowing Escape, is a Mac the user cannot get out of
        // without a force quit — so starting either one stands the other down.
        self.cleanKeyboard.onWillStart = { [weak cleanScreen = self.cleanScreen] in
            cleanScreen?.stop()
        }
        self.cleanScreen.onWillStart = { [weak cleanKeyboard = self.cleanKeyboard] in
            cleanKeyboard?.stop()
        }
        self.clipboardHistory = ClipboardHistoryManager()
        self.power = PowerManager()
        self.hotKeys = HotKeyManager()

        // Constructed at launch rather than lazily on first use: Sparkle owns the
        // scheduled-check timer, and a manager built only when Settings is opened
        // would never check for updates on a Mac where Settings is never opened.
        self.updates = UpdateManager()
    }

    /// Set by the menu bar to ask the Settings window to open on a particular
    /// utility's page. `SettingsView` consumes and clears it — the window may not
    /// exist at the moment the request is made, so it cannot simply be told.
    var pendingSettingsFeature: WhizFeature?

    /// Called once from the app delegate after launch.
    func bootstrap() {
        permissions.startMonitoring()
        power.startMonitoring()
        clipboardHistory.startMonitoring()

        for feature in WhizFeature.shipping {
            hotKeys.setAction(for: feature) { [weak self] in
                self?.trigger(feature)
            }
        }
        hotKeys.activate()
    }

    func shutdown() {
        hotKeys.deactivate()
        permissions.stopMonitoring()
        power.stopMonitoring()
        // Flushes the debounced save; there is no later.
        clipboardHistory.stopMonitoring()
        // Releasing the power assertion here matters: a leaked assertion outlives
        // the process and keeps the Mac awake with nothing to switch it off.
        awake.deactivate()
        cleanKeyboard.stop()
        cleanScreen.stop()
    }

    /// Runs a utility, ignoring the request when the user has switched it off.
    func trigger(_ feature: WhizFeature) {
        guard preferences.isEnabled(feature) else { return }

        switch feature {
        case .awake:
            awake.toggle(defaultDuration: preferences.defaultAwakeDuration)
        case .colorPicker:
            colorPicker.pickColor()
        case .textExtractor:
            ocr.captureText()
        case .advancedPaste:
            advancedPaste.showHUD()
        case .clipboardHistory:
            ClipboardHistoryPresenter.shared.present(manager: clipboardHistory)
        case .batteryHealth:
            // A readout, not an action — opening its page is the only sensible response.
            pendingSettingsFeature = .batteryHealth
        case .cleanKeyboard, .cleanScreen:
            // Started from their own settings page, never from a shortcut or a menu
            // click — see `WhizFeature.isOnDemand`.
            break
        case .windowSnapping, .cropAndLock, .workspaces:
            break // Not implemented yet — menu rows for these are disabled.
        }
    }

    /// Permissions that a switched-on utility needs but does not have.
    var outstandingPermissions: [SystemPermission] {
        SystemPermission.allCases.filter { permission in
            guard !permissions.state(for: permission).isGranted else { return false }
            return permission.poweredFeatures.contains { feature in
                feature.availability == .shipping && preferences.isEnabled(feature)
            }
        }
    }
}
