import Foundation

final class AutoSaveController {
    private let debounceInterval: TimeInterval
    private let fileStore: FileStore
    private var pendingWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "autosave", qos: .utility)

    init(fileStore: FileStore, debounceInterval: TimeInterval = 0.5) {
        self.fileStore = fileStore
        self.debounceInterval = debounceInterval
    }

    func scheduleWrite(content: String, to url: URL) {
        pendingWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.fileStore.write(content: content, to: url)
        }

        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    func flushImmediately() {
        pendingWorkItem?.perform()
        pendingWorkItem = nil
    }
}
