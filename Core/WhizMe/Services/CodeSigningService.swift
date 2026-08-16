import Foundation
import Security

/// Reports how the running copy of WhizMe is signed.
///
/// This exists for one reason: macOS keys privacy grants to an app's *designated
/// requirement*. For an ad-hoc signed build that requirement is `cdhash H"…"` — a
/// hash of the binary — so every rebuild produces an app that TCC has never seen and
/// the previously granted permissions stop applying. System Settings keeps showing
/// the toggle as ON, because that row belongs to the previous build, which makes the
/// failure look like a macOS bug rather than a signing one.
///
/// WhizMe detects the situation and says so in the onboarding window, instead of
/// letting a developer re-grant Screen Recording after every build wondering why it
/// never sticks.
enum CodeSigningService {
    /// `true` when this build was signed with `codesign -s -` and therefore loses its
    /// privacy grants on every rebuild.
    static let isAdHocSigned: Bool = signingInfo().certificateCount == 0

    /// Team identifier from the signing certificate, `nil` for ad-hoc or self-signed.
    static let teamIdentifier: String? = signingInfo().teamIdentifier

    private static func signingInfo() -> (certificateCount: Int, teamIdentifier: String?) {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            // Unsigned or unreadable — treat as ad-hoc so the warning still shows.
            return (0, nil)
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return (0, nil)
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let details = information as? [String: Any] else {
            return (0, nil)
        }

        // Ad-hoc signatures carry no certificate chain at all. A self-signed
        // certificate produces a one-element chain and no team identifier, which is
        // enough for TCC to hold a stable grant — so certificate count, not team id,
        // is the thing worth warning about.
        let certificates = details[kSecCodeInfoCertificates as String] as? [Any] ?? []
        let team = details[kSecCodeInfoTeamIdentifier as String] as? String
        return (certificates.count, team)
    }
}
