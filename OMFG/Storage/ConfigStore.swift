import Foundation

final class ConfigStore {
    static let shared = ConfigStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let folderID = "syncFolderID"
        static let folderPath = "syncFolderPath"
        static let remoteDeviceID = "remoteDeviceID"
        static let remoteDeviceName = "remoteDeviceName"
        static let isConfigured = "isConfigured"
    }

    var isConfigured: Bool {
        get { defaults.bool(forKey: Keys.isConfigured) }
        set { defaults.set(newValue, forKey: Keys.isConfigured) }
    }

    var folderID: String? {
        get { defaults.string(forKey: Keys.folderID) }
        set { defaults.set(newValue, forKey: Keys.folderID) }
    }

    var folderPath: String? {
        get { defaults.string(forKey: Keys.folderPath) }
        set { defaults.set(newValue, forKey: Keys.folderPath) }
    }

    var remoteDeviceID: String? {
        get { defaults.string(forKey: Keys.remoteDeviceID) }
        set { defaults.set(newValue, forKey: Keys.remoteDeviceID) }
    }

    var remoteDeviceName: String? {
        get { defaults.string(forKey: Keys.remoteDeviceName) }
        set { defaults.set(newValue, forKey: Keys.remoteDeviceName) }
    }
}
