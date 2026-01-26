import Foundation

final class FileWatcher {
    var onExternalChange: (() -> Void)?

    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var lastModificationDate: Date?

    func watch(_ url: URL) {
        stopWatching()

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        lastModificationDate = modificationDate(for: url)

        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )

        dispatchSource?.setEventHandler { [weak self] in
            self?.handleFileEvent(url)
        }

        dispatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        dispatchSource?.resume()
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        fileDescriptor = -1
    }

    private func handleFileEvent(_ url: URL) {
        let currentDate = modificationDate(for: url)
        guard currentDate != lastModificationDate else { return }
        lastModificationDate = currentDate
        onExternalChange?()
    }

    private func modificationDate(for url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
