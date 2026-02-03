import Foundation

final class DailyNoteManager {
    private let baseDirectory: URL
    private let dateFormatter: DateFormatter

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
    }

    func todaysNotePath() -> URL {
        let filename = dateFormatter.string(from: Date()) + ".org"
        return baseDirectory
            .appendingPathComponent("daily", isDirectory: true)
            .appendingPathComponent(filename)
    }

    func ensureNoteExists(at url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: url.path) {
            try? defaultTemplate().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func defaultTemplate() -> String {
        let header = dateFormatter.string(from: Date())
        return "* \(header)\n\n"
    }
}
