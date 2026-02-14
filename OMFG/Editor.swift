import UIKit

// MARK: - Navigation State

enum NoteLevel: Int {
    case search, daily, weekly, monthly, settings

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

    /// Returns string content with attachment characters replaced by their raw text wrapped in :SNAP:/:END:.
    var fileContent: String {
        var result = ""
        let text = string as NSString
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length), options: []) { value, range, _ in
            if let attachment = value as? WorkoutTableAttachment {
                result += ":SNAP:\n\(attachment.rawText)\n:END:"
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
        // Save attachments before overwriting — setAttributes strips all existing attributes
        var attachments: [(NSTextAttachment, NSRange)] = []
        backingStore.enumerateAttribute(.attachment, in: range, options: []) { value, r, _ in
            if let a = value as? NSTextAttachment { attachments.append((a, r)) }
        }
        backingStore.setAttributes(defaultAttrs, range: range)
        for (a, r) in attachments {
            backingStore.addAttribute(.attachment, value: a, range: r)
        }
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
    private let galleryView = PhotoGalleryView()

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
    private lazy var workoutTransformer = WorkoutTransformer(
        textStorage: textStorage,
        baseDirectory: baseDirectory,
        filePath: { [weak self] in self?.currentFilePath }
    )
    private var enterOnEmptyLine = false

    var onRequestSettings: (() -> Void)?
    var onRequestSearch: (() -> Void)?
    var savedCursorRange: NSRange?

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
        WorkoutIndexManager.shared.configure(baseDirectory: baseDirectory)
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
        configureGalleryView()
        configureTextView()
        configureSwipeGestures()
        loadNote(for: currentState)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sync()
        }
    }

    private let galleryHeight: CGFloat = 200
    private let galleryPadding: CGFloat = 8

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

        updateGalleryInset()
        layoutGalleryInScrollView()
    }

    private func configureTitleLabel() {
        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = .gray
        titleLabel.textAlignment = .left
        view.addSubview(titleLabel)
    }

    private func configureGalleryView() {
        galleryView.isHidden = true
        galleryView.layer.cornerRadius = 12
        galleryView.clipsToBounds = true
        galleryView.onPhotoTapped = { [weak self] index, entries, sourceFrame in
            guard let self = self, let window = self.view.window else { return }
            let viewer = PhotoViewerOverlay()
            viewer.show(entries: entries, startIndex: index, sourceFrame: sourceFrame, in: window)
        }
        textView.addSubview(galleryView)
    }

    private func updateGalleryInset() {
        let inset: CGFloat = galleryView.isHidden ? 0 : galleryHeight + galleryPadding * 2
        textView.contentInset.top = inset
        textView.verticalScrollIndicatorInsets.top = inset
    }

    private func layoutGalleryInScrollView() {
        guard !galleryView.isHidden else { return }
        let totalInset = galleryHeight + galleryPadding * 2
        galleryView.frame = CGRect(
            x: galleryPadding,
            y: -totalInset + galleryPadding,
            width: textView.bounds.width - galleryPadding * 2,
            height: galleryHeight
        )
    }

    private func refreshGallery() {
        guard let path = currentFilePath else {
            galleryView.isHidden = true
            updateGalleryInset()
            return
        }
        let noteDir = path.deletingLastPathComponent()
        let text = textStorage.string
        let entries = PhotoParser.parse(from: text, noteDirectory: noteDir)
        galleryView.isHidden = entries.isEmpty
        galleryView.update(with: entries)
        updateGalleryInset()
        layoutGalleryInScrollView()
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

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
        swipeUp.direction = .up
        view.addGestureRecognizer(swipeUp)
    }

    @objc private func handleSwipeUp() {
        guard currentState.level == .daily else { return }
        navigateToPreviousLevel()
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
        let folder: String
        let subfolder: String

        switch state.level {
        case .daily:
            folder = "daily"
            subfolder = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        case .weekly:
            folder = "weekly"
            subfolder = String(format: "%04d-W%02d", c.year!, c.weekOfYear!)
        case .monthly:
            folder = "monthly"
            subfolder = String(format: "%04d-%02d", c.year!, c.month!)
        case .settings, .search:
            return nil
        }
        return baseDirectory
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(subfolder, isDirectory: true)
            .appendingPathComponent("note.org")
    }

    private func previousDate(from date: Date, at level: NoteLevel) -> Date {
        switch level {
        case .daily: return calendar.date(byAdding: .day, value: -1, to: date) ?? date
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: -1, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .settings, .search: return date
        }
    }

    private func nextDate(from date: Date, at level: NoteLevel) -> Date {
        switch level {
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .settings, .search: return date
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
        case .search:
            return "Search"
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
        guard state.level != .search else {
            onRequestSearch?()
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
        refreshGallery()
        workoutTransformer.renderAll()
        textView.contentOffset = CGPoint(x: 0, y: -textView.contentInset.top)
    }

    func returnFromSettings() {
        if currentState.level == .settings {
            currentState.level = .monthly
        }
        loadNote(for: currentState)
    }

    func returnFromSearch() {
        if currentState.level == .search {
            currentState.level = .daily
        }
        loadNote(for: currentState)
    }

    func insertAtSavedCursor(_ text: String) {
        if currentState.level != .daily {
            currentState.level = .daily
            currentState.currentDate = Date()
            loadNote(for: currentState)
        }

        let insertLocation: Int
        if let saved = savedCursorRange, saved.location <= textStorage.length {
            insertLocation = saved.location
        } else {
            insertLocation = textStorage.length
        }

        let insertText = text.hasSuffix("\n") ? text : text + "\n"
        textStorage.replaceCharacters(
            in: NSRange(location: insertLocation, length: 0),
            with: insertText
        )
        textView.selectedRange = NSRange(
            location: insertLocation + (insertText as NSString).length,
            length: 0
        )
        savedCursorRange = nil
        scheduleSyncSoon()
    }

    func loadNoteAndScroll(to state: NavigationState, lineNumber: Int?) {
        loadNote(for: state)
        guard let line = lineNumber else { return }
        let text = textStorage.string as NSString
        var currentLine = 0
        var charIndex = 0
        while currentLine < line && charIndex < text.length {
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
            charIndex = NSMaxRange(lineRange)
            currentLine += 1
        }
        if charIndex <= text.length {
            textView.selectedRange = NSRange(location: charIndex, length: 0)
            DispatchQueue.main.async {
                let rect = self.layoutManager.boundingRect(
                    forGlyphRange: self.layoutManager.glyphRange(
                        forCharacterRange: NSRange(location: charIndex, length: 0),
                        actualCharacterRange: nil
                    ),
                    in: self.textContainer
                )
                self.textView.scrollRectToVisible(rect, animated: false)
            }
        }
    }

    // MARK: - Sync

    /// Reconciles editor content with file on disk.
    /// Called on keypress (debounced 300ms), every 2s, and on navigation.
    ///
    /// Model: save local edits to disk, reload remote changes from disk,
    /// then absorb any Syncthing conflict files via two-way LCS merge.
    func sync() {
        guard !isSyncing, let path = currentFilePath else { return }
        isSyncing = true
        defer { isSyncing = false }

        let editorContent = textStorage.fileContent
        let diskContent = (try? String(contentsOf: path, encoding: .utf8)) ?? ""

        if editorContent != diskContent {
            if editorContent != lastSyncedContent {
                // Local edits — save to disk
                lastSyncedContent = editorContent
                try? editorContent.write(to: path, atomically: true, encoding: .utf8)
            } else {
                // Remote changed — reload into editor
                lastSyncedContent = diskContent
                reloadEditor(with: diskContent)
                refreshGallery()
            }
        } else {
            lastSyncedContent = editorContent
        }

        // Absorb any Syncthing conflict files
        let dir = path.deletingLastPathComponent()
        let baseName = path.deletingPathExtension().lastPathComponent
        let ext = path.pathExtension

        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        let conflictPattern = try! NSRegularExpression(pattern: "\\.sync-conflict-\\d{8}-\\d{6}-[A-Z0-9]{7}(?=\\.)")
        let conflictFiles = files.filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(baseName), name.hasSuffix(".\(ext)") else { return false }
            return conflictPattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }

        guard !conflictFiles.isEmpty else { return }

        var current = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        for conflictFile in conflictFiles {
            guard let conflictContent = try? String(contentsOf: conflictFile, encoding: .utf8) else { continue }
            current = Self.mergeTwo(current, conflictContent)
            try? FileManager.default.removeItem(at: conflictFile)
        }

        lastSyncedContent = current
        try? current.write(to: path, atomically: true, encoding: .utf8)
        reloadEditor(with: current)
        refreshGallery()
    }

    private func reloadEditor(with content: String) {
        let sel = textView.selectedRange
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: content)
        let max = textStorage.length
        textView.selectedRange = NSRange(
            location: min(sel.location, max),
            length: min(sel.length, max - min(sel.location, max))
        )
    }

    static func mergeTwo(_ a: String, _ b: String) -> String {
        let aLines = a.components(separatedBy: "\n")
        let bLines = b.components(separatedBy: "\n")
        let matches = lcs(aLines, bLines)

        var result: [String] = []
        var ai = 0, bi = 0
        for (mi, ni) in matches {
            result += aLines[ai..<mi]
            result += bLines[bi..<ni]
            result.append(aLines[mi])
            ai = mi + 1
            bi = ni + 1
        }
        result += aLines[ai...]
        result += bLines[bi...]
        return result.joined(separator: "\n")
    }

    private static func lcs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let m = a.count, n = b.count
        guard m > 0 && n > 0 else { return [] }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1] + 1 : max(dp[i-1][j], dp[i][j-1])
            }
        }
        var result: [(Int, Int)] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1] == b[j-1] {
                result.append((i-1, j-1))
                i -= 1; j -= 1
            } else if dp[i-1][j] >= dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
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
        // Track Enter on empty line for workout rendering
        if text == "\n" {
            let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
            let lineContent = (textStorage.string as NSString).substring(with: lineRange).trimmingCharacters(in: .newlines)
            enterOnEmptyLine = lineContent.isEmpty
        } else {
            enterOnEmptyLine = false
        }

        // Backspace near attachment: restore raw text
        if text.isEmpty && range.length == 1 {
            // Backspacing line below attachment → de-render
            if range.location > 0 {
                let prevAttrs = textStorage.attributes(at: range.location - 1, effectiveRange: nil)
                if let attachment = prevAttrs[.attachment] as? WorkoutTableAttachment {
                    let attachmentRange = NSRange(location: range.location - 1, length: 1)
                    textStorage.replaceCharacters(in: attachmentRange, with: attachment.rawText)
                    textView.selectedRange = NSRange(location: range.location - 1 + (attachment.rawText as NSString).length, length: 0)
                    scheduleSyncSoon()
                    return false
                }
            }
            // Backspacing the attachment itself → de-render
            if range.location < textStorage.length {
                let attrs = textStorage.attributes(at: range.location, effectiveRange: nil)
                if let attachment = attrs[.attachment] as? WorkoutTableAttachment {
                    textStorage.replaceCharacters(in: range, with: attachment.rawText)
                    textView.selectedRange = NSRange(location: range.location + (attachment.rawText as NSString).length, length: 0)
                    scheduleSyncSoon()
                    return false
                }
            }
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isSyncing else { return }

        if let newCursor = workoutTransformer.textChanged(renderAllowed: enterOnEmptyLine, cursorPosition: textView.selectedRange.location) {
            textView.selectedRange = NSRange(location: min(newCursor, textStorage.length), length: 0)
        }
        enterOnEmptyLine = false
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

        // Handle search specially
        if level == .search {
            sync()
            savedCursorRange = textView.selectedRange
            currentState.level = level
            onRequestSearch?()
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
