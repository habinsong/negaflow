import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

// 변형(회전/플립/크롭) 전용 CIContext. 캐시된 결과의 장치 색공간을 그대로 유지하고
// 색 관리를 끈 채 순수 기하 변형만 적용한다. PRINT printer-profile 픽셀을 sRGB로 왕복시키지 않는다.
// 전역 let이라 어떤 스레드에서도 안전하게 접근(CIContext.createCGImage는 thread-safe).
private let transformCIContext = CIContext(options: [
    .useSoftwareRenderer: false,
    .workingColorSpace: NSNull(),
    .outputColorSpace: NSNull(),
])

extension AppModel {
    func renderLatestTransform(for frame: ScanFrame) async {
        defer { frame.transformTask = nil }
        var revision = frame.transformRevision

        while true {
            guard !Task.isCancelled, let developedBase = frame.cachedDevelopedBase else { return }
            let transform = frame.imageTransform
            let proofRevision = softProofConfigurationRevision
            let showsClippingOverlay = clippingOverlayEnabled
            let clippingOverlayBase = showsClippingOverlay ? frame.cachedClippingOverlayBase : nil
            let showsDestinationGamut = softProofEnabled
                && destinationGamutWarningEnabled
                && destinationGamutWarningAvailable
                && frame.displayedSoftProofRevision == proofRevision
            let destinationGamutOverlayBase = showsDestinationGamut
                ? frame.cachedDestinationGamutOverlayBase
                : nil
            // ── 인터랙티브: 발색 base 한 장만, 캔버스 표시 해상도로 축소해 읽어온다.
            //    회전은 풀해상도에서 수행하고 readback만 줄여 품질은 정착과 동일 계열이다.
            let proxyDimension = DevelopFrameRenderer.interactiveProxyDimension(
                displayTargetPixels: canvasDisplayTargetPixels
            )
            let interactive = await Task.detached(priority: .userInitiated) { () -> TransformInteractiveResult? in
                guard let developed = Self.renderTransformed(
                    developedBase,
                    transform: transform,
                    maxDimension: proxyDimension
                ) else { return nil }
                let clippingOverlay = clippingOverlayBase.flatMap {
                    Self.renderTransformed($0, transform: transform, maxDimension: proxyDimension)
                }
                let destinationGamutOverlay = destinationGamutOverlayBase.flatMap {
                    Self.renderTransformed($0, transform: transform, maxDimension: proxyDimension)
                }
                return TransformInteractiveResult(
                    developed: developed,
                    clippingOverlay: clippingOverlay,
                    destinationGamutOverlay: destinationGamutOverlay
                )
            }.value
            guard !Task.isCancelled, proofRevision == softProofConfigurationRevision else { return }
            if let interactive {
                frame.noteDevelopedDisplaySize(
                    CGSize(width: interactive.developed.width, height: interactive.developed.height),
                    authoritative: false
                )
                frame.developedImage = NSImage(
                    cgImage: interactive.developed,
                    size: NSSize(width: interactive.developed.width, height: interactive.developed.height)
                )
                if clippingOverlayEnabled == showsClippingOverlay {
                    frame.clippingOverlayImage = interactive.clippingOverlay.map {
                        NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                    }
                }
                frame.destinationGamutOverlayImage = interactive.destinationGamutOverlay.map {
                    NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                }
                frame.developedPreviewTransform = transform
            }
            // 인터랙티브 후 리비전이 바뀌었으면(드래그 진행) 즉시 다음 인터랙티브로.
            guard frame.transformRevision == revision else {
                revision = frame.transformRevision
                continue
            }
            // 정착 감지: 추가 편집 없이 settle 윈도가 지나야 풀해상도로 마무리.
            if !(await waitForTransformSettle(frame, revision: revision)) {
                revision = frame.transformRevision
                continue
            }

            // ── 정착: 풀해상도 developed + raw/무보정/MAIN 비교본 + 필름스트립 썸네일.
            guard let settledBase = frame.cachedDevelopedBase else { return }
            let settledTransform = frame.imageTransform
            let rawBase = frame.cachedRawBase
            let neutralBase = frame.cachedNeutralBase
            let mainBase = frame.cachedMainBase
            let settledClippingOverlayBase = showsClippingOverlay ? frame.cachedClippingOverlayBase : nil
            let settledDestinationGamutOverlayBase = showsDestinationGamut
                ? frame.cachedDestinationGamutOverlayBase
                : nil
            let settledThumbnailBase = frame.cachedThumbnailBase
            let settled = await Task.detached(priority: .userInitiated) { () -> TransformSettleResult? in
                guard let developed = Self.renderTransformed(settledBase, transform: settledTransform, maxDimension: 0)
                else { return nil }
                let raw = rawBase.flatMap {
                    Task.isCancelled ? nil : Self.renderTransformed($0, transform: settledTransform, maxDimension: 0)
                }
                let neutral = neutralBase.flatMap {
                    Task.isCancelled ? nil : Self.renderTransformed($0, transform: settledTransform, maxDimension: 0)
                }
                let main = mainBase.flatMap {
                    Task.isCancelled ? nil : Self.renderTransformed($0, transform: settledTransform, maxDimension: 0)
                }
                let clippingOverlay = settledClippingOverlayBase.flatMap {
                    Task.isCancelled ? nil : Self.renderTransformed($0, transform: settledTransform, maxDimension: 0)
                }
                let destinationGamutOverlay = settledDestinationGamutOverlayBase.flatMap {
                    Task.isCancelled ? nil : Self.renderTransformed($0, transform: settledTransform, maxDimension: 0)
                }
                // 프루프 미적용 360px base에서 변형해 화면용 프루프가 영속 썸네일로 새지 않는다.
                let thumbnail = settledThumbnailBase.flatMap {
                    Task.isCancelled ? nil : Self.renderTransformed($0, transform: settledTransform, maxDimension: 0)
                }
                return TransformSettleResult(
                    developed: developed,
                    raw: raw,
                    neutral: neutral,
                    main: main,
                    clippingOverlay: clippingOverlay,
                    destinationGamutOverlay: destinationGamutOverlay,
                    thumbnail: thumbnail
                )
            }.value
            guard !Task.isCancelled, proofRevision == softProofConfigurationRevision else { return }
            guard frame.transformRevision == revision else {
                revision = frame.transformRevision
                continue
            }
            if let settled {
                frame.noteDevelopedDisplaySize(
                    CGSize(width: settled.developed.width, height: settled.developed.height),
                    authoritative: true
                )
                frame.developedImage = NSImage(
                    cgImage: settled.developed,
                    size: NSSize(width: settled.developed.width, height: settled.developed.height)
                )
                if clippingOverlayEnabled == showsClippingOverlay {
                    frame.clippingOverlayImage = settled.clippingOverlay.map {
                        NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                    }
                }
                frame.destinationGamutOverlayImage = settled.destinationGamutOverlay.map {
                    NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                }
                frame.developedPreviewTransform = settledTransform
                if let thumbnail = settled.thumbnail {
                    frame.thumbnailImage = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
                    // 변형이 반영된 세대를 기록하고 디스크 캐시까지 덮어쓴다. 예전에는 둘 다
                    // 빠져 있어서, 회전·플립한 사진의 썸네일이 화면에서는 돌아간 채 디스크에는
                    // 옛 방향으로 남았다 — 앱을 다시 켜면 그 옛 썸네일이 복원돼 필름스트립만
                    // 본 이미지와 다른 방향으로 보였다.
                    frame.thumbnailTransform = settledTransform
                    persistThumbnail(for: frame, cgImage: thumbnail)
                }
                if let raw = settled.raw {
                    frame.rawPreviewImage = NSImage(
                        cgImage: raw,
                        size: NSSize(width: raw.width, height: raw.height)
                    )
                    frame.rawPreviewTransform = settledTransform
                }
                if let neutral = settled.neutral {
                    frame.neutralPreviewImage = NSImage(
                        cgImage: neutral,
                        size: NSSize(width: neutral.width, height: neutral.height)
                    )
                    frame.neutralPreviewTransform = settledTransform
                }
                if let main = settled.main {
                    frame.mainPreviewImage = NSImage(
                        cgImage: main,
                        size: NSSize(width: main.width, height: main.height)
                    )
                    frame.mainPreviewTransform = settledTransform
                }
            }
            if frame.debugOverlayEnabled {
                Task { await self.developFrame(frame) }
            }
            return
        }
    }

