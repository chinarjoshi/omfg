import UIKit

// MARK: - Navigation State

enum NoteLevel: Int {
    case daily, weekly, monthly, settings

    var next: NoteLevel? { NoteLevel(rawValue: rawValue + 1) }
    var previous: NoteLevel? { NoteLevel(rawValue: rawValue - 1) }
}

struct NavigationState {
    var level: NoteLevel
    var currentDate: Date

    static func today() -> NavigationState {
        NavigationState(level: .daily, currentDate: Date())
    }
}

// MARK: - Syntax Highlighting

private struct SyntaxRule {
    let pattern: NSRegularExpression
    let attributes: [NSAttributedString.Key: Any]
}

final class OrgTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()

    private static let rules: [SyntaxRule] = {
        func rule(
            _ pattern: String,
            _ options: NSRegularExpression.Options = [],
            color: UIColor? = nil,
            font: UIFont? = nil,
            underline: Bool = false,
            background: UIColor? = nil
        ) -> SyntaxRule {
            var attrs: [NSAttributedString.Key: Any] = [:]
            if let color = color { attrs[.foregroundColor] = color }
            if let font = font { attrs[.font] = font }
            if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let background = background { attrs[.backgroundColor] = background }
            return SyntaxRule(
                pattern: try! NSRegularExpression(pattern: pattern, options: options),
                attributes: attrs
            )
        }

        return [
            // Property drawers
            rule("^:PROPERTIES:$", .anchorsMatchLines, color: .gray, font: .systemFont(ofSize: 12)),
            rule("^:END:$", .anchorsMatchLines, color: .gray, font: .systemFont(ofSize: 12)),
            rule("^:(IMAGE|LOCATION):.*$", .anchorsMatchLines, color: .gray, font: .systemFont(ofSize: 12)),
            // Headers
            rule("^\\* .+$", .anchorsMatchLines, color: .white, font: .systemFont(ofSize: 24, weight: .bold)),
            rule("^\\*\\* .+$", .anchorsMatchLines, color: .white, font: .systemFont(ofSize: 20, weight: .bold)),
            rule("^\\*\\*\\* .+$", .anchorsMatchLines, color: .white, font: .systemFont(ofSize: 18, weight: .semibold)),
            // Keywords
            rule("\\bTODO\\b", color: .systemRed, font: .systemFont(ofSize: 16, weight: .bold)),
            rule("\\bDONE\\b", color: .systemGreen, font: .systemFont(ofSize: 16, weight: .bold)),
            // Links
            rule("\\[\\[[^\\]]+\\]\\]", color: .systemBlue, underline: true),
            // Formatting
            rule("(?<=\\s|^)\\*[^\\*\\n]+\\*(?=\\s|$)", .anchorsMatchLines, font: .systemFont(ofSize: 16, weight: .bold)),
            rule("(?<=\\s|^)/[^/\\n]+/(?=\\s|$)", .anchorsMatchLines, font: .italicSystemFont(ofSize: 16)),
            // Timestamps
            rule("<[^>]+>", color: .systemPurple, background: UIColor.systemPurple.withAlphaComponent(0.1)),
            // Table lines - monospace font for alignment (text stays white)
            rule("^\\|.+\\|$", .anchorsMatchLines, font: .monospacedSystemFont(ofSize: 16, weight: .regular)),
            // Table separator rows (lines with dashes between pipes) - dark grey
            rule("^\\|[-| ]+\\|$", .anchorsMatchLines, color: UIColor(white: 0.4, alpha: 1)),
            // Table borders (pipe characters) - dark grey (must come after other table rules)
            rule("\\|", color: UIColor(white: 0.4, alpha: 1), font: .monospacedSystemFont(ofSize: 16, weight: .regular)),
            // Horizontal rule (3+ dashes on their own line)
            rule("^-{3,}$", .anchorsMatchLines, color: .gray),
        ]
    }()

    override var string: String {
        backingStore.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func replaceCharacters(in range: NSRange, with attrString: NSAttributedString) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: attrString)
        edited([.editedCharacters, .editedAttributes], range: range, changeInLength: attrString.length - range.length)
        endEditing()
    }

    /// Returns string content with attachment characters replaced by their raw text.
    var fileContent: String {
        var result = ""
        let text = string as NSString
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length), options: []) { value, range, _ in
            if let attachment = value as? WorkoutTableAttachment {
                result += attachment.rawText
            } else {
                result += text.substring(with: range)
            }
        }
        return result
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        // Expand to cover all lines affected by the edit (handles multi-line inserts)
        let text = string as NSString
        let start = text.lineRange(for: NSRange(location: editedRange.location, length: 0)).location
        let end = NSMaxRange(text.lineRange(for: NSRange(location: NSMaxRange(editedRange), length: 0)))
        let affectedRange = NSRange(location: start, length: end - start)

        applyDefaultAttributes(in: affectedRange)
        applySyntaxHighlighting(in: affectedRange)
        super.processEditing()
    }

    private func applyDefaultAttributes(in range: NSRange) {
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.white
        ]
        backingStore.setAttributes(defaultAttrs, range: range)
    }

    private func applySyntaxHighlighting(in range: NSRange) {
        let text = string
        for rule in Self.rules {
            rule.pattern.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                backingStore.addAttributes(rule.attributes, range: matchRange)
            }
        }
    }
}

