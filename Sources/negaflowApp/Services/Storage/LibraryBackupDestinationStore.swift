import Combine
import Foundation

@MainActor
final class LibraryBackupDestinationStore: ObservableObject {
    private enum Keys {
        static let path = "library.externalBackup.path"
        static let bookmark = "library.externalBackup.bookmark"
        static let lastSuccess = "library.externalBackup.lastSuccess"
    }

    typealias VolumeInspector = (URL) -> LibraryBackupVolumeInfo?

    @Published private(set) var status: LibraryBackupDestinationStatus = .notConfigured
    @Published private(set) var configuredPath: String?
    @Published private(set) var lastSuccessAt: Date?

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let inspectVolume: VolumeInspector
    private var bookmarkData: Data?

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        inspectVolume: @escaping VolumeInspector = { LibraryBackupVolumeInspector.inspect($0) }
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.inspectVolume = inspectVolume
        configuredPath = defaults.string(forKey: Keys.path)
        bookmarkData = defaults.data(forKey: Keys.bookmark)
        lastSuccessAt = defaults.object(forKey: Keys.lastSuccess) as? Date
    }

    var isConfigured: Bool { configuredPath != nil }

    var configuredURL: URL? {
        guard let configuredPath else { return nil }
        let fallback = URL(fileURLWithPath: configuredPath, isDirectory: true)
        let resolved = SourceBookmark.resolve(
            bookmarkData,
            fallbackURL: fallback,
            fileManager: fileManager
        )
        if resolved.url.path != configuredPath || resolved.bookmarkData != bookmarkData {
            self.configuredPath = resolved.url.path
            bookmarkData = resolved.bookmarkData
            persistLocation()
        }
        return resolved.url
    }

    func configure(_ url: URL) {
        let standardized = url.standardizedFileURL
        configuredPath = standardized.path
        bookmarkData = SourceBookmark.create(for: standardized, fileManager: fileManager)
        persistLocation()
        status = .disconnected(standardized)
    }

    func clear() {
        configuredPath = nil
        bookmarkData = nil
        status = .notConfigured
        defaults.removeObject(forKey: Keys.path)
        defaults.removeObject(forKey: Keys.bookmark)
    }

    @discardableResult
    func refresh(catalogURL: URL, requiredBytes: Int64 = 0) -> LibraryBackupDestinationStatus {
        guard let configuredURL else {
            status = .notConfigured
            return status
        }
        status = LibraryBackupDestinationValidator.evaluate(
            catalogURL: catalogURL,
            destinationURL: configuredURL,
            requiredBytes: requiredBytes,
            fileManager: fileManager,
            inspectVolume: inspectVolume
        )
        return status
    }

    func markSuccess(at date: Date = Date()) {
        lastSuccessAt = date
        defaults.set(date, forKey: Keys.lastSuccess)
    }

    private func persistLocation() {
        defaults.set(configuredPath, forKey: Keys.path)
        if let bookmarkData {
            defaults.set(bookmarkData, forKey: Keys.bookmark)
        } else {
            defaults.removeObject(forKey: Keys.bookmark)
        }
    }
}
