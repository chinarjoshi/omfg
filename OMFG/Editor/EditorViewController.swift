import UIKit

final class EditorViewController: UIViewController {
    private let textStorage: OrgTextStorage
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let textView: UITextView
    private let titleLabel: UILabel

    private let pathResolver: NotePathResolver
    private let autoSaveController: AutoSaveController
    private let fileWatcher: FileWatcher

    private var currentState: NavigationState
    private var currentFilePath: URL?

    var onRequestSettings: (() -> Void)?

    init(
        pathResolver: NotePathResolver,
        autoSaveController: AutoSaveController,
        fileWatcher: FileWatcher,
        initialState: NavigationState = .today()
    ) {
        self.pathResolver = pathResolver
        self.autoSaveController = autoSaveController
        self.fileWatcher = fileWatcher
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
        observeExternalChanges()
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
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.backgroundColor = .black
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.keyboardDismissMode = .interactive
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
        // Horizontal swipes on main view for date navigation
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
        }

        // Vertical swipes on title bar for level navigation (doesn't conflict with scroll)
        titleLabel.isUserInteractionEnabled = true
        for direction: UISwipeGestureRecognizer.Direction in [.up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            titleLabel.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        var newState = currentState

        switch gesture.direction {
        case .left:
            // Swipe left = next date
            newState.currentDate = pathResolver.nextDate(from: currentState.currentDate, at: currentState.level)
        case .right:
            // Swipe right = previous date
            newState.currentDate = pathResolver.previousDate(from: currentState.currentDate, at: currentState.level)
        case .down:
            // Swipe down = go up a level (daily → weekly → monthly → settings)
            if let nextLevel = currentState.level.next {
                newState.level = nextLevel
            }
        case .up:
            // Swipe up = go down a level (settings → monthly → weekly → daily)
            if let previousLevel = currentState.level.previous {
                newState.level = previousLevel
            }
        default:
            return
        }

        // Only navigate if state changed
        if newState.level != currentState.level || newState.currentDate != currentState.currentDate {
            textView.resignFirstResponder()
            saveCurrentNoteIfNeeded()
            loadNote(for: newState)
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

        currentFilePath = pathResolver.path(for: state)
        pathResolver.ensureNoteExists(for: state)

        titleLabel.text = pathResolver.displayTitle(for: state)

        let content: String
        if let path = currentFilePath,
           let fileContent = try? String(contentsOf: path, encoding: .utf8) {
            content = fileContent
        } else {
            content = ""
        }
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: content)
        textView.contentOffset = .zero

        if let path = currentFilePath {
            fileWatcher.watch(path)
        }
    }

    private func saveCurrentNoteIfNeeded() {
        guard let path = currentFilePath else { return }
        autoSaveController.flushImmediately()
        try? textStorage.string.write(to: path, atomically: true, encoding: .utf8)
    }

    private func observeExternalChanges() {
        fileWatcher.onExternalChange = { [weak self] in
            self?.reloadFromDisk()
        }
    }

    private func reloadFromDisk() {
        guard let path = currentFilePath,
              let content = try? String(contentsOf: path, encoding: .utf8) else { return }

        let currentSelection = textView.selectedRange
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: content)
        textView.selectedRange = currentSelection
    }

    func returnFromSettings() {
        if currentState.level == .settings {
            currentState.level = .monthly
        }
        loadNote(for: currentState)
    }
}

extension EditorViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard let path = currentFilePath else { return }
        autoSaveController.scheduleWrite(content: textStorage.string, to: path)

        if let selectedRange = textView.selectedTextRange {
            var caretRect = textView.caretRect(for: selectedRange.end)
            caretRect.size.height += 8
            textView.scrollRectToVisible(caretRect, animated: false)
        }
    }
}
