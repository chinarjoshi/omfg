import Foundation

final class FileStore {
    func write(content: String, to url: URL) {
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(from url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
