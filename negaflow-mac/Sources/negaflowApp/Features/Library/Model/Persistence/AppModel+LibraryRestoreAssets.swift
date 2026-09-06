import AppKit
import Combine
import CoreImage
import Foundation
import Chromabase
import ScannerKit

extension AppModel {
    /// 설정에 표시되는 이미지 입력·출력·파생 캐시 폴더를 보장 생성한다.
    /// 사용자가 경로를 바꾼 경우 바꾼 위치가 생성된다. 백그라운드 IO.
    func ensureStorageFolders() {
        let urls = [
            diskStorage.rootURL,
            diskStorage.thumbnailsURL,
            diskStorage.exportURL,
            diskStorage.quickExportURL,
            diskStorage.scansURL,
            diskStorage.importedSourcesURL,
            diskStorage.cleanedRawURL,
            diskStorage.scanPreviewsURL,
        ]
        Task.detached(priority: .utility) {
            for url in urls {
                _ = DiskStorageStore.ensureDirectory(url)
            }
        }
    }

    /// 유효한 카탈로그가 소유한 recipe를 보존합니다. 알 수 없는 파일도 지우지 않습니다.
    func sweepDefectStorageOrphans(
        catalog: LibraryCatalog,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        cleanedRawDirectory: URL = CleanedRawCacheFile.defaultDirectoryURL()
    ) async {
        let frameIDs = Set(catalog.frames.map(\.id))
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            if let names = try? fm.contentsOfDirectory(atPath: defectDirectory.path) {
                for name in names where name.hasSuffix(".plist") {
                    guard let id = UUID(uuidString: String(name.dropLast(6))),
                          !frameIDs.contains(id) else { continue }
                    try? DefectSidecarFile.remove(for: id, in: defectDirectory)
                }
            }
            if let names = try? fm.contentsOfDirectory(atPath: cleanedRawDirectory.path) {
                for name in names {
                    guard let id = CleanedRawCacheFile.frameID(fromFileName: name),
                          !frameIDs.contains(id) else { continue }
                    let url = cleanedRawDirectory.appendingPathComponent(name)
                    guard CleanedRawCacheFile.isOwnedCacheURL(url, frameID: id,
                                                             directory: cleanedRawDirectory) else { continue }
                    try? fm.removeItem(at: url)
                }
            }
        }.value
    }
}
