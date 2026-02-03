import UIKit

final class SettingsViewController: UIViewController {
    private let syncEngine = SyncEngine.shared
    private let configStore = ConfigStore.shared
    private var onComplete: (() -> Void)?

    private let deviceIDLabel = UILabel()
    private let folderIDField = UITextField()
    private let remoteDeviceField = UITextField()
    private let saveButton = UIButton(type: .system)

    var enableSwipeBack = false

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let titleLabel = UILabel()
        titleLabel.text = "OMFG Settings"
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let idTitleLabel = UILabel()
        idTitleLabel.text = "This Device ID:"
        idTitleLabel.font = .preferredFont(forTextStyle: .headline)
        idTitleLabel.textColor = .white
        idTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(idTitleLabel)

        deviceIDLabel.text = "Starting..."
        deviceIDLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        deviceIDLabel.textColor = .lightGray
        deviceIDLabel.numberOfLines = 0
        deviceIDLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(deviceIDLabel)

        let folderLabel = UILabel()
        folderLabel.text = "Folder ID:"
        folderLabel.font = .preferredFont(forTextStyle: .headline)
        folderLabel.textColor = .white
        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(folderLabel)

        folderIDField.borderStyle = .roundedRect
        folderIDField.placeholder = "Enter folder ID"
        folderIDField.autocapitalizationType = .none
        folderIDField.autocorrectionType = .no
        folderIDField.backgroundColor = .darkGray
        folderIDField.textColor = .white
        folderIDField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(folderIDField)

        let remoteLabel = UILabel()
        remoteLabel.text = "Remote Device ID (optional):"
        remoteLabel.font = .preferredFont(forTextStyle: .headline)
        remoteLabel.textColor = .white
        remoteLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(remoteLabel)

        remoteDeviceField.borderStyle = .roundedRect
        remoteDeviceField.placeholder = "Enter remote device ID"
        remoteDeviceField.autocapitalizationType = .none
        remoteDeviceField.autocorrectionType = .no
        remoteDeviceField.backgroundColor = .darkGray
        remoteDeviceField.textColor = .white
        remoteDeviceField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(remoteDeviceField)

        saveButton.setTitle("Save & Continue", for: .normal)
        saveButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        saveButton.setTitleColor(.systemBlue, for: .normal)
        saveButton.addTarget(self, action: #selector(saveAndContinue), for: .touchUpInside)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            idTitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 30),
            idTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            deviceIDLabel.topAnchor.constraint(equalTo: idTitleLabel.bottomAnchor, constant: 8),
            deviceIDLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            deviceIDLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            folderLabel.topAnchor.constraint(equalTo: deviceIDLabel.bottomAnchor, constant: 24),
            folderLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            folderIDField.topAnchor.constraint(equalTo: folderLabel.bottomAnchor, constant: 8),
            folderIDField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            folderIDField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            folderIDField.heightAnchor.constraint(equalToConstant: 44),

            remoteLabel.topAnchor.constraint(equalTo: folderIDField.bottomAnchor, constant: 24),
            remoteLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            remoteDeviceField.topAnchor.constraint(equalTo: remoteLabel.bottomAnchor, constant: 8),
            remoteDeviceField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            remoteDeviceField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            remoteDeviceField.heightAnchor.constraint(equalToConstant: 44),

            saveButton.topAnchor.constraint(equalTo: remoteDeviceField.bottomAnchor, constant: 40),
            saveButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        if enableSwipeBack {
            setupSwipeBack()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Start syncthing on background thread (may block for a while)
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.syncEngine.start()
        }
        // Poll for device ID on separate thread - it becomes available quickly
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Give syncthing a moment to initialize and set the device ID
            Thread.sleep(forTimeInterval: 1.0)
            for _ in 0..<30 {
                let deviceID = self?.syncEngine.deviceID ?? ""
                if !deviceID.isEmpty {
                    DispatchQueue.main.async {
                        self?.deviceIDLabel.text = deviceID
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    private func setupSwipeBack() {
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
        swipeUp.direction = .up
        view.addGestureRecognizer(swipeUp)
    }

    @objc private func handleSwipeUp() {
        onComplete?()
    }

    @objc private func saveAndContinue() {
        guard let folderID = folderIDField.text, !folderID.isEmpty else { return }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path

        configStore.folderID = folderID
        configStore.folderPath = documentsPath
        configStore.remoteDeviceID = remoteDeviceField.text?.isEmpty == true ? nil : remoteDeviceField.text
        configStore.isConfigured = true

        onComplete?()
    }
}
