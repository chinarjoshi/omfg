import UIKit
import Snap

// MARK: - Workout Index

struct WorkoutIndexEntry: Codable {
    let name: String
    let rawLine: String
    let date: String
    let filePath: String
}

final class WorkoutIndexManager {
    static let shared = WorkoutIndexManager()
    private var entries: [String: [WorkoutIndexEntry]] = [:]
    private var indexURL: URL?

    func configure(baseDirectory: URL) {
        indexURL = baseDirectory.appendingPathComponent("workout-index.json")
        load()
    }

    func update(parseResult: WorkoutResult, rawText: String, filePath: URL, baseDirectory: URL) {
        let relativePath = filePath.path.replacingOccurrences(of: baseDirectory.path + "/", with: "")
        let date = (filePath.deletingPathExtension().lastPathComponent)
        let lines = rawText.components(separatedBy: "\n")

        for exercise in parseResult.exercises {
            let key = exercise.name.lowercased()
            // Find the raw line for this exercise
            let rawLine = lines.first { $0.lowercased().contains(exercise.name.lowercased()) } ?? exercise.name
            let entry = WorkoutIndexEntry(name: exercise.name, rawLine: rawLine, date: date, filePath: relativePath)

            var list = entries[key] ?? []
            list.removeAll { $0.date == date && $0.filePath == relativePath }
            list.append(entry)
            list.sort { $0.date > $1.date }
            entries[key] = list
        }
        save()
    }

    func search(query: String) -> [WorkoutIndexEntry] {
        let q = query.lowercased()
        var results: [WorkoutIndexEntry] = []
        for (key, list) in entries {
            if key.contains(q) {
                results.append(contentsOf: list)
            }
        }
        return results.sorted { $0.date > $1.date }
    }

    func recent(limit: Int = 20) -> [WorkoutIndexEntry] {
        var all: [WorkoutIndexEntry] = []
        for list in entries.values {
            all.append(contentsOf: list)
        }
        all.sort { $0.date > $1.date }
        return Array(all.prefix(limit))
    }

    private func load() {
        guard let url = indexURL, let data = try? Data(contentsOf: url) else { return }
        entries = (try? JSONDecoder().decode([String: [WorkoutIndexEntry]].self, from: data)) ?? [:]
    }

