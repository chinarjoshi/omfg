import UIKit

// MARK: - Search Result

struct SearchResult {
    let text: String
    let date: String
    let filePath: String
    let lineNumber: Int?
    let isWorkout: Bool
    let rawInsertText: String?
}

// MARK: - Search Result Cell

final class SearchResultCell: UITableViewCell {
    static let reuseID = "SearchResultCell"

    private let resultLabel = UILabel()
    private let dateLabel = UILabel()
    let insertButton = UIButton(type: .system)

    var onInsert: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .black
        selectionStyle = .gray

        resultLabel.textColor = .white
        resultLabel.font = .systemFont(ofSize: 15)
        resultLabel.numberOfLines = 2

        dateLabel.textColor = .gray
        dateLabel.font = .systemFont(ofSize: 12)

        insertButton.setImage(UIImage(systemName: "arrow.up.left.circle.fill"), for: .normal)
        insertButton.tintColor = .systemBlue
        insertButton.isHidden = true
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [resultLabel, dateLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let hStack = UIStackView(arrangedSubviews: [textStack, insertButton])
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 12
        hStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hStack)

        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            insertButton.widthAnchor.constraint(equalToConstant: 32),
            insertButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func insertTapped() { onInsert?() }

    func configure(with result: SearchResult) {
        resultLabel.text = result.text
        dateLabel.text = result.date
        insertButton.isHidden = !result.isWorkout
    }
}

// MARK: - Search View Controller

final class SearchViewController: UIViewController {
    private let onComplete: () -> Void
    private let onInsert: (String) -> Void
    private let onNavigate: (String, Int?) -> Void

    private let baseDirectory: URL
    private let searchBar = UITextField()
    private let tableView = UITableView()

    private var results: [SearchResult] = []
    private var searchWorkItem: DispatchWorkItem?
    private var searchBarBottomConstraint: NSLayoutConstraint?

    init(
        baseDirectory: URL,
        onComplete: @escaping () -> Void,
        onInsert: @escaping (String) -> Void,
        onNavigate: @escaping (String, Int?) -> Void
    ) {
        self.baseDirectory = baseDirectory
        self.onComplete = onComplete
        self.onInsert = onInsert
        self.onNavigate = onNavigate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSearchBar()
        configureTableView()
        loadRecent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UI Setup

    private func configureSearchBar() {
        searchBar.backgroundColor = UIColor(white: 0.12, alpha: 1)
        searchBar.textColor = .white
        searchBar.font = .systemFont(ofSize: 16)
        searchBar.attributedPlaceholder = NSAttributedString(
            string: "Search notes...",
            attributes: [.foregroundColor: UIColor.gray]
        )
        searchBar.borderStyle = .none
        searchBar.layer.cornerRadius = 12
        searchBar.clipsToBounds = true
        searchBar.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        searchBar.leftViewMode = .always
        searchBar.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        searchBar.rightViewMode = .always
        searchBar.returnKeyType = .search
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        searchBarBottomConstraint = searchBar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8
        )
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            searchBarBottomConstraint!,
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardDidHide),
            name: UIResponder.keyboardDidHideNotification, object: nil
        )
    }

    private func configureTableView() {
        tableView.backgroundColor = .black
        tableView.separatorColor = UIColor(white: 0.2, alpha: 1)
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.reuseID)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: searchBar.topAnchor, constant: -8),
        ])
    }

    private var isOverscrolling = false
    private let overscrollThreshold: CGFloat = 25

    // MARK: - Keyboard

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let screenHeight = UIScreen.main.bounds.height
        let keyboardTop = screenHeight - frame.origin.y
        if keyboardTop > 0 {
            searchBarBottomConstraint?.constant = -(keyboardTop - view.safeAreaInsets.bottom + 8)
        } else {
            searchBarBottomConstraint?.constant = -8
        }
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    @objc private func keyboardDidHide() {
        onComplete()
    }

    // MARK: - Search Logic

    private func loadRecent() {
        results = WorkoutIndexManager.shared.recent().map { entry in
            SearchResult(
                text: entry.rawLine,
                date: entry.date,
                filePath: entry.filePath,
                lineNumber: nil,
                isWorkout: true,
                rawInsertText: entry.rawLine
            )
        }
        tableView.reloadData()
    }

    @objc private func searchTextChanged() {
        searchWorkItem?.cancel()
        let query = searchBar.text ?? ""
        guard !query.isEmpty else {
            loadRecent()
            return
        }

        let item = DispatchWorkItem { [weak self] in
            self?.performSearch(query: query)
        }
        searchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func performSearch(query: String) {
        var combined: [SearchResult] = []

        // 1. Workout index results
        let workoutResults = WorkoutIndexManager.shared.search(query: query)
        var workoutKeys = Set<String>()
        for entry in workoutResults {
            let key = "\(entry.filePath):\(entry.date):\(entry.name.lowercased())"
            workoutKeys.insert(key)
            combined.append(SearchResult(
                text: entry.rawLine,
                date: entry.date,
                filePath: entry.filePath,
                lineNumber: nil,
                isWorkout: true,
                rawInsertText: entry.rawLine
            ))
        }

        // 2. Org file text search
        let orgResults = searchOrgFiles(query: query)
        for result in orgResults {
            // Skip if already covered by workout index
            let text = result.text.lowercased()
            let dominated = workoutKeys.contains { key in
                let parts = key.components(separatedBy: ":")
                return parts.count >= 3 && result.filePath == parts[0] && text.contains(parts[2])
            }
            if !dominated {
                combined.append(result)
            }
        }

        combined.sort { $0.date > $1.date }
        results = combined
        tableView.reloadData()
    }

    private func searchOrgFiles(query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        let fm = FileManager.default
        let q = query.lowercased()

        for folder in ["daily", "weekly", "monthly"] {
            let folderURL = baseDirectory.appendingPathComponent(folder)
            guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { continue }

            for file in files where file.pathExtension == "org" {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let lines = content.components(separatedBy: "\n")
                let relativePath = "\(folder)/\(file.lastPathComponent)"
                let date = file.deletingPathExtension().lastPathComponent

                for (lineIdx, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && trimmed.lowercased().contains(q) {
                        results.append(SearchResult(
                            text: trimmed,
                            date: date,
                            filePath: relativePath,
                            lineNumber: lineIdx,
                            isWorkout: false,
                            rawInsertText: nil
                        ))
                    }
                }
            }
        }
        return results
    }

    // MARK: - Actions

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y < -overscrollThreshold {
            isOverscrolling = true
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard isOverscrolling else { return }
        isOverscrolling = false
        if scrollView.contentOffset.y < -overscrollThreshold {
            searchBar.resignFirstResponder()
            onComplete()
        }
    }
}

// MARK: - Table View

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.reuseID, for: indexPath) as! SearchResultCell
        let result = results[indexPath.row]
        cell.configure(with: result)
        cell.onInsert = { [weak self] in
            guard let raw = result.rawInsertText else { return }
            self?.searchBar.resignFirstResponder()
            self?.onInsert(raw)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let result = results[indexPath.row]
        searchBar.resignFirstResponder()
        onNavigate(result.filePath, result.lineNumber)
    }
}
