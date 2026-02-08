import UIKit
import WorkoutLiner

final class WorkoutTransformer {
    private weak var textStorage: NSTextStorage?
    private var previousParagraphRange: NSRange?

    init(textStorage: NSTextStorage) {
        self.textStorage = textStorage
    }

    /// Returns the range of an inserted table if transformation occurred, nil otherwise
    func selectionChanged(to position: Int) -> NSRange? {
        guard let textStorage = textStorage else { return nil }
        let text = textStorage.string as NSString

        let currentParagraph = paragraphRange(in: text, at: position)

        var insertedTableRange: NSRange?
        if let prevRange = previousParagraphRange,
           currentParagraph?.location != prevRange.location {
            insertedTableRange = transformIfNeeded(in: prevRange, text: text)
        }

        previousParagraphRange = currentParagraph
        return insertedTableRange
    }

    private func paragraphRange(in text: NSString, at position: Int) -> NSRange? {
        guard position <= text.length else { return nil }

        let str = text as String

        // Find block boundaries (separated by blank lines: \n\n)
        var start = position
        while start > 0 {
            let idx = str.index(str.startIndex, offsetBy: start - 1)
            if start >= 2 {
                let prevIdx = str.index(str.startIndex, offsetBy: start - 2)
                if str[prevIdx] == "\n" && str[idx] == "\n" {
                    break
                }
            }
            start -= 1
        }

        var end = position
        while end < text.length - 1 {
            let idx = str.index(str.startIndex, offsetBy: end)
            let nextIdx = str.index(str.startIndex, offsetBy: end + 1)
            if str[idx] == "\n" && str[nextIdx] == "\n" {
                end += 1
                break
            }
            end += 1
        }
        if end < text.length {
            end = min(end + 1, text.length)
        }

        return NSRange(location: start, length: end - start)
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
