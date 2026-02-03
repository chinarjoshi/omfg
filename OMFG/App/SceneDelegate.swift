import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let syncEngine = SyncEngine.shared
    private let configStore = ConfigStore.shared

    private var editorViewController: EditorViewController?
    private var settingsViewController: SettingsViewController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)

        if configStore.isConfigured {
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

        if configStore.isConfigured {
            startSyncAsync()
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        startSyncAsync()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        syncEngine.beginBackgroundSync()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.syncEngine.endBackgroundSync()
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

        UIView.transition(
            with: window!,
            duration: 0.3,
            options: .transitionCrossDissolve
        ) {
            self.window?.rootViewController = editor
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for _ in 0..<100 {
                if self?.syncEngine.isRunning == true {
                    self?.syncEngine.applyConfig()
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
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
        let pathResolver = NotePathResolver(baseDirectory: documentsURL)
        let editor = EditorViewController(
            pathResolver: pathResolver,
            autoSaveController: AutoSaveController(),
            fileWatcher: FileWatcher()
        )
        editor.onRequestSettings = { [weak self] in
            self?.transitionToSettings()
        }
        return editor
    }
}
