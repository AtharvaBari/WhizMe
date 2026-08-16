import Foundation
import Observation

/// Owns the mapping between utilities and their global shortcuts, and keeps that
/// mapping persisted. `HotKeyService` does the Carbon work; this type decides
/// *what* is bound and exposes it to the UI.
@MainActor
@Observable
final class HotKeyManager {
    /// Currently bound shortcut per utility.
    private(set) var bindings: [WhizFeature: HotKey] = [:]

    /// Utilities whose shortcut could not be claimed — almost always a conflict with
    /// another app. Surfaced in Settings so the user is not left guessing.
    private(set) var conflicts: Set<WhizFeature> = []

    @ObservationIgnored private var tokens: [WhizFeature: UInt32] = [:]
    @ObservationIgnored private var actions: [WhizFeature: () -> Void] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let service: HotKeyService

    private static let storageKey = "hotKeyBindings"

    init(defaults: UserDefaults = .standard, service: HotKeyService = .shared) {
        self.defaults = defaults
        self.service = service
        self.bindings = Self.loadBindings(from: defaults)
    }

    /// Wires the closure a utility should run when its shortcut fires. Call before
    /// `activate()`.
    func setAction(for feature: WhizFeature, _ action: @escaping () -> Void) {
        actions[feature] = action
    }

    /// Claims every bound shortcut that has an action attached.
    func activate() {
        for (feature, hotKey) in bindings {
            register(feature, hotKey: hotKey)
        }
    }

    /// Replaces (or with `nil`, removes) the shortcut for a utility and persists it.
    func rebind(_ feature: WhizFeature, to hotKey: HotKey?) {
        if let token = tokens.removeValue(forKey: feature) {
            service.unregister(token)
        }
        conflicts.remove(feature)

        if let hotKey {
            bindings[feature] = hotKey
            register(feature, hotKey: hotKey)
        } else {
            bindings.removeValue(forKey: feature)
        }
        persist()
    }

    func hotKey(for feature: WhizFeature) -> HotKey? { bindings[feature] }

    func deactivate() {
        for token in tokens.values { service.unregister(token) }
        tokens.removeAll()
    }

    private func register(_ feature: WhizFeature, hotKey: HotKey) {
        guard let action = actions[feature] else { return }
        guard tokens[feature] == nil else { return }

        if let token = service.register(hotKey, action: action) {
            tokens[feature] = token
            conflicts.remove(feature)
        } else {
            conflicts.insert(feature)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func loadBindings(from defaults: UserDefaults) -> [WhizFeature: HotKey] {
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([WhizFeature: HotKey].self, from: data) {
            return stored
        }
        // First launch: seed the shipping defaults.
        return WhizFeature.shipping.reduce(into: [:]) { result, feature in
            result[feature] = HotKey.default(for: feature)
        }
    }
}
