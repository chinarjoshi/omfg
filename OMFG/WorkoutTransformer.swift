import UIKit
import WorkoutLiner

final class WorkoutTransformer {
    private weak var textStorage: NSTextStorage?

    init(textStorage: NSTextStorage) {
        self.textStorage = textStorage
    }

    /// Called on text change. Returns table range if transformation occurred.
    func textChanged() -> NSRange? {
        guard let textStorage = textStorage else { return nil }
        let text = textStorage.string as NSString

        // Check if last two characters are \n\n
        guard text.length >= 2 else { return nil }
        let lastTwo = text.substring(with: NSRange(location: text.length - 2, length: 2))
        guard lastTwo == "\n\n" else { return nil }

        // Find the paragraph before the double newline
        let paragraphEnd = text.length - 2
        guard paragraphEnd > 0 else { return nil }

        // Find paragraph start (previous \n\n or start of text)
        var paragraphStart = paragraphEnd
        let str = text as String
        while paragraphStart > 0 {
            if paragraphStart >= 2 {
                let idx = str.index(str.startIndex, offsetBy: paragraphStart - 1)
                let prevIdx = str.index(str.startIndex, offsetBy: paragraphStart - 2)
                if str[prevIdx] == "\n" && str[idx] == "\n" {
                    break
                }
            }
            paragraphStart -= 1
        }

        let range = NSRange(location: paragraphStart, length: paragraphEnd - paragraphStart)
        guard range.length > 0 else { return nil }

        return transformIfNeeded(in: range, text: text)
    }

    /// Returns the range of the inserted table if transformation occurred
    private func transformIfNeeded(in range: NSRange, text: NSString) -> NSRange? {
        guard let textStorage = textStorage else { return nil }

        let paragraph = text.substring(with: range)

        // Heuristic: skip if no numbers
        guard paragraph.contains(where: { $0.isNumber }) else { return nil }

        // Skip if already a table
        guard !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("|") else { return nil }

        let transformed = transform(paragraph)

        // Only replace if transformation produced a table
        if transformed != paragraph && transformed.contains("|") {
            let newContent = transformed + "\n"
            textStorage.replaceCharacters(in: range, with: newContent)
            return NSRange(location: range.location, length: (newContent as NSString).length)
        }
        return nil
    }
}
