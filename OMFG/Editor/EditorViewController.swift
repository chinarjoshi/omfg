import UIKit

final class EditorViewController: UIViewController {
    private let textStorage: OrgTextStorage
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let textView: UITextView
    private let titleLabel: UILabel

    private let dailyNoteManager: DailyNoteManager
    private let autoSaveController: AutoSaveController
    private let fileWatcher: FileWatcher

    private var currentFilePath: URL?

    init(
        dailyNoteManager: DailyNoteManager,
        autoSaveController: AutoSaveController,
        fileWatcher: FileWatcher
    ) {
        self.dailyNoteManager = dailyNoteManager
        self.autoSaveController = autoSaveController
        self.fileWatcher = fileWatcher

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
        loadTodaysNote()
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
        view.addSubview(textView)
    }

    private func loadTodaysNote() {
        currentFilePath = dailyNoteManager.todaysNotePath()
        dailyNoteManager.ensureNoteExists(at: currentFilePath!)

        titleLabel.text = currentFilePath?.deletingPathExtension().lastPathComponent

        if let content = try? String(contentsOf: currentFilePath!, encoding: .utf8) {
            textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: content)
        } else {
            textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: dailyNoteManager.defaultTemplate())
        }

        fileWatcher.watch(currentFilePath!)
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
}

extension EditorViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard let path = currentFilePath else { return }
        autoSaveController.scheduleWrite(content: textStorage.string, to: path)
    }
}
