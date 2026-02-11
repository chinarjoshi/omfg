import UIKit

final class SettingsViewController: UIViewController {
    private let syncEngine = SyncEngine.shared
    private var onComplete: (() -> Void)?

    private let deviceIDLabel = UILabel()
    private var fullDeviceID = ""
    private let folderIDField = UITextField()
    private let remoteDeviceField = UITextField()
    private let logTextView = UITextView()

    var enableSwipeBack = false

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        stack.addArrangedSubview(label("Settings", font: .boldSystemFont(ofSize: 24)))
        stack.addArrangedSubview(spacer(22))
        stack.addArrangedSubview(label("Device ID:", font: .preferredFont(forTextStyle: .headline)))

        let deviceIDRow = UIStackView()
        deviceIDRow.axis = .horizontal
        deviceIDRow.spacing = 8
        deviceIDRow.alignment = .center

        deviceIDLabel.text = "Starting..."
        deviceIDLabel.font = .systemFont(ofSize: 11, weight: .regular)
        deviceIDLabel.textColor = .lightGray
        deviceIDLabel.lineBreakMode = .byTruncatingTail
        deviceIDLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        deviceIDRow.addArrangedSubview(deviceIDLabel)

        let copyButton = UIButton(type: .system)
        copyButton.setTitle("Copy", for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 14)
        copyButton.addTarget(self, action: #selector(copyDeviceID), for: .touchUpInside)
        copyButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        deviceIDRow.addArrangedSubview(copyButton)

        stack.addArrangedSubview(deviceIDRow)
        stack.addArrangedSubview(spacer(16))
        stack.addArrangedSubview(label("Folder ID:", font: .preferredFont(forTextStyle: .headline)))
        stack.addArrangedSubview(field(folderIDField, placeholder: "Enter folder ID"))
        stack.addArrangedSubview(spacer(16))
        stack.addArrangedSubview(label("Remote Device ID (optional):", font: .preferredFont(forTextStyle: .headline)))
        stack.addArrangedSubview(field(remoteDeviceField, placeholder: "Enter remote device ID"))
        stack.addArrangedSubview(spacer(32))

        let saveButton = UIButton(type: .system)
        saveButton.setTitle("Save & Continue", for: .normal)
        saveButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        saveButton.addTarget(self, action: #selector(saveAndContinue), for: .touchUpInside)
        stack.addArrangedSubview(saveButton)

        stack.addArrangedSubview(spacer(16))
        stack.addArrangedSubview(label("Sync Log:", font: .preferredFont(forTextStyle: .headline)))

        logTextView.isEditable = false
        logTextView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        logTextView.textColor = .lightGray
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.layer.cornerRadius = 8
        stack.addArrangedSubview(logTextView)

        // Pin log bottom to safe area so it fills remaining space
        logTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20).isActive = true

        syncEngine.onLogUpdate = { [weak self] in
            self?.updateLogView()
        }
        updateLogView()

        if enableSwipeBack {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
            swipe.direction = .up
            view.addGestureRecognizer(swipe)
        }
    }

    private func label(_ text: String, font: UIFont) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = .white
        return l
    }

    private func field(_ textField: UITextField, placeholder: String) -> UITextField {
        textField.borderStyle = .roundedRect
        textField.placeholder = placeholder
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.backgroundColor = .darkGray
        textField.textColor = .white
        textField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return textField
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let defaults = UserDefaults.standard
        if let folderID = defaults.folderID {
            folderIDField.text = folderID
        }
        if let remoteDeviceID = defaults.remoteDeviceID {
            remoteDeviceField.text = remoteDeviceID
        }

        // Show device ID immediately if available
        let id = syncEngine.deviceID
        if !id.isEmpty && id != "0000000-0000000-0000000-0000000-0000000-0000000-0000000-0000000" {
            fullDeviceID = id
            deviceIDLabel.text = id
        }

        syncEngine.onDeviceIDUpdate = { [weak self] id in
            self?.fullDeviceID = id
            self?.deviceIDLabel.text = id
        }

        syncEngine.startEventPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        syncEngine.stopEventPolling()
    }

    @objc private func handleSwipeUp() { onComplete?() }

    @objc private func copyDeviceID(_ sender: UIButton) {
        UIPasteboard.general.string = fullDeviceID
        let original = sender.titleLabel?.text
        let originalColor = sender.titleColor(for: .normal)
        sender.setTitle("Done", for: .normal)
        sender.setTitleColor(.systemGreen, for: .normal)
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                sender.transform = .identity
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sender.setTitle(original, for: .normal)
            sender.setTitleColor(originalColor, for: .normal)
        }
    }

    private func updateLogView() {
        logTextView.text = syncEngine.logs.joined(separator: "\n")
        if !logTextView.text.isEmpty {
            let bottom = NSRange(location: logTextView.text.count, length: 0)
            logTextView.scrollRangeToVisible(bottom)
        }
    }

    @objc private func saveAndContinue() {
        guard let folderID = folderIDField.text, !folderID.isEmpty else { return }
        let defaults = UserDefaults.standard
        defaults.folderID = folderID
        defaults.remoteDeviceID = remoteDeviceField.text?.isEmpty == true ? nil : remoteDeviceField.text
        defaults.isConfigured = true
        onComplete?()
    }
}
