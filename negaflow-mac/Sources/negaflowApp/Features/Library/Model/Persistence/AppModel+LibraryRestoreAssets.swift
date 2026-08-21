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
            (
                frame: frame,
                developedURL: thumbnailFileURL(for: frame),
                rawCacheURL: rawThumbnailFileURL(for: frame),
                legacyURL: legacyThumbnailFileURL(for: frame),
                sourceURL: frame.rawScanURL,
                transform: frame.imageTransform,
                requiresInversion: frame.filmType.requiresInversion,
                hasDevelopedOnce: frame.hasDevelopedOnce
            )
        }
        let cache = thumbnailDiskCache
        Task.detached(priority: .utility) {
            var framesNeedingDevelopedThumbnail: [ScanFrame] = []
            for job in jobs {
                let developed = ThumbnailDiskCache.load(at: job.developedURL)
                let cachedRaw = ThumbnailDiskCache.load(at: job.rawCacheURL)
                let legacy = ThumbnailDiskCache.load(at: job.legacyURL)
                // 디스크 캐시가 **어떤 방향으로** 그려졌는지는 파일만 봐서는 알 수 없다.
                // 여기서 현재 imageTransform 을 태그로 붙이면 "이미 맞는 방향"으로 간주돼
                // 다음 정착 현상이 다시 그리지 않고, 회전·플립한 사진의 썸네일이 영영 옛
                // 방향으로 남는다. transform 을 비워 두는 것이 ScanFrame.thumbnailTransform
                // 의 계약(nil = 이전 세션 캐시라 알 수 없음)이고, 그래야 스스로 복구된다.
                await MainActor.run {
                    guard self.ownsFrame(job.frame) else { return }
                    if let cachedRaw, job.frame.rawPreviewImage == nil {
                        job.frame.rawPreviewImage = cachedRaw
                    }
                    if let developed, job.frame.thumbnailImage == nil {
                        job.frame.thumbnailImage = developed
                    } else if job.hasDevelopedOnce,
                              let legacy,
                              job.frame.thumbnailImage == nil {
                        // 분리 전 캐시가 원본인지 현상본인지 확정할 수 없더라도 먼저 지워서
                        // 라이브러리를 빈칸으로 만들면 안 된다. 마지막으로 보이던 썸네일을
                        // 유지한 채 아래에서 저장된 params로 새 현상 캐시를 다시 만든다.
                        job.frame.thumbnailImage = legacy
                    } else if !job.requiresInversion,
                              let fallback = legacy ?? cachedRaw,
                              job.frame.thumbnailImage == nil {
                        // 포지티브의 legacy 원본/현상본은 모두 포지티브다. 새 분리 캐시가
                        // 생길 때까지 표시 폴백으로 안전하게 사용할 수 있다.
                        job.frame.thumbnailImage = fallback
                    } else if job.requiresInversion,
                              !job.hasDevelopedOnce,
                              let legacy,
                              job.frame.rawPreviewImage == nil {
                        // 한 번도 현상하지 않은 네거티브의 legacy 캐시는 원본 시드임이 확실하다.
                        // (방향은 위와 같은 이유로 태그하지 않는다 — 파일만 봐서는 알 수 없다.)
                        job.frame.rawPreviewImage = legacy
                    }
                }

                if cachedRaw == nil,
                   let raw = AppModel.rawThumbnailCGImage(
                       for: job.sourceURL,
                       maxPixelSize: 360
                   ) {
                    // 원본 픽셀이므로 현상 방향과 맞추기 위해 프레임 변형을 적용한다.
                    let cg = AppModel.orientedThumbnail(raw, transform: job.transform)
                    await MainActor.run {
                        guard self.ownsFrame(job.frame) else { return }
                        let image = NSImage(
                            cgImage: cg,
                            size: NSSize(width: cg.width, height: cg.height)
                        )
                        job.frame.rawPreviewImage = image
                        job.frame.rawPreviewTransform = job.transform
                        if !job.requiresInversion, job.frame.thumbnailImage == nil {
                            job.frame.thumbnailImage = image
                            job.frame.thumbnailTransform = job.transform
                        }
                    }
                    cache.store(cg, for: job.frame.id, at: job.rawCacheURL)
                }

                if job.requiresInversion,
                   job.hasDevelopedOnce,
                   developed == nil,
                   FileManager.default.fileExists(atPath: job.sourceURL.path) {
                    // 분리 전 단일 캐시는 원본/현상본을 판별할 수 없다. 원본을 현상본으로
                    // 고정하지 않고 한 번 재현상해 신뢰 가능한 새 캐시를 만든다. legacy는
                    // 새 캐시 쓰기가 예약될 때 persistThumbnail이 제거하므로 여기서 먼저
                    // 지우지 않는다.
                    framesNeedingDevelopedThumbnail.append(job.frame)
                }
            }
            guard !framesNeedingDevelopedThumbnail.isEmpty else { return }
            let framesToDevelop = framesNeedingDevelopedThumbnail
            await MainActor.run {
                _ = self.developImportedFramesSequentially(framesToDevelop)
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
