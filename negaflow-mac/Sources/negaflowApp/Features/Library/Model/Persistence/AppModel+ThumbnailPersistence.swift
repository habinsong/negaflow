import AppKit
import Combine
import CoreImage
import Foundation
import Chromabase
import ScannerKit

extension AppModel {
    // MARK: 썸네일 디스크 캐시

    /// 현상 썸네일과 원본 프리뷰는 서로 다른 파일에 저장한다. 한 경로를 공유하면 늦게 끝난
    /// 원본 시드가 현상 썸네일을 덮어써, 재실행 뒤 네거티브 전체가 원본으로 보일 수 있다.
    func thumbnailFileURL(for frame: ScanFrame) -> URL {
        thumbnailDirectoryURL(for: frame)
            .appendingPathComponent("\(frame.id.uuidString)-developed.jpg")
    }

    func rawThumbnailFileURL(for frame: ScanFrame) -> URL {
        thumbnailDirectoryURL(for: frame)
            .appendingPathComponent("\(frame.id.uuidString)-raw.jpg")
    }

    /// 분리 전 캐시 경로. 네거티브에서는 원본인지 현상본인지 판별할 수 없어 표시용으로
    /// 신뢰하지 않는다.
    func legacyThumbnailFileURL(for frame: ScanFrame) -> URL {
        thumbnailDirectoryURL(for: frame)
            .appendingPathComponent("\(frame.id.uuidString).jpg")
    }

    private func thumbnailDirectoryURL(for frame: ScanFrame) -> URL {
        let group = FrameStorageNaming.sanitizeComponent(
            frame.storageGroupName ?? FrameStorageNaming.defaultImportGroup
        )
        return diskStorage.thumbnailsURL
            .appendingPathComponent(FrameStorageNaming.dateFolderName(for: frame.scannedAt), isDirectory: true)
            .appendingPathComponent(group.isEmpty ? FrameStorageNaming.defaultImportGroup : group, isDirectory: true)
    }

    /// 최신 썸네일을 디스크에 덮어쓴다(현상 정착/가져오기 시점). 백그라운드 코얼레싱 쓰기.
    func persistThumbnail(for frame: ScanFrame, cgImage: CGImage) {
        guard libraryPersistenceEnabled, !frame.isPreviewScan else { return }
        thumbnailDiskCache.store(cgImage, for: frame.id, at: thumbnailFileURL(for: frame))
        thumbnailDiskCache.remove(for: frame.id, at: legacyThumbnailFileURL(for: frame))
    }

    func persistRawThumbnail(for frame: ScanFrame, cgImage: CGImage) {
        guard libraryPersistenceEnabled, !frame.isPreviewScan else { return }
        thumbnailDiskCache.store(cgImage, for: frame.id, at: rawThumbnailFileURL(for: frame))
    }

    /// 대량 가져오기/스캔 완료의 시드 디코드 동시 폭 제한 — IO/메모리 폭주 방지(현상 슬롯과 분리).
    static let thumbnailSeedSemaphore = AsyncSemaphore(width: 3)

    /// 가져오기/스캔 직후 원본 프리뷰를 시드한다. 포지티브 원본은 그대로 첫 현상 썸네일로도 쓰고,
    /// 컬러/흑백 네거티브는 rawPreviewImage 에만 발행한다. 어느 쪽이든 원본 썸네일 캐시는 저장해
    /// 자동 현상 OFF인 새 가져오기도 앱 재실행 뒤 원본 썸네일을 즉시 복원한다.
    /// 디코드는 백그라운드(동시 폭 제한)에서 수행한다 — 폴더 가져오기·스캔 완료 때 파일마다 원본
    /// 디코드가 메인 스레드를 잡아 UI 전체가 멎던 병목 제거. 시드 → 현상 순서는
    /// developFrameAfterFastPreview 가 이 태스크를 await 해 기존과 동일하게 유지된다.
    func seedInitialThumbnail(for frame: ScanFrame, from url: URL) {
        let transform = frame.imageTransform
        let shouldPublishRawThumbnail = !frame.filmType.requiresInversion
        frame.initialThumbnailSeedTask?.cancel()
        frame.initialThumbnailSeedGeneration &+= 1
        let seedGeneration = frame.initialThumbnailSeedGeneration
        frame.initialThumbnailSeedTask = Task { [weak self, weak frame] in
            // 끝나면 참조를 지운다 — 남겨 두면 "시드 진행 중"으로 오해돼 축출된 프레임이 다시
            // 현상되지 않는다. 자기가 설치한 태스크일 때만 지우므로, 취소된 옛 태스크가 새
            // 참조를 덮어쓰는 레이스는 생기지 않는다.
            defer {
                if let frame, frame.initialThumbnailSeedGeneration == seedGeneration {
                    frame.initialThumbnailSeedTask = nil
                }
            }
            // 대기 중 취소 → 슬롯 미획득(CancellationError) — release 없이 종료한다.
            guard (try? await AppModel.thumbnailSeedSemaphore.acquire()) != nil else { return }
            let cg: CGImage?
            if Task.isCancelled {
                cg = nil
            } else {
                cg = await Task.detached(priority: .userInitiated) {
                    autoreleasepool {
                        AppModel.rawThumbnailCGImage(
                            for: url,
                            maxPixelSize: Int(DevelopFrameRenderer.thumbnailMaxDimension)
                        )
                            .map { AppModel.orientedThumbnail($0, transform: transform) }
                    }
                }.value
            }
            await AppModel.thumbnailSeedSemaphore.release()
            guard let self, let frame, let cg,
                  !Task.isCancelled,
                  self.ownsFrame(frame),
                  frame.thumbnailImage == nil else { return }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            frame.rawPreviewImage = image
            self.persistRawThumbnail(for: frame, cgImage: cg)
            if shouldPublishRawThumbnail {
                frame.thumbnailImage = image
                frame.thumbnailTransform = transform
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
        for url in [
            thumbnailFileURL(for: frame),
            rawThumbnailFileURL(for: frame),
            legacyThumbnailFileURL(for: frame),
        ] {
            thumbnailDiskCache.remove(for: frame.id, at: url)
        }
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