// MARK: - Editor

final class EditorViewController: UIViewController {
    private let textStorage: OrgTextStorage
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let textView: UITextView
    private let titleLabel: UILabel

    private let baseDirectory: URL
    private let calendar = Calendar.current

    private var currentState: NavigationState
    private var currentFilePath: URL?

    // Sync: unified save/reload
    private var lastSyncedContent: String = ""
    private var syncWorkItem: DispatchWorkItem?
    private var syncTimer: Timer?
    private var isSyncing = false

    // Elastic pull navigation
    private let overscrollThreshold: CGFloat = 25
    private var isOverscrolling = false

    // Table auto-formatting
    private var previousTableRange: NSRange?

    // Workout transformation
    private lazy var workoutTransformer = WorkoutTransformer(textStorage: textStorage)


    var onRequestSettings: (() -> Void)?

    init(baseDirectory: URL, initialState: NavigationState = .today()) {
        self.baseDirectory = baseDirectory
        self.currentState = initialState

        self.textStorage = OrgTextStorage()
        self.layoutManager = NSLayoutManager()
        self.textContainer = NSTextContainer()

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        self.textView = UITextView(frame: .zero, textContainer: textContainer)
        self.titleLabel = UILabel()

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    deinit {
        syncTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureTitleLabel()
        configureTextView()
        configureSwipeGestures()
        loadNote(for: currentState)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sync()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safeArea = view.safeAreaInsets
        let titleHeight: CGFloat = 44
        titleLabel.frame = CGRect(
            x: 16,
            y: safeArea.top,
            width: view.bounds.width - 32,
            height: titleHeight
        )
        textView.frame = CGRect(
            x: 0,
            y: safeArea.top + titleHeight,
            width: view.bounds.width,
            height: view.bounds.height - safeArea.top - titleHeight
        )
        textContainer.size = CGSize(
            width: view.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right,
            height: .greatestFiniteMagnitude
        )
    }

    private func configureTitleLabel() {
        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = .gray
        titleLabel.textAlignment = .left
        view.addSubview(titleLabel)
    }

    private func configureTextView() {
        textView.backgroundColor = .black
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.delegate = self
        view.addSubview(textView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardHeight = keyboardFrame.height - view.safeAreaInsets.bottom
        textView.contentInset.bottom = keyboardHeight
        textView.verticalScrollIndicatorInsets.bottom = keyboardHeight
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        textView.contentInset.bottom = 0
        textView.verticalScrollIndicatorInsets.bottom = 0
    }

    // MARK: - Swipe Navigation

    private func configureSwipeGestures() {
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleHorizontalSwipe(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)

            // Make scroll view's pan wait for swipe to fail
            textView.panGestureRecognizer.require(toFail: swipe)
        }
    }

    @objc private func handleHorizontalSwipe(_ gesture: UISwipeGestureRecognizer) {
        var newState = currentState

        if gesture.direction == .left {
            newState.currentDate = nextDate(from: currentState.currentDate, at: currentState.level)
        } else {
            newState.currentDate = previousDate(from: currentState.currentDate, at: currentState.level)
        }

        if newState.currentDate != currentState.currentDate {
            textView.resignFirstResponder()
            loadNote(for: newState)
        }
    }

    // MARK: - Path Resolution

    private func path(for state: NavigationState) -> URL? {
        let c = calendar.dateComponents([.year, .month, .day, .weekOfYear], from: state.currentDate)
        let filename: String
        let folder: String

        switch state.level {
        case .daily:
            filename = String(format: "%04d-%02d-%02d.org", c.year!, c.month!, c.day!)
            folder = "daily"
        case .weekly:
            filename = String(format: "%04d-W%02d.org", c.year!, c.weekOfYear!)
            folder = "weekly"
        case .monthly:
            filename = String(format: "%04d-%02d.org", c.year!, c.month!)
            folder = "monthly"
        case .settings:
            return nil
        }
        return baseDirectory.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(filename)
    }

    private func previousDate(from date: Date, at level: NoteLevel) -> Date {
        switch level {
        case .daily: return calendar.date(byAdding: .day, value: -1, to: date) ?? date
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: -1, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .settings: return date
        }
    }

    private func nextDate(from date: Date, at level: NoteLevel) -> Date {
        switch level {
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .settings: return date
        }
    }

    private static let shortMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private func displayTitle(for state: NavigationState) -> String {
        let c = calendar.dateComponents([.day, .weekOfYear], from: state.currentDate)
        switch state.level {
        case .daily:
            return "\(c.day!)"
        case .weekly:
            return "W\(c.weekOfYear!)"
        case .monthly:
            return Self.shortMonthFormatter.string(from: state.currentDate)
        case .settings:
            return "Settings"
        }
    }

    private func ensureNoteExists(for state: NavigationState) {
        guard let url = path(for: state) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    // MARK: - Note Loading

    private func loadNote(for state: NavigationState) {
        sync()
        currentState = state

        guard state.level != .settings else {
            onRequestSettings?()
            return
        }

        currentFilePath = path(for: state)
        ensureNoteExists(for: state)
        titleLabel.text = displayTitle(for: state)

        let content: String
        if let path = currentFilePath, let fileContent = try? String(contentsOf: path, encoding: .utf8) {
            content = fileContent
        } else {
            content = ""
        }
        syncWorkItem?.cancel()
        syncWorkItem = nil
        isSyncing = true
        lastSyncedContent = content
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: content)
        isSyncing = false
        textView.contentOffset = .zero
    }

    func returnFromSettings() {
        if currentState.level == .settings {
            currentState.level = .monthly
        }
        loadNote(for: currentState)
    }

    // MARK: - Sync

    /// Unified sync: reconciles editor content with file on disk.
    /// Called on keypress (debounced), every 2 seconds, and on navigation.
    func sync() {
        guard !isSyncing, let path = currentFilePath else { return }
        isSyncing = true
        defer { isSyncing = false }

        let editorContent = textStorage.fileContent
        let diskContent = (try? String(contentsOf: path, encoding: .utf8)) ?? ""

        let localChanged = editorContent != lastSyncedContent
        let remoteChanged = diskContent != lastSyncedContent

        if localChanged && remoteChanged {
            guard editorContent != diskContent else {
                lastSyncedContent = editorContent
                return
            }
            let merged = Self.merge(base: lastSyncedContent, local: editorContent, remote: diskContent)
            lastSyncedContent = merged
            try? merged.write(to: path, atomically: true, encoding: .utf8)
            if merged != editorContent {
                let sel = textView.selectedRange
                textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: merged)
                let max = textStorage.length
                textView.selectedRange = NSRange(
                    location: min(sel.location, max),
                    length: min(sel.length, max - min(sel.location, max))
                )
            }
        } else if localChanged {
            guard editorContent != diskContent else {
                lastSyncedContent = editorContent
                return
            }
            lastSyncedContent = editorContent
            try? editorContent.write(to: path, atomically: true, encoding: .utf8)
        } else if remoteChanged {
            lastSyncedContent = diskContent
            let sel = textView.selectedRange
            textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: diskContent)
            let max = textStorage.length
            textView.selectedRange = NSRange(
                location: min(sel.location, max),
                length: min(sel.length, max - min(sel.location, max))
            )
        }
    }

    static func merge(base: String, local: String, remote: String) -> String {
        let baseLines = base.components(separatedBy: "\n")
        let localLines = local.components(separatedBy: "\n")
        let remoteLines = remote.components(separatedBy: "\n")

        var prefixLen = 0
        let minPrefix = min(baseLines.count, min(localLines.count, remoteLines.count))
        while prefixLen < minPrefix
            && baseLines[prefixLen] == localLines[prefixLen]
            && baseLines[prefixLen] == remoteLines[prefixLen] {
            prefixLen += 1
        }

        var suffixLen = 0
        let maxSuffix = min(baseLines.count - prefixLen,
                            min(localLines.count - prefixLen, remoteLines.count - prefixLen))
        while suffixLen < maxSuffix
            && baseLines[baseLines.count - 1 - suffixLen] == localLines[localLines.count - 1 - suffixLen]
            && baseLines[baseLines.count - 1 - suffixLen] == remoteLines[remoteLines.count - 1 - suffixLen] {
            suffixLen += 1
        }

        let prefix = Array(baseLines.prefix(prefixLen))
        let suffix = suffixLen > 0 ? Array(baseLines.suffix(suffixLen)) : []
        let remoteMiddle = Array(remoteLines[prefixLen ..< (remoteLines.count - suffixLen)])
        let localMiddle = Array(localLines[prefixLen ..< (localLines.count - suffixLen)])

        var merged = prefix
        merged += remoteMiddle
        merged += localMiddle
        merged += suffix
        return merged.joined(separator: "\n")
    }

    /// Schedule a sync after a short debounce (called on keypress).
    private func scheduleSyncSoon() {
        syncWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.sync() }
        syncWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: - Table Auto-Formatting

    private func tableRange(at position: Int) -> NSRange? {
        let text = textStorage.string as NSString
        guard position <= text.length else { return nil }

        func isTableLine(at loc: Int) -> Bool {
            let range = text.lineRange(for: NSRange(location: loc, length: 0))
            let line = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            return line.hasPrefix("|") && line.hasSuffix("|")
        }

        guard isTableLine(at: position) else { return nil }

        var start = text.lineRange(for: NSRange(location: position, length: 0)).location
        var end = NSMaxRange(text.lineRange(for: NSRange(location: position, length: 0)))

        while start > 0 && isTableLine(at: start - 1) {
            start = text.lineRange(for: NSRange(location: start - 1, length: 0)).location
        }
        while end < text.length && isTableLine(at: end) {
            end = NSMaxRange(text.lineRange(for: NSRange(location: end, length: 0)))
        }

        return NSRange(location: start, length: end - start)
    }

    private func formatTable(in range: NSRange) {
        let text = textStorage.string as NSString
        let lines = text.substring(with: range).components(separatedBy: "\n").filter { !$0.isEmpty }

        let rows = lines.map { line -> [String] in
            String(line.trimmingCharacters(in: .whitespaces).dropFirst().dropLast())
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }

        guard let columnCount = rows.map(\.count).max(), columnCount > 0 else { return }

        func isSeparatorCell(_ cell: String) -> Bool {
            !cell.isEmpty && cell.allSatisfy({ $0 == "-" })
        }

        // Calculate widths (skip separator rows)
        var widths = Array(repeating: 1, count: columnCount)
        for row in rows {
            for (i, cell) in row.enumerated() where !isSeparatorCell(cell) {
                widths[i] = max(widths[i], cell.count)
            }
        }

        let formatted = rows.map { row -> String in
            let cells = (0..<columnCount).map { i -> String in
                let cell = i < row.count ? row[i] : ""
                return isSeparatorCell(cell)
                    ? String(repeating: "-", count: widths[i])
                    : cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }.joined(separator: "\n")

        if formatted + "\n" != text.substring(with: range) {
            textStorage.replaceCharacters(in: range, with: formatted + "\n")
        }
    }
}

