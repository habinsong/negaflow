import Darwin
import Dispatch
import Foundation

/// 등록된 실제 원본 폴더의 vnode 변경만 감시한다. 파일 내용은 읽지 않고 변경된 폴더 URL만
/// AppModel에 전달해, 전체 라이브러리 재검색 대신 해당 폴더만 병합할 수 있게 한다.
final class LibraryFileSystemMonitor: @unchecked Sendable {
    private static let queueLabel = "com.songhabin.negaflow.library-file-system-monitor"

    private final class Entry {
        let source: DispatchSourceFileSystemObject

        init(source: DispatchSourceFileSystemObject) {
            self.source = source
        }

        deinit {
            source.cancel()
        }
    }

    private let queue = DispatchQueue(
        label: LibraryFileSystemMonitor.queueLabel,
        qos: .utility
    )
    private var entries: [String: Entry] = [:]

    func update(
        folderURLs: [URL],
        onChange: @escaping @Sendable (URL) -> Void
    ) {
        let foldersByPath = Dictionary(
            folderURLs.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) },
            uniquingKeysWith: { first, _ in first }
        )
        queue.async { [weak self] in
            self?.replaceEntries(with: foldersByPath, onChange: onChange)
        }
    }

    func cancel() {
        queue.async { [weak self] in
            self?.cancelAllEntries()
        }
    }

    private func replaceEntries(
        with foldersByPath: [String: URL],
        onChange: @escaping @Sendable (URL) -> Void
    ) {
        for path in entries.keys where foldersByPath[path] == nil {
            cancelEntry(at: path)
        }
        for (path, folderURL) in foldersByPath where entries[path] == nil {
            let descriptor = open(folderURL.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
                queue: queue
            )
            source.setEventHandler {
                onChange(folderURL)
            }
            source.setCancelHandler {
                close(descriptor)
            }
            entries[path] = Entry(source: source)
            source.resume()
        }
    }

    private func cancelEntry(at path: String) {
        guard let entry = entries.removeValue(forKey: path) else { return }
        entry.source.cancel()
    }

    private func cancelAllEntries() {
        let currentEntries = entries.values
        entries.removeAll()
        for entry in currentEntries {
            entry.source.cancel()
        }
    }
}
