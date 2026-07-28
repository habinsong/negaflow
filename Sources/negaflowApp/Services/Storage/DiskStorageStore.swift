import Combine
import Foundation

enum DiskStorageLocationMode: String, CaseIterable, Hashable {
    case iCloud
    case desktop
    case specificFolder
    case custom
}

// MARK: - DiskStorageStore
//
// 썸네일/내보내기/빠른 내보내기/스캔 원본의 디스크 저장 위치를 관리한다.
@MainActor
final class DiskStorageStore: ObservableObject {
    private enum Keys {
        static let locationMode = "disk.locationMode"
        static let specificFolder = "disk.specificFolder"
        static let root = "disk.rootFolder"
        static let thumbnails = "disk.thumbnailsFolder"
        static let export = "disk.exportFolder"
        static let quickExport = "disk.quickExportFolder"
        static let scans = "disk.scansFolder"
        static let importedSources = "disk.importedSourcesFolder"
        static let cleanedRaw = "disk.cleanedRawFolder"
        static let cleanedRawHistory = "disk.cleanedRawFolderHistory"
        static let scanPreviews = "disk.scanPreviewsFolder"
        static let recentCreatedScanFolder = "disk.recentCreatedScanFolder"
        // 디스크 탭 도입 전 빠른 내보내기 경로 키(ExportSettingsStore) — 최초 실행 시 이어받는다.
        static let legacyQuickExport = "export.quick.folder"
    }

    enum FolderName {
        static let root = "negaflow"
        static let thumbnails = "Thumbnails"
        static let export = "Export"
        static let quickExport = "Quick Export"
        static let scans = "Scans"
        static let importedSources = "Imported Originals"
        static let cleanedRaw = "Cleaned Raw"
        static let scanPreviews = "scan-previews"
        static let managedScanPreviews = "Scan Previews"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager

    @Published var locationMode: DiskStorageLocationMode {
        didSet {
            defaults.set(locationMode.rawValue, forKey: Keys.locationMode)
            registerCleanedRawDirectoryChange(from: cleanedRawURL(for: oldValue))
        }
    }
    @Published var specificFolderPath: String? {
        didSet {
            let oldDirectory = resolved(oldValue)?
                .appendingPathComponent(FolderName.root, isDirectory: true)
                .appendingPathComponent(FolderName.cleanedRaw, isDirectory: true)
            defaults.set(specificFolderPath, forKey: Keys.specificFolder)
            if locationMode == .specificFolder {
                registerCleanedRawDirectoryChange(from: oldDirectory)
            }
        }
    }
    @Published var rootPath: String? {
        didSet {
            defaults.set(rootPath, forKey: Keys.root)
            activateCustomMode(for: rootPath)
        }
    }
    @Published var thumbnailsPath: String? {
        didSet {
            defaults.set(thumbnailsPath, forKey: Keys.thumbnails)
            activateCustomMode(for: thumbnailsPath)
        }
    }
    @Published var exportPath: String? {
        didSet {
            defaults.set(exportPath, forKey: Keys.export)
            activateCustomMode(for: exportPath)
        }
    }
    @Published var quickExportPath: String? {
        didSet {
            defaults.set(quickExportPath, forKey: Keys.quickExport)
            activateCustomMode(for: quickExportPath)
        }
    }
    @Published var scansPath: String? {
        didSet {
            defaults.set(scansPath, forKey: Keys.scans)
            activateCustomMode(for: scansPath)
        }
    }
    @Published var importedSourcesPath: String? {
        didSet {
            defaults.set(importedSourcesPath, forKey: Keys.importedSources)
            activateCustomMode(for: importedSourcesPath)
        }
    }
    @Published var cleanedRawPath: String? {
        didSet {
            if let oldValue, oldValue != cleanedRawPath, !oldValue.isEmpty,
               !cleanedRawHistoryPaths.contains(oldValue) {
                cleanedRawHistoryPaths.append(oldValue)
                defaults.set(cleanedRawHistoryPaths, forKey: Keys.cleanedRawHistory)
            }
            if let cleanedRawPath, !cleanedRawPath.isEmpty {
                CleanedRawCacheFile.registerDirectory(
                    URL(fileURLWithPath: cleanedRawPath, isDirectory: true)
                )
            }
            defaults.set(cleanedRawPath, forKey: Keys.cleanedRaw)
            activateCustomMode(for: cleanedRawPath)
        }
    }
    @Published var scanPreviewsPath: String? {
        didSet {
            defaults.set(scanPreviewsPath, forKey: Keys.scanPreviews)
            activateCustomMode(for: scanPreviewsPath)
        }
    }
    @Published var recentCreatedScanFolderPath: String? {
        didSet { defaults.set(recentCreatedScanFolderPath, forKey: Keys.recentCreatedScanFolder) }
    }
    private var cleanedRawHistoryPaths: [String]

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        let storedMode = defaults.string(forKey: Keys.locationMode)
            .flatMap(DiskStorageLocationMode.init(rawValue:))
        locationMode = storedMode ?? (Self.hasLegacyCustomPaths(in: defaults) ? .custom : .iCloud)
        specificFolderPath = defaults.string(forKey: Keys.specificFolder)
        cleanedRawHistoryPaths = defaults.stringArray(forKey: Keys.cleanedRawHistory) ?? []
        rootPath = defaults.string(forKey: Keys.root)
        thumbnailsPath = defaults.string(forKey: Keys.thumbnails)
        exportPath = defaults.string(forKey: Keys.export)
        quickExportPath = defaults.string(forKey: Keys.quickExport)
            ?? defaults.string(forKey: Keys.legacyQuickExport)
        scansPath = defaults.string(forKey: Keys.scans)
        importedSourcesPath = defaults.string(forKey: Keys.importedSources)
        cleanedRawPath = defaults.string(forKey: Keys.cleanedRaw)
        scanPreviewsPath = defaults.string(forKey: Keys.scanPreviews)
        recentCreatedScanFolderPath = defaults.string(forKey: Keys.recentCreatedScanFolder)
        for directory in cleanedRawKnownDirectories {
            CleanedRawCacheFile.registerDirectory(directory)
        }
    }

