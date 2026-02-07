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
            // Headers
            rule("^\\* .+$", .anchorsMatchLines, color: .white, font: .monospacedSystemFont(ofSize: 24, weight: .bold)),
            rule("^\\*\\* .+$", .anchorsMatchLines, color: .white, font: .monospacedSystemFont(ofSize: 20, weight: .bold)),
            rule("^\\*\\*\\* .+$", .anchorsMatchLines, color: .white, font: .monospacedSystemFont(ofSize: 18, weight: .semibold)),
            // Keywords
            rule("\\bTODO\\b", color: .systemRed, font: .monospacedSystemFont(ofSize: 16, weight: .bold)),
            rule("\\bDONE\\b", color: .systemGreen, font: .monospacedSystemFont(ofSize: 16, weight: .bold)),
            // Links
            rule("\\[\\[[^\\]]+\\]\\]", color: .systemBlue, underline: true),
            // Formatting
            rule("(?<=\\s|^)\\*[^\\*\\n]+\\*(?=\\s|$)", .anchorsMatchLines, font: .monospacedSystemFont(ofSize: 16, weight: .bold)),
            rule("(?<=\\s|^)/[^/\\n]+/(?=\\s|$)", .anchorsMatchLines, font: .italicSystemFont(ofSize: 16)),
            // Timestamps
            rule("<[^>]+>", color: .systemPurple, background: UIColor.systemPurple.withAlphaComponent(0.1)),
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
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        let paragraphRange = (string as NSString).paragraphRange(for: editedRange)
        applyDefaultAttributes(in: paragraphRange)
        applySyntaxHighlighting(in: paragraphRange)
        super.processEditing()
    }

    private func applyDefaultAttributes(in range: NSRange) {
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
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

    // Inline auto-save
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "autosave", qos: .utility)

    // Inline file watcher
    private var watchedFileDescriptor: Int32 = -1
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var lastModificationDate: Date?

    // Elastic pull navigation
    private let overscrollThreshold: CGFloat = 80
    private var isOverscrolling = false


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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureTitleLabel()
        configureTextView()
        configureSwipeGestures()
        loadNote(for: currentState)
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
        titleLabel.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .left
        view.addSubview(titleLabel)
    }

    private func configureTextView() {
        textView.backgroundColor = .black
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.delegate = self
        textView.inputAccessoryView = createKeyboardAccessoryView()
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

    private func createKeyboardAccessoryView() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 28))
        container.backgroundColor = .black

        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        button.tintColor = UIColor(white: 0.4, alpha: 1)
        button.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    @objc private func dismissKeyboard() {
        textView.resignFirstResponder()
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
        // Horizontal swipes for date navigation
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleHorizontalSwipe(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleHorizontalSwipe(_ gesture: UISwipeGestureRecognizer) {
        var newState = currentState

        switch gesture.direction {
        case .left:
            newState.currentDate = nextDate(from: currentState.currentDate, at: currentState.level)
        case .right:
            newState.currentDate = previousDate(from: currentState.currentDate, at: currentState.level)
        default:
            return
        }

        if newState.currentDate != currentState.currentDate {
            textView.resignFirstResponder()
            saveCurrentNoteIfNeeded()
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

    private func displayTitle(for state: NavigationState) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekOfYear], from: state.currentDate)
        switch state.level {
        case .daily:
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        case .weekly:
            return String(format: "%04d-W%02d", c.year!, c.weekOfYear!)
        case .monthly:
            return String(format: "%04d-%02d", c.year!, c.month!)
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
        saveCurrentNoteIfNeeded()
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
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: content)
        textView.contentOffset = .zero

        if let path = currentFilePath {
            watchFile(path)
        }
    }

    private func saveCurrentNoteIfNeeded() {
        guard let path = currentFilePath else { return }
        flushSaveImmediately()
        try? textStorage.string.write(to: path, atomically: true, encoding: .utf8)
    }

    func returnFromSettings() {
        if currentState.level == .settings {
            currentState.level = .monthly
        }
        loadNote(for: currentState)
    }

    // MARK: - Auto Save

    private func scheduleAutoSave(content: String, to url: URL) {
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func flushSaveImmediately() {
        pendingSaveWorkItem?.perform()
        pendingSaveWorkItem = nil
    }

    // MARK: - File Watching

    private func watchFile(_ url: URL) {
        stopWatchingFile()

        watchedFileDescriptor = open(url.path, O_EVTONLY)
        guard watchedFileDescriptor >= 0 else { return }

        lastModificationDate = modificationDate(for: url)

        fileWatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchedFileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )

        fileWatchSource?.setEventHandler { [weak self] in
            self?.handleFileEvent(url)
        }

        fileWatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.watchedFileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        fileWatchSource?.resume()
    }

    private func stopWatchingFile() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
        watchedFileDescriptor = -1
    }

    private func handleFileEvent(_ url: URL) {
        let currentDate = modificationDate(for: url)
        guard currentDate != lastModificationDate else { return }
        lastModificationDate = currentDate
        reloadFromDisk()
    }

    private func modificationDate(for url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func reloadFromDisk() {
        guard let path = currentFilePath,
              let content = try? String(contentsOf: path, encoding: .utf8) else { return }

        let currentSelection = textView.selectedRange
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: content)
        textView.selectedRange = currentSelection
    }
}

extension EditorViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard let path = currentFilePath else { return }
        scheduleAutoSave(content: textStorage.string, to: path)

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
        saveCurrentNoteIfNeeded()

        // Handle settings specially
        if level == .settings {
            currentState.level = level
            onRequestSettings?()
            return
        }

        // Slide current content out
        let exitY: CGFloat = direction == .up ? -view.bounds.height : view.bounds.height
        UIView.animate(withDuration: 0.08) {
            self.view.transform = CGAffineTransform(translationX: 0, y: exitY)
        } completion: { _ in
            // Load new content
            self.currentState.level = level
            self.loadNote(for: self.currentState)

            // Position off-screen on opposite side, then animate in
            let enterY: CGFloat = direction == .up ? self.view.bounds.height : -self.view.bounds.height
            self.view.transform = CGAffineTransform(translationX: 0, y: enterY)

            UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseOut) {
                self.view.transform = .identity
            }
        }
    }
}
