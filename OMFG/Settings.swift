import UIKit

final class SettingsViewController: UIViewController {
    private let syncEngine = SyncEngine.shared
    private var onComplete: (() -> Void)?

    private let deviceIDLabel = UILabel()
    private let folderIDField = UITextField()
    private let remoteDeviceField = UITextField()

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

        stack.addArrangedSubview(label("OMFG Settings", font: .boldSystemFont(ofSize: 24)))
        stack.addArrangedSubview(spacer(22))
        stack.addArrangedSubview(label("This Device ID:", font: .preferredFont(forTextStyle: .headline)))
        deviceIDLabel.text = "Starting..."
        deviceIDLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        deviceIDLabel.textColor = .lightGray
        deviceIDLabel.numberOfLines = 0
        stack.addArrangedSubview(deviceIDLabel)
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.syncEngine.start()
            let deviceID = self?.syncEngine.deviceID ?? ""
            DispatchQueue.main.async { self?.deviceIDLabel.text = deviceID }
        }
    }

    @objc private func handleSwipeUp() { onComplete?() }

    @objc private func saveAndContinue() {
        guard let folderID = folderIDField.text, !folderID.isEmpty else { return }
        let defaults = UserDefaults.standard
        defaults.folderID = folderID
        defaults.folderPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
        defaults.remoteDeviceID = remoteDeviceField.text?.isEmpty == true ? nil : remoteDeviceField.text
        defaults.isConfigured = true
        onComplete?()
    }
}
