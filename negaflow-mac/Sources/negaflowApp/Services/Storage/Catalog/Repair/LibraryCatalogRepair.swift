import Foundation

/// 이미 저장된 카탈로그의 정합성을 카탈로그 안에서 되돌린다.
///
/// 원칙 하나: **사진 레코드는 절대 지우지 않는다.** 되돌리는 대상은 소속·스캔 이력·추적
/// 지문·컬렉션 같은 부수 기록뿐이고, 값을 창작하지 않고 카탈로그에 이미 있는 사실에서
/// 유도한다(예: 롤의 필름 종류는 그 롤 사진들의 필름 종류에서).
///
/// 이 수리는 **여는 경로에서만** 쓴다. 새로 쓰는 카탈로그는 여전히 `canOpenSafely`(error 0)를
/// 통과해야 하며, 저장 검증은 완화하지 않는다.
enum LibraryCatalogRepair {
    static func repair(
        _ catalog: LibraryCatalog,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        cleanedRawDirectory: URL = CleanedRawCacheFile.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) -> LibraryCatalogRepairResult {
        var working = catalog
        var report = LibraryCatalogRepairReport()

        repairRolls(&working, report: &report)
        repairScanWorkflow(&working, report: &report)
        repairOrganizer(&working, report: &report)
        // 가상 사본은 롤 소속이 확정된 뒤에 맞춘다.
        repairVirtualCopies(&working, report: &report)
        // 프레임 단계는 앞의 재구성이 끝난 카탈로그를 다시 검사해서 남은 것만 손댄다.
        repairFrames(
            &working,
            defectDirectory: defectDirectory,
            cleanedRawDirectory: cleanedRawDirectory,
            fileManager: fileManager,
            report: &report
        )

        return LibraryCatalogRepairResult(catalog: working, report: report)
    }

    /// 수리한 카탈로그가 실제로 열 수 있는 상태가 되었을 때만 결과를 돌려준다.
    /// 수리가 아무것도 못 고쳤거나 error 가 남으면 nil 이다 — 호출부는 기존 차단 흐름을 탄다.
    static func repairedCatalogIfOpenable(
        _ catalog: LibraryCatalog,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        cleanedRawDirectory: URL = CleanedRawCacheFile.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) -> LibraryCatalogRepairResult? {
        let result = repair(
            catalog,
            defectDirectory: defectDirectory,
            cleanedRawDirectory: cleanedRawDirectory,
            fileManager: fileManager
        )
        guard result.didRepair else { return nil }
        let health = LibraryCatalogHealthInspector.inspect(
            result.catalog,
            defectDirectory: defectDirectory,
            cleanedRawDirectory: cleanedRawDirectory,
            fileManager: fileManager,
            includeWarnings: false
        )
        guard health.canOpenSafely else { return nil }
        return result
    }

    // MARK: 공용 도우미

    static func uniqued(_ ids: [UUID]) -> (ids: [UUID], removed: Int) {
        var seen = Set<UUID>()
        var result: [UUID] = []
        result.reserveCapacity(ids.count)
        for id in ids where seen.insert(id).inserted {
            result.append(id)
        }
        return (result, ids.count - result.count)
    }
}
