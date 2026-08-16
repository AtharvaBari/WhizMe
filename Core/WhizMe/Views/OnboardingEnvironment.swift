import SwiftUI

/// Dismissal hook for the onboarding window.
///
/// SwiftUI's `\.dismiss` is a no-op inside a view hosted in a plain `NSWindow`, so
/// `OnboardingPresenter` injects the real close action here instead.
extension EnvironmentValues {
    @Entry var dismissOnboarding: @MainActor @Sendable () -> Void = {}
}
