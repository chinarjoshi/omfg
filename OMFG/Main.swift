import UIKit
import Syncthing
import AppIntents

// MARK: - Config

extension UserDefaults {
    private enum Keys {
        static let folderID = "syncFolderID"
        static let folderPath = "syncFolderPath"
        static let remoteDeviceID = "remoteDeviceID"
        static let remoteDeviceName = "remoteDeviceName"
        static let isConfigured = "isConfigured"
    }

    var isConfigured: Bool {
        get { bool(forKey: Keys.isConfigured) }
        set { set(newValue, forKey: Keys.isConfigured) }
    }

    var folderID: String? {
        get { string(forKey: Keys.folderID) }
        set { set(newValue, forKey: Keys.folderID) }
    }

    var folderPath: String? {
        get { string(forKey: Keys.folderPath) }
        set { set(newValue, forKey: Keys.folderPath) }
    }

    var remoteDeviceID: String? {
        get { string(forKey: Keys.remoteDeviceID) }
        set { set(newValue, forKey: Keys.remoteDeviceID) }
    }

    var remoteDeviceName: String? {
        get { string(forKey: Keys.remoteDeviceName) }
        set { set(newValue, forKey: Keys.remoteDeviceName) }
    }
}

// MARK: - SyncEngine

final class SyncEngine {
    static let shared = SyncEngine()

    private let dataDirectory: URL
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private(set) var logs: [String] = []
    var onLogUpdate: (() -> Void)?
    private var eventPollTimer: Timer?

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"
        logs.append(entry)
        if logs.count > 100 { logs.removeFirst() }
        DispatchQueue.main.async { self.onLogUpdate?() }
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDirectory = appSupport.appendingPathComponent("Syncthing", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    var isRunning: Bool { LibsyncthingIsRunning() }
    var deviceID: String { LibsyncthingGetDeviceID() }

    func start() {
        if isRunning {
            applyConfig()
            return
        }
        var error: NSError?
        let success = LibsyncthingStart(dataDirectory.path, &error)
        if success {
            applyConfig()
        } else if let error = error {
            log("Start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        LibsyncthingStop()
    }

    func beginBackgroundSync() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundSync()
        }
    }

    func endBackgroundSync() {
        stop()
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    func rescan() {
        guard let folderID = UserDefaults.standard.folderID else { return }
        LibsyncthingRescan(folderID, nil)
    }

    func startEventPolling() {
        eventPollTimer?.invalidate()
        eventPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.global(qos: .utility).async {
                self.pollEvents()
                self.checkDeviceID()
            }
        }
    }

    func stopEventPolling() {
        eventPollTimer?.invalidate()
        eventPollTimer = nil
    }

    private func pollEvents() {
        let events = LibsyncthingGetEvents()
        if events.isEmpty {
            // Still trigger UI update so we see Swift-side logs
            DispatchQueue.main.async { self.onLogUpdate?() }
            return
        }
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        for line in events.components(separatedBy: "\n") where !line.isEmpty {
            logs.append("[\(timestamp)] \(line)")
            if logs.count > 100 { logs.removeFirst() }
        }
        DispatchQueue.main.async { self.onLogUpdate?() }
    }

    var onDeviceIDUpdate: ((String) -> Void)?

    private func checkDeviceID() {
        let id = deviceID
        if !id.isEmpty {
            DispatchQueue.main.async { self.onDeviceIDUpdate?(id) }
        }
    }

    func applyConfig() {
        let defaults = UserDefaults.standard
        guard let folderID = defaults.folderID else {
            log("No folder ID configured")
            return
        }

        let folderPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path

        var folderErr: NSError?
        LibsyncthingSetFolder(folderID, folderPath, &folderErr)
        if let err = folderErr {
            log("SetFolder error: \(err.localizedDescription)")
        }

        if let remoteID = defaults.remoteDeviceID {
            var deviceErr: NSError?
            LibsyncthingAddDevice(remoteID, defaults.remoteDeviceName ?? "Remote", &deviceErr)
            if let err = deviceErr {
                log("AddDevice error: \(err.localizedDescription)")
            }

            var shareErr: NSError?
            LibsyncthingShareFolderWithDevice(folderID, remoteID, &shareErr)
            if let err = shareErr {
                log("ShareFolder error: \(err.localizedDescription)")
            }

            log("Config: folder=\(folderID) remote=\(String(remoteID.prefix(7)))")
        } else {
            log("Config: folder=\(folderID) (no remote)")
        }
    }
}

// MARK: - AppDelegate

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

// MARK: - SceneDelegate

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let syncEngine = SyncEngine.shared

