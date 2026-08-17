import SwiftUI
import AppKit

@MainActor
@Observable
final class AdvancedPasteManager {
    private let permissions: PermissionManager
    // using NotificationService.shared directly instead of holding a reference
    
    var isHUDPresented = false
    var availableFormats: [PasteFormat] = []
    
    // The floating panel for the HUD
    private var hudWindow: NSPanel?

    init(permissions: PermissionManager) {
        self.permissions = permissions
    }

    /// Triggers the feature, checks clipboard, and shows the HUD if valid.
    func showHUD() {
        // Evaluate what formats are available based on clipboard
        var formats: [PasteFormat] = []
        
        if ClipboardService.hasImage {
            formats.append(.ocrText)
        }
        
        if ClipboardService.hasText {
            formats.append(contentsOf: [.plainText, .markdown, .json, .uppercase, .lowercase, .titleCase])
        }
        
        guard !formats.isEmpty else {
            NotificationService.shared.post(title: "Advanced Paste", body: "No supported content on clipboard.")
            return
        }
        
        self.availableFormats = formats
        
        // Present the HUD
        if hudWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isOpaque = false
            self.hudWindow = panel
        }
        
        // Position at cursor
        if let window = hudWindow {
            let mouseLoc = NSEvent.mouseLocation
            window.setFrameTopLeftPoint(NSPoint(x: mouseLoc.x - 150, y: mouseLoc.y))
            
            // We inject self into the view so it can call transformAndPaste
            let view = NSHostingView(rootView: AdvancedPasteHUDView(manager: self))
            window.contentView = view
            
            // Order front WITHOUT activating. This is the whole point of
            // `.nonactivatingPanel`, and activating here would defeat it: the paste
            // below targets whatever app is frontmost, so stealing focus makes WhizMe
            // the paste target and the user's text lands nowhere. Leaving the original
            // app frontmost is also what lets `isTextInputFocused` read *its* focused
            // element rather than ours.
            window.orderFrontRegardless()
            self.isHUDPresented = true
        }
    }

    func hideHUD() {
        hudWindow?.orderOut(nil)
        isHUDPresented = false
    }

    /// Performs transformation and simulates pasting.
    func transformAndPaste(format: PasteFormat) {
        hideHUD()
        
        Task {
            do {
                let transformedText: String?
                
                switch format {
                case .plainText:
                    transformedText = ClipboardService.currentString
                case .markdown:
                    let html = ClipboardService.currentHTML
                    transformedText = ClipboardService.convertToMarkdown(from: html) ?? ClipboardService.currentString
                case .json:
                    let string = ClipboardService.currentString
                    transformedText = ClipboardService.formatJSON(string) ?? string
                case .ocrText:
                    if let image = ClipboardService.currentImage {
                        transformedText = try await TextRecognitionService.recognizeText(in: image)
                    } else {
                        transformedText = nil
                    }
                case .uppercase:
                    transformedText = ClipboardService.currentString?.uppercased()
                case .lowercase:
                    transformedText = ClipboardService.currentString?.lowercased()
                case .titleCase:
                    transformedText = ClipboardService.currentString?.capitalized
                }
                
                guard let finalString = transformedText, !finalString.isEmpty else {
                    NotificationService.shared.post(title: "Advanced Paste", body: "Transformation yielded no text.")
                    return
                }
                
                // Copy to clipboard
                ClipboardService.copy(finalString)
                
                // Re-read rather than trusting the cache, the way every other manager
                // does: polling stops once nothing is missing, so a grant made in
                // System Settings since the last check would otherwise read as denied
                // and silently downgrade to "copied, paste it yourself".
                permissions.refresh()

                // Simulate Paste or Notify
                if permissions.state(for: .accessibility).isGranted {
                    if ClipboardService.isTextInputFocused {
                        // Small delay to ensure HUD is fully dismissed and target app is focused
                        try await Task.sleep(for: .milliseconds(150))
                        ClipboardService.simulatePaste()
                    } else {
                        NotificationService.shared.post(
                            title: "Copied!",
                            body: "No text input focused. Formatted text is on your clipboard."
                        )
                    }
                } else {
                    NotificationService.shared.post(
                        title: "Copied!",
                        body: "Grant Accessibility permission to auto-paste."
                    )
                }
                
            } catch {
                NotificationService.shared.post(title: "Advanced Paste Failed", body: error.localizedDescription)
            }
        }
    }
}
