import Foundation

/// 열지 못한 카탈로그를 디스크에서 다시 읽어 무엇이 어긋났는지 그대로 적어 둔다.
/// 실패 코드는 `corrupt` 하나로 뭉뚱그려지기 때문에, 지원 요청을 받았을 때 원인을 좁힐
/// 유일한 단서다. 경로·이름·사진 내용은 담지 않는다.
struct LibraryRecoveryCatalogInspection: Equatable {
    enum Readability: String {
        case missing
        case unreadable
        case invalid
        case unsupportedVersion
        case unsupportedStorageVersion
        case loaded
    }

    var readability: Readability
    var catalogVersion: Int?
    var frameCount: Int?
    var rollCount: Int?
    var blockingIssues: [String] = []
    var repairableIssues: [String] = []
    var repairableAfterRepair: Bool?

    var lines: [String] {
        var lines = ["catalogRead=\(readability.rawValue)"]
        if let catalogVersion { lines.append("catalogVersion=\(catalogVersion)") }
        if let frameCount { lines.append("frames=\(frameCount)") }
        if let rollCount { lines.append("rolls=\(rollCount)") }
        if !blockingIssues.isEmpty {
            lines.append("blocking=\(blockingIssues.joined(separator: " "))")
        }
        if !repairableIssues.isEmpty {
            lines.append("repairable=\(repairableIssues.joined(separator: " "))")
        }
        if let repairableAfterRepair {
            lines.append("repairResolvesIssues=\(repairableAfterRepair)")
        }
        return lines
    }

    static func inspect(
        catalogURL: URL,
        defectDirectory: URL,
        fileManager: FileManager = .default
    ) -> LibraryRecoveryCatalogInspection {
        switch LibraryCatalogFile.read(from: catalogURL, fileManager: fileManager) {
        case .missing:
            return LibraryRecoveryCatalogInspection(readability: .missing)
        case .unreadable:
            return LibraryRecoveryCatalogInspection(readability: .unreadable)
        case .invalid:
            return LibraryRecoveryCatalogInspection(readability: .invalid)
        case let .unsupportedVersion(version):
            return LibraryRecoveryCatalogInspection(
                readability: .unsupportedVersion,
                catalogVersion: version
            )
        case let .unsupportedStorageVersion(version):
            return LibraryRecoveryCatalogInspection(
                readability: .unsupportedStorageVersion,
                catalogVersion: version
            )
        case let .loaded(catalog, sourceVersion):
            let health = LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: defectDirectory,
                fileManager: fileManager,
                includeWarnings: false
            )
            var inspection = LibraryRecoveryCatalogInspection(
                readability: .loaded,
                catalogVersion: sourceVersion,
                frameCount: catalog.frames.count,
                rollCount: catalog.rolls.count,
                blockingIssues: counted(health.blockingIssues),
                repairableIssues: counted(health.repairableIssues)
            )
            if health.needsRepair {
                inspection.repairableAfterRepair = LibraryCatalogRepair
                    .repairedCatalogIfOpenable(
                        catalog,
                        defectDirectory: defectDirectory,
                        fileManager: fileManager
                    ) != nil
            }
            return inspection
        }
    }

    private static func counted(_ issues: [LibraryCatalogHealthIssue]) -> [String] {
        var counts: [String: Int] = [:]
        for issue in issues {
            counts[issue.code.rawValue, default: 0] += 1
        }
        return counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
    }
}
