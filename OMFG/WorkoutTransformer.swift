import UIKit
import WorkoutLiner

// MARK: - Table Attachment

final class WorkoutTableAttachment: NSTextAttachment {
    let rawText: String
    let parseResult: ParseResult

    init(rawText: String, parseResult: ParseResult) {
        self.rawText = rawText
        self.parseResult = parseResult
        super.init(data: nil, ofType: nil)
        self.image = Self.renderTable(parseResult)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - Table Rendering

    private static let font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    private static let headerColor = UIColor.gray
    private static let cellColor = UIColor.white
    private static let gridColor = UIColor(white: 0.4, alpha: 1)
    private static let bgColor = UIColor.black
    private static let hPad: CGFloat = 8
    private static let vPad: CGFloat = 6
    private static let gridWidth: CGFloat = 1

    private static func renderTable(_ result: ParseResult) -> UIImage {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxSets = result.exercises.map(\.sets.count).max() ?? 0
        let colCount = maxSets + 1

        // Build cell content
        var headerCells = [""]
        for i in 0..<maxSets { headerCells.append("\(i)") }

        var dataRows: [[String]] = []
        for exercise in result.exercises {
            var row = [exercise.name]
            for s in exercise.sets {
                row.append(s.weight > 0 ? "\(s.reps)@\(s.weight)" : "\(s.reps)")
            }
            while row.count < colCount { row.append("") }
            dataRows.append(row)
        }

        let allRows = [headerCells] + dataRows

        // Column widths from content
        var colWidths = Array(repeating: CGFloat(0), count: colCount)
        for row in allRows {
            for (i, cell) in row.enumerated() {
                colWidths[i] = max(colWidths[i], (cell as NSString).size(withAttributes: attrs).width)
            }
        }

        let rowHeight = font.lineHeight + vPad * 2
        let tableWidth = colWidths.reduce(0, +) + CGFloat(colCount) * hPad * 2 + CGFloat(colCount + 1) * gridWidth
        let tableHeight = CGFloat(allRows.count) * rowHeight + CGFloat(allRows.count + 1) * gridWidth

        // Notes below table
        var notesLines: [String] = []
        for exercise in result.exercises {
            let notes = exercise.sets.compactMap { $0.note.isEmpty ? nil : $0.note }
            if !notes.isEmpty {
                notesLines.append("- \(exercise.name) :: \(notes.joined(separator: ". "))")
            }
        }

        let notesHeight: CGFloat = notesLines.isEmpty ? 0 : CGFloat(notesLines.count) * (font.lineHeight + 4) + 8
        let totalSize = CGSize(width: tableWidth, height: tableHeight + notesHeight)

        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { _ in
            bgColor.setFill()
            UIRectFill(CGRect(origin: .zero, size: totalSize))

            for (rowIdx, row) in allRows.enumerated() {
                let y = CGFloat(rowIdx) * rowHeight + CGFloat(rowIdx + 1) * gridWidth
                var x = gridWidth
                for (colIdx, cell) in row.enumerated() {
                    let cellWidth = colWidths[colIdx] + hPad * 2
                    let cellRect = CGRect(x: x, y: y, width: cellWidth, height: rowHeight)

                    gridColor.setStroke()
                    UIBezierPath(rect: cellRect).stroke()

                    let textColor = rowIdx == 0 ? headerColor : cellColor
                    let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                    let textSize = (cell as NSString).size(withAttributes: textAttrs)
                    (cell as NSString).draw(
                        at: CGPoint(x: x + hPad, y: y + (rowHeight - textSize.height) / 2),
                        withAttributes: textAttrs
                    )

                    x += cellWidth + gridWidth
                }
            }

            if !notesLines.isEmpty {
                let noteAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.gray]
                for (i, line) in notesLines.enumerated() {
                    let y = tableHeight + 8 + CGFloat(i) * (font.lineHeight + 4)
                    (line as NSString).draw(at: CGPoint(x: 0, y: y), withAttributes: noteAttrs)
                }
            }
        }
    }
}

// MARK: - Transformer

final class WorkoutTransformer {
    private weak var textStorage: NSTextStorage?
    private var isTransforming = false

    init(textStorage: NSTextStorage) {
        self.textStorage = textStorage
    }

    /// Called on text change. Replaces workout paragraphs with rendered table attachments.
    func textChanged() {
        guard !isTransforming else { return }
        guard let textStorage = textStorage else { return }
        let text = textStorage.string as NSString

        guard text.length >= 2 else { return }
        let lastTwo = text.substring(with: NSRange(location: text.length - 2, length: 2))
        guard lastTwo == "\n\n" else { return }

        let paragraphEnd = text.length - 2
        guard paragraphEnd > 0 else { return }

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
        guard range.length > 0 else { return }

        let paragraph = text.substring(with: range)

        // Skip if already an attachment or table
        guard !paragraph.contains("\u{FFFC}") else { return }
        guard !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("|") else { return }

        let results = transform(paragraph)
        guard let first = results.first else { return }

        switch first {
        case .prose:
            return
        case .workout(let parseResult):
            guard parseResult.hasExercises else { return }
            let attachment = WorkoutTableAttachment(rawText: paragraph, parseResult: parseResult)
            let attachmentString = NSAttributedString(attachment: attachment)

            isTransforming = true
            textStorage.replaceCharacters(in: range, with: attachmentString)
            isTransforming = false
        }
    }
}
