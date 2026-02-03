import Foundation
import UIKit

#if canImport(Syncthing)
import Syncthing
#endif

final class SyncEngine {
    static let shared = SyncEngine()

    private let dataDirectory: URL
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var _isRunning = false
    private var _deviceID = ""

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDirectory = appSupport.appendingPathComponent("Syncthing", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    var isRunning: Bool {
        #if canImport(Syncthing)
        return LibsyncthingIsRunning()
        #else
        return _isRunning
        #endif
    }

    var deviceID: String {
        #if canImport(Syncthing)
        return LibsyncthingGetDeviceID()
        #else
        return _deviceID.isEmpty ? generateStubDeviceID() : _deviceID
        #endif
    }

    func start() {
        guard !isRunning else { return }
        #if canImport(Syncthing)
        var error: NSError?
        let success = LibsyncthingStart(dataDirectory.path, &error)
        if success {
            applyConfig()
        } else if let error = error {
            print("Sync start failed: \(error)")
        }
        #else
        _isRunning = true
        _deviceID = generateStubDeviceID()
        #endif
    }

    func stop() {
        #if canImport(Syncthing)
        LibsyncthingStop()
        #else
        _isRunning = false
        #endif
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
        #if canImport(Syncthing)
        guard let folderID = ConfigStore.shared.folderID else { return }
        LibsyncthingRescan(folderID, nil)
        #endif
    }

    func applyConfig() {
        #if canImport(Syncthing)
        let config = ConfigStore.shared
        guard let folderID = config.folderID, let folderPath = config.folderPath else { return }

        LibsyncthingSetFolder(folderID, folderPath, nil)

        if let remoteID = config.remoteDeviceID {
            LibsyncthingAddDevice(remoteID, config.remoteDeviceName ?? "Remote", nil)
            LibsyncthingShareFolderWithDevice(folderID, remoteID, nil)
        }
        #endif
    }

    private func generateStubDeviceID() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var id = ""
        for i in 0..<56 {
            if i > 0 && i % 7 == 0 { id += "-" }
            id += String(chars.randomElement()!)
        }
        return id
    }
}
