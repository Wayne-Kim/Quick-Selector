import Foundation

final class DesktopFolderObserver {
    private let url: URL
    private let queue: DispatchQueue
    private let debounceInterval: DispatchTimeInterval
    private let onChange: @Sendable () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?

    init(
        url: URL,
        debounceMilliseconds: Int = 200,
        queue: DispatchQueue = DispatchQueue(label: "quickdesktop.observer", qos: .utility),
        onChange: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.debounceInterval = .milliseconds(debounceMilliseconds)
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[quick-desktop] observer open() failed for \(url.path), errno=\(errno)")
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.revoke) || flags.contains(.rename) {
                self.restart()
            }
            self.scheduleDebouncedFire()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
    }

    private func restart() {
        queue.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self] in
            self?.start()
        }
    }

    private func scheduleDebouncedFire() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [onChange] in
            onChange()
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
