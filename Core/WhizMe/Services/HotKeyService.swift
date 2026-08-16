import Carbon.HIToolbox
import os

/// Process-wide global hotkey registration built on Carbon's `RegisterEventHotKey`.
///
/// Carbon is the only API that delivers system-wide hotkeys **without** requiring
/// Accessibility permission — `CGEventTap` and `NSEvent.addGlobalMonitorForEvents`
/// both do. That matters here: Awake and Color Picker need zero TCC grants, so their
/// shortcuts must not silently drag in an Accessibility prompt.
///
/// All access is main-actor isolated; Carbon delivers hotkey events on the main run
/// loop, which is what makes the `assumeIsolated` hop in the C trampoline sound.
@MainActor
final class HotKeyService {
    static let shared = HotKeyService()

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextIdentifier: UInt32 = 1
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "HotKeys")

    /// Four-char code identifying hotkeys owned by this app.
    private static let signature: OSType = 0x574D_455A // 'WMEZ'

    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private init() {}

    /// Registers `hotKey` system-wide.
    /// - Returns: A token used to unregister, or `nil` if the combination was
    ///   rejected (most often because another app already owns it).
    @discardableResult
    func register(_ hotKey: HotKey, action: @escaping () -> Void) -> UInt32? {
        installEventHandlerIfNeeded()

        let identifier = nextIdentifier
        nextIdentifier += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey failed for \(hotKey.displayString, privacy: .public) (OSStatus \(status))")
            return nil
        }

        registrations[identifier] = Registration(ref: ref, action: action)
        return identifier
    }

    func unregister(_ identifier: UInt32) {
        guard let registration = registrations.removeValue(forKey: identifier) else { return }
        UnregisterEventHotKey(registration.ref)
    }

    func unregisterAll() {
        for identifier in registrations.keys { unregister(identifier) }
    }

    /// Invoked from the Carbon trampoline below.
    fileprivate func handleHotKey(id identifier: UInt32) {
        registrations[identifier]?.action()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventTrampoline,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        if status != noErr {
            log.error("InstallEventHandler failed (OSStatus \(status)) — global shortcuts are inactive")
        }
    }
}

/// C callback Carbon invokes on the main run loop when one of our hotkeys fires.
/// `@convention(c)` blocks capture, so it re-enters the singleton by hand.
private let hotKeyEventTrampoline: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let identifier = hotKeyID.id
    MainActor.assumeIsolated {
        HotKeyService.shared.handleHotKey(id: identifier)
    }
    return noErr
}