    /// 추가 변형 편집 없이 settle 윈도가 지나면 true, 그 전에 새 리비전이 오면 false(드래그 진행).
    private func waitForTransformSettle(_ frame: ScanFrame, revision: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(0.14)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if frame.transformRevision != revision { return false }
        }
        return frame.transformRevision == revision
    }

    /// 변형-전 결과에 기하 변형만 적용해 sRGB display 픽셀로 읽어온다.
    /// maxDimension > 0 이면 변형 후 그 크기로 축소해 readback을 줄인다(인터랙티브 경로).
    nonisolated private static func renderTransformed(
        _ source: CGImage,
        transform: ImageTransform,
        maxDimension: CGFloat
    ) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let colorSpace = source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let unmanaged = CIImage(cgImage: source, options: [.colorSpace: NSNull()])
        var image = ImageTransformStage.apply(to: unmanaged, transform: transform)
        if maxDimension > 0 {
            image = DevelopFrameRenderer.displayProxy(image, maxDimension: maxDimension)
        }
        guard !Task.isCancelled else { return nil }
        return transformCIContext.createCGImage(
            image, from: image.extent, format: .RGBA8,
            colorSpace: colorSpace
        )
    }
}

private struct TransformSettleResult: @unchecked Sendable {
    let developed: CGImage
    let raw: CGImage?
    let neutral: CGImage?
    let main: CGImage?
    let clippingOverlay: CGImage?
    let destinationGamutOverlay: CGImage?
    let thumbnail: CGImage?
}

private struct TransformInteractiveResult: @unchecked Sendable {
    let developed: CGImage
    let clippingOverlay: CGImage?
    let destinationGamutOverlay: CGImage?
}
