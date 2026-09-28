import Darwin
import Foundation

/// 카탈로그가 선언한 결함 기록을 열지 못할 때 되살릴 수 있는 것만 되살린다. 내용을 새로
/// 만들지 않는다 — 권한을 되돌리거나 백업에 남은 같은 사진의 기록을 가져올 뿐이다.
enum DefectRecordRecovery {
    /// 앱이 쓴 기록인데 읽기 권한만 빠진 경우(다른 계정에서 복사, 권한 정리 도구 등) 소유자의
    /// 읽기·쓰기만 되돌린다. 남의 파일이면 건드리지 않는다.
    static func restoreOwnerAccessIfNeeded(
        for frameID: UUID,
        in directory: URL,
        fileManager: FileManager = .default
    ) {
        let path = DefectSidecarFile.url(for: frameID, in: directory).path
        guard fileManager.fileExists(atPath: path),
              !fileManager.isReadableFile(atPath: path),
              let attributes = try? fileManager.attributesOfItem(atPath: path),
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value else {
            return
        }
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: permissions | 0o600)],
            ofItemAtPath: path
        )
    }

    /// 기록이 사라졌거나 깨졌으면 가장 새 검증된 백업 세대에 남은 같은 사진의 기록으로 되살린다.
    /// 백업에 멀쩡히 있는데도 편집을 비우면 사용자가 한 결함 제거를 통째로 잃는다. 깨진 파일은
    /// 지우지 않고 라이브러리 폴더 옆에 보관한다. 되살리지 못하면 false.
    static func restoreFromBackup(
        for frameID: UUID,
        in directory: URL,
        backupDirectory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        switch DefectSidecarFile.read(for: frameID, in: directory) {
        case .missing, .invalid:
            break
        case .loaded, .unreadable, .unsupportedVersion:
            return false
        }
        let snapshots = LibraryBackupStore.validSnapshots(in: backupDirectory, fileManager: fileManager)
            .filter { $0.manifest.defectFrameIDs.contains(frameID) }
            .sorted(by: LibraryBackupOrdering.isNewerSnapshot)
        for snapshot in snapshots {
            let backupDefects = LibraryBackupStore.defectsDirectory(in: snapshot.directoryURL)
            guard case .loaded = DefectSidecarFile.read(for: frameID, in: backupDefects) else { continue }
            let destination = DefectSidecarFile.url(for: frameID, in: directory)
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destination.path) {
                    let preserved = directory.deletingLastPathComponent().appendingPathComponent(
                        "defects.corrupt-\(UUID().uuidString)",
                        isDirectory: true
                    )
                    try fileManager.createDirectory(at: preserved, withIntermediateDirectories: true)
                    try fileManager.moveItem(
                        at: destination,
                        to: preserved.appendingPathComponent(destination.lastPathComponent)
                    )
                }
                try fileManager.copyItem(
                    at: DefectSidecarFile.url(for: frameID, in: backupDefects),
                    to: destination
                )
                return true
            } catch {
                continue
            }
        }
        return false
    }
}
