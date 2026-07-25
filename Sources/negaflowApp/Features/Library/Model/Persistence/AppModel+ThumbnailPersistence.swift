import AppKit
import Combine
import CoreImage
import Foundation
import Chromabase
import ScannerKit

extension AppModel {
    // MARK: 썸네일 디스크 캐시

    /// 프레임 썸네일의 디스크 경로: <썸네일 폴더>/<yyyyMMdd(최초 사용일)>/<출처>/<프레임 id>.jpg
    func thumbnailFileURL(for frame: ScanFrame) -> URL {
        let group = FrameStorageNaming.sanitizeComponent(
            frame.storageGroupName ?? FrameStorageNaming.defaultImportGroup
        )
        return diskStorage.thumbnailsURL
            .appendingPathComponent(FrameStorageNaming.dateFolderName(for: frame.scannedAt), isDirectory: true)
            .appendingPathComponent(group.isEmpty ? FrameStorageNaming.defaultImportGroup : group, isDirectory: true)
            .appendingPathComponent("\(frame.id.uuidString).jpg")
    }

    /// 최신 썸네일을 디스크에 덮어쓴다(현상 정착/가져오기 시점). 백그라운드 코얼레싱 쓰기.
    func persistThumbnail(for frame: ScanFrame, cgImage: CGImage) {
        guard libraryPersistenceEnabled, !frame.isPreviewScan else { return }
        thumbnailDiskCache.store(cgImage, for: frame.id, at: thumbnailFileURL(for: frame))
    }

    /// 대량 가져오기/스캔 완료의 시드 디코드 동시 폭 제한 — IO/메모리 폭주 방지(현상 슬롯과 분리).
    static let thumbnailSeedSemaphore = AsyncSemaphore(width: 3)

    /// 가져오기/스캔 직후 원본 프리뷰를 시드한다. 포지티브 원본은 그대로 첫 썸네일로 쓰지만,
    /// 컬러/흑백 네거티브는 rawPreviewImage 에만 보관하고 thumbnailImage 는 빠른 현상 결과가 처음 채운다.
    /// 디코드는 백그라운드(동시 폭 제한)에서 수행한다 — 폴더 가져오기·스캔 완료 때 파일마다 원본
    /// 디코드가 메인 스레드를 잡아 UI 전체가 멎던 병목 제거. 시드 → 현상 순서는
    /// developFrameAfterFastPreview 가 이 태스크를 await 해 기존과 동일하게 유지된다.
    func seedInitialThumbnail(for frame: ScanFrame, from url: URL) {
        let transform = frame.imageTransform
        let shouldPublishRawThumbnail = !frame.filmType.requiresInversion
        frame.initialThumbnailSeedTask?.cancel()
        frame.initialThumbnailSeedTask = Task { [weak self, weak frame] in
            // 대기 중 취소 → 슬롯 미획득(CancellationError) — release 없이 종료한다.
            guard (try? await AppModel.thumbnailSeedSemaphore.acquire()) != nil else { return }
            let cg: CGImage?
            if Task.isCancelled {
                cg = nil
            } else {
                cg = await Task.detached(priority: .userInitiated) {
                    autoreleasepool {
                        AppModel.rawThumbnailCGImage(for: url, maxPixelSize: 720)
                            .map { AppModel.orientedThumbnail($0, transform: transform) }
                    }
                }.value
            }
            await AppModel.thumbnailSeedSemaphore.release()
            // 완료된 태스크 참조는 그대로 둔다 — 여기서 nil 로 지우면 취소된 옛 태스크가 새로
            // 설치된 태스크 참조를 지우는 레이스가 생긴다(await 하는 쪽은 완료 즉시 반환).
            guard let self, let frame, let cg,
                  !Task.isCancelled,
                  self.ownsFrame(frame),
                  frame.thumbnailImage == nil else { return }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            frame.rawPreviewImage = image
            if shouldPublishRawThumbnail {
                frame.thumbnailImage = image
                self.persistThumbnail(for: frame, cgImage: cg)
            }
        }
    }

    // 첫/복원 썸네일은 원본 파일 픽셀(변형 전)이라, 프레임의 방향 변형(회전/플립)을 적용해 현상
    // 결과와 방향을 맞춘다 — 스캔 방향 템플릿(nextScanOrientation)이 걸린 프레임에서 썸네일이
    // 현상본과 180°/90° 어긋나지 않게 한다. identity면 원본 그대로(무연산).
    // CIContext 는 스레드 안전 — 시드(메인)와 복원 폴백(백그라운드)이 공유한다.
    nonisolated private static let thumbnailOrientContext =
        CIContext(options: [.cacheIntermediates: false])

    nonisolated static func orientedThumbnail(_ cg: CGImage, transform: ImageTransform) -> CGImage {
        guard !transform.isIdentity else { return cg }
        let transformed = ImageTransformStage.apply(to: CIImage(cgImage: cg), transform: transform)
        let space = cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return thumbnailOrientContext.createCGImage(
            transformed, from: transformed.extent, format: .RGBA8, colorSpace: space
        ) ?? cg
    }

    /// 프레임 삭제 시 디스크 썸네일도 제거한다.
    func removeThumbnailFile(for frame: ScanFrame) {
        let url = thumbnailFileURL(for: frame)
        thumbnailDiskCache.remove(for: frame.id, at: url)
    }

    // MARK: 캐시 관리(설정 디스크 탭)

    func thumbnailCacheSizeBytes() async -> Int64 {
        let url = diskStorage.thumbnailsURL
        return await Task.detached(priority: .utility) {
            DiskStorageStore.directorySize(at: url)
        }.value
    }

    /// 썸네일 캐시 폴더를 디스크에서 삭제한다. 메모리에 이미 올라온 썸네일은 그대로 쓰이고,
    /// 다음 현상/가져오기 때 캐시가 다시 채워진다(카탈로그·원본은 무관).
    func clearThumbnailCache() async {
        let url = diskStorage.thumbnailsURL
        await thumbnailDiskCache.clear(at: url)
        statusMessage = text(AppLocalizedPhrase.diskThumbnailCacheClearedStatus)
    }

}
