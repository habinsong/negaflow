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

    /// 복원된 프레임의 썸네일을 백그라운드에서 채운다. 디스크 캐시가 있으면 lazy-디코드 로드,
    /// 없으면 원본에서 생성해 캐시에 백킹한다(다음 실행부터는 로드만).
    func loadThumbnailsFromDisk(for restoredFrames: [ScanFrame]) {
        let jobs = restoredFrames.map { frame in
            (frame: frame, thumbURL: thumbnailFileURL(for: frame),
             rawURL: frame.rawScanURL, transform: frame.imageTransform)
        }
        let cache = thumbnailDiskCache
        Task.detached(priority: .utility) {
            for job in jobs {
                if let image = ThumbnailDiskCache.load(at: job.thumbURL) {
                    await MainActor.run {
                        guard self.ownsFrame(job.frame) else { return }
                        if job.frame.thumbnailImage == nil { job.frame.thumbnailImage = image }
                    }
                    continue
                }
                guard let raw = AppModel.rawThumbnailCGImage(for: job.rawURL, maxPixelSize: 360) else {
                    continue
                }
                // 원본 픽셀이므로 현상 방향과 맞추기 위해 프레임 변형(회전/플립)을 적용한다.
                let cg = AppModel.orientedThumbnail(raw, transform: job.transform)
                await MainActor.run {
                    guard self.ownsFrame(job.frame), job.frame.thumbnailImage == nil else { return }
                    job.frame.thumbnailImage = NSImage(
                        cgImage: cg, size: NSSize(width: cg.width, height: cg.height)
                    )
                    cache.store(cg, for: job.frame.id, at: job.thumbURL)
                }
            }
        }
    }

    /// 결함 기록(sidecar/recipe)과 cleaned-raw 캐시는 세션을 넘어 보존되지 않는다 —
    /// 종료 시 cleaned raw가 원본 이미지에 구워지므로 시작 시 남아 있는 파일은 전부
    /// (이전 빌드/비정상 종료의) 잔재이며 안전하게 제거한다.
    func sweepDefectStorageOrphans(
        catalog: LibraryCatalog,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        cleanedRawDirectory: URL = CleanedRawCacheFile.defaultDirectoryURL()
    ) async {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            for directory in [defectDirectory, cleanedRawDirectory] {
                guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else {
                    continue
                }
                for name in names {
                    try? fm.removeItem(at: directory.appendingPathComponent(name))
                }
            }
        }.value
    }

}