extension EditorViewController: UITextViewDelegate {
    func textViewDidChangeSelection(_ textView: UITextView) {
        let cursorPosition = textView.selectedRange.location

        // Table auto-formatting
        let currentTableRange = tableRange(at: cursorPosition)
        if let prevRange = previousTableRange,
           currentTableRange?.location != prevRange.location {
            formatTable(in: prevRange)
        }
        previousTableRange = currentTableRange

    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Backspace into attachment: restore raw text
        if text.isEmpty && range.length == 1 && range.location < textStorage.length {
            let attrs = textStorage.attributes(at: range.location, effectiveRange: nil)
            if let attachment = attrs[.attachment] as? WorkoutTableAttachment {
                textStorage.replaceCharacters(in: range, with: attachment.rawText)
                textView.selectedRange = NSRange(location: range.location + (attachment.rawText as NSString).length, length: 0)
                scheduleSyncSoon()
                return false
            }
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isSyncing else { return }

        workoutTransformer.textChanged()
        scheduleSyncSoon()

        if let selectedRange = textView.selectedTextRange {
            var caretRect = textView.caretRect(for: selectedRange.end)
            caretRect.size.height += 8
            textView.scrollRectToVisible(caretRect, animated: false)
        }
    }

    // MARK: - Elastic Pull Navigation

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        // Pulling down at top (negative offset)
        if offsetY < -overscrollThreshold {
            isOverscrolling = true
        }
        // Pulling up at bottom (past max)
        else if offsetY > maxOffset + overscrollThreshold {
            isOverscrolling = true
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard isOverscrolling else { return }
        isOverscrolling = false

        let offsetY = scrollView.contentOffset.y
        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        if offsetY < -overscrollThreshold {
            // Pulled down past threshold → go to next level (weekly/monthly/settings)
            navigateToNextLevel()
        } else if offsetY > maxOffset + overscrollThreshold {
            // Pulled up past threshold → go to previous level
            navigateToPreviousLevel()
        }
    }

    private func navigateToNextLevel() {
        guard let nextLevel = currentState.level.next else { return }
        animateNavigation(to: nextLevel, direction: .down)
    }

    private func navigateToPreviousLevel() {
        guard let prevLevel = currentState.level.previous else { return }
        animateNavigation(to: prevLevel, direction: .up)
    }

    private enum NavigationDirection { case up, down }

    private func animateNavigation(to level: NoteLevel, direction: NavigationDirection) {
        textView.resignFirstResponder()

        // Handle settings specially
        if level == .settings {
            sync()
            currentState.level = level
            onRequestSettings?()
            return
        }

        // Slide current content out
        let exitY: CGFloat = direction == .up ? -view.bounds.height : view.bounds.height
        UIView.animate(withDuration: 0.05) {
            self.view.transform = CGAffineTransform(translationX: 0, y: exitY)
        } completion: { _ in
            // Load new content
            self.currentState.level = level
            self.loadNote(for: self.currentState)

            // Stop any scroll momentum and reset position
            self.textView.setContentOffset(.zero, animated: false)

            // Position off-screen on opposite side, then animate in
            let enterY: CGFloat = direction == .up ? self.view.bounds.height : -self.view.bounds.height
            self.view.transform = CGAffineTransform(translationX: 0, y: enterY)

            UIView.animate(withDuration: 0.06, delay: 0, options: .curveEaseOut) {
                self.view.transform = .identity
            }
        }
    }
}
