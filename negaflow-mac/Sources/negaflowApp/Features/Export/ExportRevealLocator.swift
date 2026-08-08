import Foundation

// 내보내기 결과를 Finder 로 보여줄 폴더를 고른다.
//
// 실제 저장 위치는 루트가 아니라 `<루트>/<날짜>/<출처 폴더>` 다(AppModel.exportDestinationFolder).
// 루트만 열면 사용자가 사진을 찾으러 다시 두 단계를 들어가야 하므로, 실제로 존재하는 가장 구체적인
// 폴더를 고른다. 다만 여기서는 폴더를 **만들지 않는다** — 아직 내보내기 전에 Finder 버튼을 눌렀다고
// 빈 날짜 폴더가 생기면 안 된다(그건 내보내기 시점의 ensureDirectory 가 할 일이다).
enum ExportRevealLocator {
    /// 우선순위:
    ///  ① 오늘 날짜의 출처 폴더 — 있으면 다음 내보내기도 여기로 간다.
    ///  ② 같은 출처로 내보낸 적 있는 가장 최근 날짜 폴더 — 어제 내보낸 사진을 바로 보여준다.
    ///  ③ 존재하는 가장 가까운 상위 — 한 번도 내보내지 않았어도 Finder 창은 반드시 뜬다.
    static func folder(root: URL,
                       group rawGroup: String?,
                       date: Date = Date(),
                       fileManager: FileManager = .default) -> URL {
        let sanitized = FrameStorageNaming.sanitizeComponent(
            rawGroup ?? FrameStorageNaming.defaultImportGroup
        )
        let group = sanitized.isEmpty ? FrameStorageNaming.defaultImportGroup : sanitized

        let today = root
            .appendingPathComponent(FrameStorageNaming.dateFolderName(for: date), isDirectory: true)
            .appendingPathComponent(group, isDirectory: true)
        if isDirectory(today, fileManager: fileManager) { return today }

        // 날짜 폴더명은 yyyyMMdd 라 이름 내림차순이 곧 최신순이다.
        let dateFolders = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let latest = dateFolders
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { $0.appendingPathComponent(group, isDirectory: true) }
            .first { isDirectory($0, fileManager: fileManager) }
        if let latest { return latest }

        return nearestExistingDirectory(root, fileManager: fileManager)
    }

    /// 존재하는 가장 가까운 상위 디렉터리. Finder 창이 반드시 뜨게 하는 마지막 보루다.
    static func nearestExistingDirectory(_ url: URL, fileManager: FileManager = .default) -> URL {
        var target = url
        while !isDirectory(target, fileManager: fileManager), target.pathComponents.count > 1 {
            target = target.deletingLastPathComponent()
        }
        return target
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
