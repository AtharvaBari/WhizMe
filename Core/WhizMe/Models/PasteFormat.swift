import Foundation
import SwiftUI

/// Formats available for the Advanced Paste feature.
enum PasteFormat: String, CaseIterable, Identifiable, Sendable {
    case plainText
    case markdown
    case json
    case ocrText
    case uppercase
    case lowercase
    case titleCase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plainText: "Plain Text"
        case .markdown: "Markdown"
        case .json: "JSON Formatting"
        case .ocrText: "Extract Text (OCR)"
        case .uppercase: "UPPERCASE"
        case .lowercase: "lowercase"
        case .titleCase: "Title Case"
        }
    }

    var subtitle: String {
        switch self {
        case .plainText: "Strip all rich text and HTML"
        case .markdown: "Convert rich text/HTML to Markdown"
        case .json: "Pretty-print valid JSON"
        case .ocrText: "Read text from image on clipboard"
        case .uppercase: "Convert text to all caps"
        case .lowercase: "Convert text to lowercase"
        case .titleCase: "Capitalize the first letter of each word"
        }
    }

    var symbolName: String {
        switch self {
        case .plainText: "text.alignleft"
        case .markdown: "m.square"
        case .json: "curlybraces"
        case .ocrText: "text.viewfinder"
        case .uppercase: "textformat.size.larger"
        case .lowercase: "textformat.size.smaller"
        case .titleCase: "textformat.size"
        }
    }
}
