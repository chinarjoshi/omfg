import UIKit
import AVFoundation
import ImageIO
import CoreLocation

final class QuickCaptureViewController: UIViewController, CLLocationManagerDelegate {
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private let textField = UITextField()
    private let captureButton = UIButton()
    private let saveButton = UIButton()
    private let cancelButton = UIButton()
    private let thumbnailView = UIImageView()

    private var capturedImageData: Data?
    private let baseDirectory: URL
    private var onDismiss: (() -> Void)?

    private let geocoder = CLGeocoder()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    init(baseDirectory: URL, onDismiss: @escaping () -> Void) {
        self.baseDirectory = baseDirectory
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        setupLocation()
        checkCameraAuthorization()
    }

    private func setupLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                        self?.startCameraSession()
                    }
                }
            }
        default:
            let label = UILabel()
            label.text = "Camera access required"
            label.textColor = .white
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }

    private func startCameraSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCameraSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)

        captureSession = session
        photoOutput = output
        previewLayer = preview

        // Bring UI elements to front
        view.bringSubviewToFront(cancelButton)
        view.bringSubviewToFront(thumbnailView)
        view.bringSubviewToFront(textField)
        view.bringSubviewToFront(captureButton)
        view.bringSubviewToFront(saveButton)
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Cancel button (top left)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Thumbnail view (shows captured photo)
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 8
        thumbnailView.layer.borderWidth = 2
        thumbnailView.layer.borderColor = UIColor.white.cgColor
        thumbnailView.isHidden = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thumbnailView)

        // Capture button (center bottom)
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.lightGray.cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureButton)

        // Text field (bottom, above capture button)
        textField.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        textField.textColor = .white
        textField.font = .systemFont(ofSize: 16)
        textField.attributedPlaceholder = NSAttributedString(
            string: "Add a note...",
            attributes: [.foregroundColor: UIColor.lightGray]
        )
        textField.borderStyle = .none
        textField.layer.cornerRadius = 8
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        textField.rightViewMode = .always
        textField.returnKeyType = .done
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textField)

        // Save button (bottom right, hidden until photo taken)
        saveButton.setTitle("Save", for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.setTitleColor(.gray, for: .disabled)
        saveButton.backgroundColor = .systemBlue
        saveButton.layer.cornerRadius = 8
        saveButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        saveButton.addTarget(self, action: #selector(saveNote), for: .touchUpInside)
        saveButton.isEnabled = false
        saveButton.alpha = 0.5
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveButton)

        NSLayoutConstraint.activate([
            // Cancel button
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            // Thumbnail view
            thumbnailView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            thumbnailView.widthAnchor.constraint(equalToConstant: 60),
            thumbnailView.heightAnchor.constraint(equalToConstant: 60),

            // Text field
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textField.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            textField.heightAnchor.constraint(equalToConstant: 44),

            // Capture button
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),

            // Save button
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saveButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 80),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput?.capturePhoto(with: settings, delegate: self)
    }

    @objc private func saveNote() {
        guard let imageData = capturedImageData else { return }

        // Disable save button to prevent double-tap
        saveButton.isEnabled = false

        // 1. Save image to attachments folder
        let filename = saveImage(imageData)

        // 2. Use captured location (not EXIF - we captured it ourselves)
        let coordinates = currentLocation?.coordinate

        // 3. Reverse geocode if we have coordinates, then write note
        if let coords = coordinates {
            geocoder.reverseGeocodeLocation(CLLocation(latitude: coords.latitude, longitude: coords.longitude)) { [weak self] placemarks, _ in
                let address = self?.formatAddress(placemarks?.first)
                self?.writeNoteAndDismiss(filename: filename, coordinates: coords, address: address)
            }
        } else {
            writeNoteAndDismiss(filename: filename, coordinates: nil, address: nil)
        }
    }

    private func writeNoteAndDismiss(filename: String, coordinates: CLLocationCoordinate2D?, address: String?) {
        // Build note content
        let noteText = textField.text ?? ""

        var properties = ":PROPERTIES:\n"
        properties += ":IMAGE: attachments/\(filename)\n"

        if let coords = coordinates {
            let locationString: String
            if let addr = address {
                locationString = "\(addr) | \(String(format: "%.4f,%.4f", coords.latitude, coords.longitude))"
            } else {
                locationString = String(format: "%.4f,%.4f", coords.latitude, coords.longitude)
            }
            properties += ":LOCATION: \(locationString)\n"
        }

        properties += ":END:\n"

        let fullNote = properties + noteText

        // Append to daily note
        appendToDaily(note: fullNote)

        // Dismiss
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }

    // MARK: - File Operations

    private func saveImage(_ data: Data) -> String {
        let attachmentsDir = baseDirectory.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "\(formatter.string(from: Date())).jpg"
        let fileURL = attachmentsDir.appendingPathComponent(filename)

        try? data.write(to: fileURL)
        return filename
    }

    private func appendToDaily(note: String) {
        let dailyFolder = baseDirectory.appendingPathComponent("daily", isDirectory: true)
        try? FileManager.default.createDirectory(at: dailyFolder, withIntermediateDirectories: true)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let filename = String(format: "%04d-%02d-%02d.org", components.year!, components.month!, components.day!)
        let fileURL = dailyFolder.appendingPathComponent(filename)

        var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += note + "\n"
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - EXIF GPS Extraction

    private func extractGPS(from imageData: Data) -> CLLocationCoordinate2D? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let lng = gps[kCGImagePropertyGPSLongitude as String] as? Double,
              let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let lngRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String
        else { return nil }

        let latitude = latRef == "S" ? -lat : lat
        let longitude = lngRef == "W" ? -lng : lng
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func formatAddress(_ placemark: CLPlacemark?) -> String? {
        guard let place = placemark else { return nil }

        var parts: [String] = []
        if let locality = place.locality {
            parts.append(locality)
        }
        if let state = place.administrativeArea {
            parts.append(state)
        }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - UITextFieldDelegate

extension QuickCaptureViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension QuickCaptureViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }

        capturedImageData = data

        // Show thumbnail
        if let image = UIImage(data: data) {
            thumbnailView.image = image
            thumbnailView.isHidden = false
        }

        // Enable save button
        saveButton.isEnabled = true
        saveButton.alpha = 1.0

        // Change capture button appearance to indicate "retake"
        captureButton.backgroundColor = .clear
        captureButton.layer.borderColor = UIColor.white.cgColor
    }
}