    private func save() {
        guard let url = indexURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Table Attachment

final class WorkoutTableAttachment: NSTextAttachment {
    let rawText: String
    let parseResult: WorkoutResult

    init(rawText: String, parseResult: WorkoutResult) {
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

    private static func renderTable(_ result: WorkoutResult) -> UIImage {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxSets = result.exercises.map(\.sets.count).max() ?? 0
        let colCount = maxSets + 1

        // Build cell content
        var headerCells = [""]
        for i in 0..<maxSets { headerCells.append("\(i)") }

        var dataRows: [[String]] = []
        for exercise in result.exercises {
            var row = [exercise.name]
            var prevWeight: Int? = nil
            for s in exercise.sets {
                if s.weight > 0 && s.weight == prevWeight {
                    row.append("\(s.reps)")
                } else if s.weight > 0 {
                    row.append("\(s.reps)x\(s.weight)")
                } else {
                    row.append("\(s.reps)")
                }
                prevWeight = s.weight
            }
            while row.count < colCount { row.append("") }
            dataRows.append(row)
        }

        let allRows = [headerCells] + dataRows

        // Column widths from content, cap name column
        let maxNameWidth: CGFloat = 150
        var colWidths = Array(repeating: CGFloat(0), count: colCount)
        for row in allRows {
            for (i, cell) in row.enumerated() {
                let w = (cell as NSString).size(withAttributes: attrs).width
                colWidths[i] = max(colWidths[i], i == 0 ? min(w, maxNameWidth) : w)
            }
        }
        // Uniform set column widths
        if colCount > 1 {
            let maxSetWidth = colWidths[1...].max() ?? 0
            for i in 1..<colCount { colWidths[i] = maxSetWidth }
        }

        // Per-row heights (name column may wrap)
        let baseRowHeight = font.lineHeight + vPad * 2
        let nameColDrawWidth = colWidths[0] + hPad * 2
        var rowHeights: [CGFloat] = []
        for row in allRows {
            let nameText = row[0] as NSString
            let boundingRect = nameText.boundingRect(
                with: CGSize(width: nameColDrawWidth - hPad * 2, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs, context: nil
            )
            let needed = ceil(boundingRect.height) + vPad * 2
            rowHeights.append(max(baseRowHeight, needed))
        }

        let tableWidth = colWidths.reduce(0, +) + CGFloat(colCount) * hPad * 2 + CGFloat(colCount + 1) * gridWidth
        let tableHeight = rowHeights.reduce(0, +) + CGFloat(allRows.count + 1) * gridWidth

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

            var y = gridWidth
            for (rowIdx, row) in allRows.enumerated() {
                let rh = rowHeights[rowIdx]
                var x = gridWidth
                for (colIdx, cell) in row.enumerated() {
                    let cellWidth = colWidths[colIdx] + hPad * 2
                    let cellRect = CGRect(x: x, y: y, width: cellWidth, height: rh)

                    gridColor.setStroke()
                    UIBezierPath(rect: cellRect).stroke()

                    let textColor = rowIdx == 0 ? headerColor : cellColor
                    let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

                    if colIdx == 0 {
                        // Name column: draw with wrapping
                        let textRect = CGRect(x: x + hPad, y: y + vPad,
                                              width: cellWidth - hPad * 2, height: rh - vPad * 2)
                        (cell as NSString).draw(in: textRect, withAttributes: textAttrs)
                    } else {
                        let textSize = (cell as NSString).size(withAttributes: textAttrs)
                        (cell as NSString).draw(
                            at: CGPoint(x: x + hPad, y: y + (rh - textSize.height) / 2),
                            withAttributes: textAttrs
                        )
                    }

                    x += cellWidth + gridWidth
                }
                y += rh + gridWidth
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
    private let baseDirectory: URL
    private let filePath: () -> URL?

    init(textStorage: NSTextStorage, baseDirectory: URL, filePath: @escaping () -> URL?) {
        self.textStorage = textStorage
        self.baseDirectory = baseDirectory
        self.filePath = filePath
    }

    /// Returns the character count of prose lines at the start of a paragraph.
    private func proseCharCount(_ proseLines: [String], in paragraph: String) -> Int {
        guard !proseLines.isEmpty else { return 0 }
        var offset = 0
        for proseLine in proseLines {
            if (paragraph as NSString).substring(from: offset).hasPrefix(proseLine) {
                offset += (proseLine as NSString).length + 1 // +1 for \n
            } else {
                break
            }
        }
        return min(offset, (paragraph as NSString).length)
    }

    /// Re-renders :SNAP:...:END: blocks as workout table attachments.
    func renderAll() {
        guard !isTransforming else { return }
        guard let textStorage = textStorage else { return }

        let text = textStorage.string as NSString
        let pattern = try! NSRegularExpression(pattern: ":SNAP:\\n([\\s\\S]*?)\\n:END:", options: [])
        let matches = pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length))

        guard !matches.isEmpty else { return }

        isTransforming = true
        // Process in reverse so replacements don't shift earlier ranges
        for match in matches.reversed() {
            let fullRange = match.range
            let bodyRange = match.range(at: 1)
            let paragraph = text.substring(with: bodyRange)

            guard case .workout(let result) = snap(paragraph),
                  result.hasExercises else { continue }

            let attachment = WorkoutTableAttachment(rawText: paragraph, parseResult: result)
            textStorage.replaceCharacters(in: fullRange, with: NSAttributedString(attachment: attachment))
        }
        isTransforming = false
    }

    /// Called on text change. Replaces workout paragraphs with rendered table attachments.
    /// Returns cursor position to set after rendering, or nil if no render happened.
    func textChanged(renderAllowed: Bool = true, cursorPosition: Int? = nil) -> Int? {
        guard renderAllowed, !isTransforming else { return nil }
        guard let textStorage = textStorage else { return nil }
        let text = textStorage.string as NSString

        let checkPos = cursorPosition ?? text.length
        guard checkPos >= 2 else { return nil }
        let twoChars = text.substring(with: NSRange(location: checkPos - 2, length: 2))
        guard twoChars == "\n\n" else { return nil }

        let paragraphEnd = checkPos - 2
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

        let paragraph = text.substring(with: range)

        // Skip if already an attachment or table
        guard !paragraph.contains("\u{FFFC}") else { return nil }
        guard !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("|") else { return nil }

        guard case .workout(let parseResult) = snap(paragraph),
              parseResult.hasExercises else { return nil }

        // Keep prose lines as text, only replace exercise lines
        let proseLength = proseCharCount(parseResult.proseLines, in: paragraph)
        let exerciseRange = NSRange(location: range.location + proseLength, length: range.length - proseLength)
        let exerciseText = text.substring(with: exerciseRange)

        let attachment = WorkoutTableAttachment(rawText: exerciseText, parseResult: parseResult)
        let attachmentString = NSAttributedString(attachment: attachment)

        isTransforming = true
        textStorage.replaceCharacters(in: exerciseRange, with: attachmentString)
        isTransforming = false

        // Update workout index
        if let fp = filePath() {
            WorkoutIndexManager.shared.update(
                parseResult: parseResult,
                rawText: exerciseText,
                filePath: fp,
                baseDirectory: baseDirectory
            )
        }

        return exerciseRange.location + 2
    }
}