    private var editorViewController: EditorViewController?
    private var settingsViewController: SettingsViewController?
    private var searchViewController: SearchViewController?
    private var backgroundSyncEndWorkItem: DispatchWorkItem?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)

        if UserDefaults.standard.isConfigured {
            let editor = createEditorViewController()
            editorViewController = editor
            window?.rootViewController = editor
        } else {
            let settings = SettingsViewController { [weak self] in
                self?.transitionToEditor()
            }
            settingsViewController = settings
            window?.rootViewController = settings
        }

        window?.makeKeyAndVisible()

        if UserDefaults.standard.isConfigured {
            startSyncAsync()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuickCapture),
            name: .quickCaptureRequested,
            object: nil
        )

        // Handle URL if app was launched from widget
        if let url = connectionOptions.urlContexts.first?.url,
           url.scheme == "omfg" && url.host == "photonote" {
            DispatchQueue.main.async { [weak self] in
                self?.handleQuickCapture()
            }
        }
    }

    @objc private func handleQuickCapture() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let capture = QuickCaptureViewController(baseDirectory: documentsURL) { [weak self] in
            self?.editorViewController?.sync()
        }
        capture.modalPresentationStyle = .fullScreen
        window?.rootViewController?.present(capture, animated: true)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        backgroundSyncEndWorkItem?.cancel()
        backgroundSyncEndWorkItem = nil
        startSyncAsync()
        editorViewController?.sync()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        syncEngine.beginBackgroundSync()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        backgroundSyncEndWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.syncEngine.endBackgroundSync()
        }
        backgroundSyncEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        if url.scheme == "omfg" && url.host == "photonote" {
            handleQuickCapture()
        }
    }

    private func startSyncAsync() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self, !self.syncEngine.isRunning else { return }
            self.syncEngine.start()
        }
    }

    private func transitionToEditor() {
        let editor = createEditorViewController()
        editorViewController = editor
        settingsViewController = nil
        window?.rootViewController = editor
        syncEngine.applyConfig()
    }

    private func transitionToSettings() {
        let settings = SettingsViewController { [weak self] in
            self?.transitionBackToEditor()
        }
        settings.enableSwipeBack = true
        settingsViewController = settings

        guard let window = window else { return }
        let snapshot = editorViewController?.view.snapshotView(afterScreenUpdates: false)
        window.rootViewController = settings
        if let snapshot = snapshot {
            snapshot.frame = window.bounds
            window.addSubview(snapshot)
            settings.view.transform = CGAffineTransform(translationX: 0, y: -window.bounds.height)

            UIView.animate(withDuration: 0.06, delay: 0, options: .curveEaseOut) {
                snapshot.transform = CGAffineTransform(translationX: 0, y: window.bounds.height)
                settings.view.transform = .identity
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }
    }

    private func transitionBackToEditor() {
        guard let editor = editorViewController, let window = window else {
            transitionToEditor()
            return
        }

        let snapshot = settingsViewController?.view.snapshotView(afterScreenUpdates: false)
        settingsViewController = nil
        editor.returnFromSettings()
        window.rootViewController = editor
        if let snapshot = snapshot {
            snapshot.frame = window.bounds
            window.addSubview(snapshot)
            editor.view.transform = CGAffineTransform(translationX: 0, y: window.bounds.height)

            UIView.animate(withDuration: 0.06, delay: 0, options: .curveEaseOut) {
                snapshot.transform = CGAffineTransform(translationX: 0, y: -window.bounds.height)
                editor.view.transform = .identity
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }
    }

    private func createEditorViewController() -> EditorViewController {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let editor = EditorViewController(baseDirectory: documentsURL)
        editor.onRequestSettings = { [weak self] in
            self?.transitionToSettings()
        }
        editor.onRequestSearch = { [weak self] in
            self?.transitionToSearch()
        }
        return editor
    }

    // MARK: - Search Transitions

    private func transitionToSearch() {
        guard let editor = editorViewController else { return }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        let search = SearchViewController(
            baseDirectory: documentsURL,
            onComplete: { [weak self] in
                self?.transitionBackFromSearch()
            },
            onInsert: { [weak self] rawText in
                self?.editorViewController?.insertAtSavedCursor(rawText)
                self?.transitionBackFromSearch()
            },
            onNavigate: { [weak self] filePath, lineNumber in
                self?.navigateToFileFromSearch(filePath: filePath, lineNumber: lineNumber)
            }
        )
        searchViewController = search

        guard let window = window else { return }
        let snapshot = editor.view.snapshotView(afterScreenUpdates: false)
        window.rootViewController = search
        if let snapshot = snapshot {
            snapshot.frame = window.bounds
            window.addSubview(snapshot)
            search.view.transform = CGAffineTransform(translationX: 0, y: window.bounds.height)

            UIView.animate(withDuration: 0.06, delay: 0, options: .curveEaseOut) {
                snapshot.transform = CGAffineTransform(translationX: 0, y: -window.bounds.height)
                search.view.transform = .identity
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }
    }

    private func transitionBackFromSearch() {
        guard let editor = editorViewController, let window = window else { return }

        let snapshot = searchViewController?.view.snapshotView(afterScreenUpdates: false)
        searchViewController = nil
        editor.returnFromSearch()
        window.rootViewController = editor
        if let snapshot = snapshot {
            snapshot.frame = window.bounds
            window.addSubview(snapshot)
            editor.view.transform = CGAffineTransform(translationX: 0, y: window.bounds.height)

            UIView.animate(withDuration: 0.06, delay: 0, options: .curveEaseOut) {
                snapshot.transform = CGAffineTransform(translationX: 0, y: -window.bounds.height)
                editor.view.transform = .identity
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }
    }

    private func navigateToFileFromSearch(filePath: String, lineNumber: Int?) {
        guard let editor = editorViewController else { return }

        let components = filePath.components(separatedBy: "/")
        guard components.count == 2 else {
            transitionBackFromSearch()
            return
        }

        let folder = components[0]
        let filename = (components[1] as NSString).deletingPathExtension
        let calendar = Calendar.current

        let level: NoteLevel
        let date: Date

        switch folder {
        case "daily":
            level = .daily
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            date = f.date(from: filename) ?? Date()
        case "weekly":
            level = .weekly
            let parts = filename.components(separatedBy: "-W")
            if parts.count == 2, let year = Int(parts[0]), let week = Int(parts[1]) {
                var dc = DateComponents()
                dc.yearForWeekOfYear = year
                dc.weekOfYear = week
                dc.weekday = 2
                date = calendar.date(from: dc) ?? Date()
            } else {
                date = Date()
            }
        case "monthly":
            level = .monthly
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM"
            date = f.date(from: filename) ?? Date()
        default:
            transitionBackFromSearch()
            return
        }

        searchViewController = nil
        let state = NavigationState(level: level, currentDate: date)
        editor.loadNoteAndScroll(to: state, lineNumber: lineNumber)

        guard let window = window else { return }
        window.rootViewController = editor
    }
}

// MARK: - App Intents

@available(iOS 16.0, *)
struct OpenDailyNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Daily Note"
    static var description = IntentDescription("Opens today's daily note in OMFG")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

@available(iOS 16.0, *)
struct QuickNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Note"
    static var description = IntentDescription("Add a quick text note")
    static var openAppWhenRun: Bool = false

    @Parameter(title: " ")
    var note: String

    func perform() async throws -> some IntentResult {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let calendar = Calendar.current
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        let subfolder = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        let noteDir = documentsURL
            .appendingPathComponent("daily", isDirectory: true)
            .appendingPathComponent(subfolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)

        let fileURL = noteDir.appendingPathComponent("note.org")

        var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += note + "\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return .result()
    }
}

@available(iOS 16.0, *)
struct PhotoNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Photo Note"
    static var description = IntentDescription("Take a photo with location and add a note")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .quickCaptureRequested, object: nil)
        }
        return .result()
    }
}

extension Notification.Name {
    static let quickCaptureRequested = Notification.Name("quickCaptureRequested")
}

@available(iOS 16.0, *)
struct OMFGShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickNoteIntent(),
            phrases: [
                "Quick note in \(.applicationName)",
                "Add note to \(.applicationName)"
            ],
            shortTitle: "Quick Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: PhotoNoteIntent(),
            phrases: [
                "Photo note in \(.applicationName)",
                "Take photo note in \(.applicationName)"
            ],
            shortTitle: "Photo Note",
            systemImageName: "camera"
        )
    }
}
