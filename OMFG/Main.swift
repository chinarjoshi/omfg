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

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDirectory = appSupport.appendingPathComponent("Syncthing", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    var isRunning: Bool { LibsyncthingIsRunning() }
    var deviceID: String { LibsyncthingGetDeviceID() }

    func start() {
        guard !isRunning else { return }
        var error: NSError?
        let success = LibsyncthingStart(dataDirectory.path, &error)
        if success {
            applyConfig()
        } else if let error = error {
            print("Sync start failed: \(error)")
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

    func applyConfig() {
        let defaults = UserDefaults.standard
        guard let folderID = defaults.folderID, let folderPath = defaults.folderPath else { return }

        LibsyncthingSetFolder(folderID, folderPath, nil)

        if let remoteID = defaults.remoteDeviceID {
            LibsyncthingAddDevice(remoteID, defaults.remoteDeviceName ?? "Remote", nil)
            LibsyncthingShareFolderWithDevice(folderID, remoteID, nil)
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
    }

    @objc private func handleQuickCapture() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let capture = QuickCaptureViewController(baseDirectory: documentsURL) { [weak self] in
            self?.editorViewController?.reloadFromDisk()
        }
        capture.modalPresentationStyle = .fullScreen
        window?.rootViewController?.present(capture, animated: true)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        backgroundSyncEndWorkItem?.cancel()
        backgroundSyncEndWorkItem = nil
        startSyncAsync()
        editorViewController?.reloadFromDisk()
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
        window?.rootViewController = settings
    }

    private func transitionBackToEditor() {
        guard let editor = editorViewController else {
            transitionToEditor()
            return
        }

        settingsViewController = nil
        editor.returnFromSettings()
        window?.rootViewController = editor
    }

    private func createEditorViewController() -> EditorViewController {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let editor = EditorViewController(baseDirectory: documentsURL)
        editor.onRequestSettings = { [weak self] in
            self?.transitionToSettings()
        }
        return editor
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
        let dailyFolder = documentsURL.appendingPathComponent("daily", isDirectory: true)
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