    /// 기본 루트: iCloud Drive/negaflow → (iCloud Drive 없음) ~/Documents/negaflow.
    nonisolated static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        let iCloudDocs = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true
        )
        if fileManager.fileExists(atPath: iCloudDocs.path) {
            return iCloudDocs.appendingPathComponent(FolderName.root, isDirectory: true)
        }
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent(FolderName.root, isDirectory: true)
    }

    nonisolated static func desktopRootURL(fileManager: FileManager = .default) -> URL {
        let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        return desktop.appendingPathComponent(FolderName.root, isDirectory: true)
    }

    var rootURL: URL {
        rootURL(for: locationMode)
    }
    var thumbnailsURL: URL {
        managedURL(named: FolderName.thumbnails, customPath: thumbnailsPath)
    }
    var exportURL: URL {
        managedURL(named: FolderName.export, customPath: exportPath)
    }
    var quickExportURL: URL {
        managedURL(named: FolderName.quickExport, customPath: quickExportPath)
    }
    /// 스캔 원본 TIFF 보관 폴더(루트 고정 하위). 캐시가 아니라 원본이므로 캐시 지우기 대상이 아니다.
    var scansURL: URL {
        managedURL(named: FolderName.scans, customPath: scansPath)
    }
    /// 가져온 원본을 사용자가 명시적으로 이동할 때 폴더 선택기가 시작하는 기본 위치.
    var importedSourcesURL: URL {
        managedURL(named: FolderName.importedSources, customPath: importedSourcesPath)
    }
    var cleanedRawURL: URL {
        if locationMode != .custom {
            return rootURL.appendingPathComponent(FolderName.cleanedRaw, isDirectory: true)
        }
        return resolved(cleanedRawPath) ?? CleanedRawCacheFile.defaultDirectoryURL(fileManager: fileManager)
    }
    var cleanedRawKnownDirectories: [URL] {
        let paths = cleanedRawHistoryPaths + [cleanedRawURL.path]
        return Array(Set(paths)).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    var scanPreviewsURL: URL {
        if locationMode != .custom {
            return rootURL.appendingPathComponent(FolderName.managedScanPreviews, isDirectory: true)
        }
        return resolved(scanPreviewsPath) ?? Self.defaultScanPreviewsURL(fileManager: fileManager)
    }
    var recentCreatedScanFolderURL: URL? {
        resolved(recentCreatedScanFolderPath)
    }

    nonisolated static func defaultScanPreviewsURL(fileManager: FileManager = .default) -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return caches
            .appendingPathComponent(FolderName.root, isDirectory: true)
            .appendingPathComponent(FolderName.scanPreviews, isDirectory: true)
    }

    func resetToDefaults() {
        rootPath = nil
        thumbnailsPath = nil
        exportPath = nil
        quickExportPath = nil
        scansPath = nil
        importedSourcesPath = nil
        cleanedRawPath = nil
        scanPreviewsPath = nil
        recentCreatedScanFolderPath = nil
    }

    func selectLocationMode(_ mode: DiskStorageLocationMode) {
        locationMode = mode
        if mode != .custom {
            ensureCurrentFolders()
        }
    }

    func selectSpecificFolder(_ parentURL: URL) {
        specificFolderPath = parentURL.standardizedFileURL.path
        locationMode = .specificFolder
        ensureCurrentFolders()
    }

    private func ensureCurrentFolders() {
        [
            rootURL, thumbnailsURL, exportURL, quickExportURL, scansURL,
            importedSourcesURL, cleanedRawURL, scanPreviewsURL,
        ].forEach { _ = Self.ensureDirectory($0, fileManager: fileManager) }
    }

    private func rootURL(for mode: DiskStorageLocationMode) -> URL {
        switch mode {
        case .iCloud:
            return Self.defaultRootURL(fileManager: fileManager)
        case .desktop:
            return Self.desktopRootURL(fileManager: fileManager)
        case .specificFolder:
            return resolved(specificFolderPath)?
                .appendingPathComponent(FolderName.root, isDirectory: true)
                ?? Self.defaultRootURL(fileManager: fileManager)
        case .custom:
            return resolved(rootPath) ?? Self.defaultRootURL(fileManager: fileManager)
        }
    }

    private func managedURL(named folderName: String, customPath: String?) -> URL {
        if locationMode == .custom, let customURL = resolved(customPath) {
            return customURL
        }
        return rootURL.appendingPathComponent(folderName, isDirectory: true)
    }

    private func cleanedRawURL(for mode: DiskStorageLocationMode) -> URL {
        if mode != .custom {
            return rootURL(for: mode).appendingPathComponent(FolderName.cleanedRaw, isDirectory: true)
        }
        return resolved(cleanedRawPath) ?? CleanedRawCacheFile.defaultDirectoryURL(fileManager: fileManager)
    }

    private func registerCleanedRawDirectoryChange(from oldDirectory: URL?) {
        if let oldDirectory {
            let oldPath = oldDirectory.standardizedFileURL.path
            if oldPath != cleanedRawURL.standardizedFileURL.path,
               !cleanedRawHistoryPaths.contains(oldPath) {
                cleanedRawHistoryPaths.append(oldPath)
                defaults.set(cleanedRawHistoryPaths, forKey: Keys.cleanedRawHistory)
            }
            CleanedRawCacheFile.registerDirectory(oldDirectory)
        }
        CleanedRawCacheFile.registerDirectory(cleanedRawURL)
    }

    private func activateCustomMode(for path: String?) {
        guard let path, !path.isEmpty, locationMode != .custom else { return }
        locationMode = .custom
    }

    private nonisolated static func hasLegacyCustomPaths(in defaults: UserDefaults) -> Bool {
        [
            Keys.root, Keys.thumbnails, Keys.export, Keys.quickExport, Keys.scans,
            Keys.importedSources, Keys.cleanedRaw, Keys.scanPreviews, Keys.legacyQuickExport,
        ].contains { key in
            guard let value = defaults.string(forKey: key) else { return false }
            return !value.isEmpty
        }
    }

    private func resolved(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 폴더를 보장 생성하고 그대로 돌려준다(존재하면 no-op).
    nonisolated static func ensureDirectory(_ url: URL, fileManager: FileManager = .default) -> URL {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 디렉토리 전체 크기(바이트). 백그라운드에서 호출한다 — 파일 수에 비례하는 IO.
    nonisolated static func directorySize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
