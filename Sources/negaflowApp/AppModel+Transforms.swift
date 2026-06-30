import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

// 변형(회전/플립/크롭) 전용 CIContext. 캐시된 결과는 이미 sRGB display 픽셀이므로
// 작업/출력 색공간을 sRGB로 맞춰 불필요한 감마 왕복 없이 순수 기하 변형만 적용한다.
// 전역 let이라 어떤 스레드에서도 안전하게 접근(CIContext.createCGImage는 thread-safe).
private let transformCIContext = CIContext(options: [
    .useSoftwareRenderer: false,
    .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
])

extension AppModel {
    func deleteFrame(_ frame: ScanFrame) {
        discardCleanedRaw(frame)
        evictDevelopBuffers(frame)
        residentDevelopedIDs.removeAll { $0 == frame.id }
        frames.removeAll { $0.id == frame.id }
        if selectedFrameID == frame.id { selectedFrameID = frames.last?.id }
    }

    /// 발색 CGImage → 필름스트립용 경량 썸네일(긴 변 ~360px). 축소만, 색 연산 없음.
    nonisolated static func makeThumbnail(_ cg: CGImage, context: CIContext, colorSpace: CGColorSpace) -> CGImage? {
        let maxSide = CGFloat(max(cg.width, cg.height))
        let maxDim: CGFloat = 360
        guard maxSide > maxDim else { return cg }
        let scale = maxDim / maxSide
        let image = CIImage(cgImage: cg).applyingFilter("CILanczosScaleTransform", parameters: [
            "inputScale": scale, "inputAspectRatio": 1.0,
        ])
        let target = CGRect(origin: .zero,
                            size: CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale))
        return context.createCGImage(image, from: target, format: .RGBA8, colorSpace: colorSpace)
    }

    func rotate(_ frame: ScanFrame, clockwise: Bool) {
        frame.updateTransform {
            $0.rotation = clockwise
                ? $0.rotation.rotatedClockwise()
                : $0.rotation.rotatedCounterClockwise()
        }
        applyTransformFast(frame)
    }

    func flipHorizontally(_ frame: ScanFrame) {
        frame.updateTransform { $0.flipHorizontal.toggle() }
        applyTransformFast(frame)
    }

    func flipVertically(_ frame: ScanFrame) {
        frame.updateTransform { $0.flipVertical.toggle() }
        applyTransformFast(frame)
    }

    func resetTransform(_ frame: ScanFrame) {
        frame.imageTransform = .identity
        applyTransformFast(frame)
    }

    /// 미세 회전(수평 보정) 각도 적용. 캐시된 결과에 변형만 다시 얹어 즉시 반영.
    func setStraighten(_ frame: ScanFrame, angle: Double) {
        frame.updateTransform { $0.straightenAngle = min(max(angle, -45), 45) }
        applyTransformFast(frame)
    }

    /// 크롭 종횡비 적용. nil = 원본(크롭 제거). 그 외엔 현재(회전 반영) 크기 안에서 종횡비를 만족하는
    /// 중앙 최대 사각형으로 크롭한다.
    func applyCropAspect(_ frame: ScanFrame, ratio: Double?) {
        guard let ratio, ratio > 0 else {
            frame.updateTransform { $0.cropAspect = nil; $0.cropRect = nil }
            applyTransformFast(frame)
            return
        }
        guard let base = frame.cachedDevelopedBase else {
            frame.updateTransform { $0.cropAspect = ratio }
            return
        }
        var w = Double(base.width), h = Double(base.height)
        if frame.imageTransform.rotation == .deg90 || frame.imageTransform.rotation == .deg270 {
            swap(&w, &h)
        }
        let cw: Double, ch: Double
        if w / h > ratio { ch = h; cw = ratio * h } else { cw = w; ch = w / ratio }
        let nw = cw / w, nh = ch / h
        let nx = (1 - nw) / 2, ny = (1 - nh) / 2
        frame.updateTransform {
            $0.cropAspect = ratio
            $0.cropRect = SIMD4(nx, ny, nw, nh)
        }
        applyTransformFast(frame)
    }

    /// 회전/플립/크롭을 즉시 반영한다. 변형은 순수 기하 연산이라 무거운 색 현상
    /// 파이프라인을 다시 돌릴 필요 없이, 캐시된 변형-전 결과에 `ImageTransformStage`만
    /// 다시 적용한다. 캐시가 없으면(최초 현상 전) 전체 현상으로 폴백한다.
    func applyTransformFast(_ frame: ScanFrame) {
        nextScanOrientation = frame.imageTransform.orientationTemplate
        // 변형 전 현상 결과를 변형한다. 입력 raw가 cleaned raw라 결함 제거도 이미 포함되어 있어
        // 회전/플립/크롭 후에도 유지된다.
        guard let developedBase = frame.cachedDevelopedBase else {
            Task { await developFrame(frame) }
            return
        }
        let transform = frame.imageTransform
        let rawBase = frame.cachedRawBase
        let neutralBase = frame.cachedNeutralBase
        Task.detached(priority: .userInitiated) {
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            func transformed(_ source: CGImage?) -> CGImage? {
                guard let source else { return nil }
                let image = ImageTransformStage.apply(to: CIImage(cgImage: source), transform: transform)
                return transformCIContext.createCGImage(
                    image, from: image.extent, format: .RGBA8, colorSpace: colorSpace
                )
            }
            let developed = transformed(developedBase)
            let raw = transformed(rawBase)
            let neutral = transformed(neutralBase)
            // 변형 후 필름스트립 썸네일도 새 방향으로 갱신(작은 축소만, 추가 색 연산 없음).
            let thumbnail = developed.flatMap { Self.makeThumbnail($0, context: transformCIContext, colorSpace: colorSpace) }
            await MainActor.run {
                if let developed {
                    frame.developedImage = NSImage(
                        cgImage: developed,
                        size: NSSize(width: developed.width, height: developed.height)
                    )
                }
                if let thumbnail {
                    frame.thumbnailImage = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
                }
                if let raw {
                    frame.rawPreviewImage = NSImage(
                        cgImage: raw,
                        size: NSSize(width: raw.width, height: raw.height)
                    )
                    frame.rawPreviewTransform = transform
                }
                if let neutral {
                    frame.neutralPreviewImage = NSImage(
                        cgImage: neutral,
                        size: NSSize(width: neutral.width, height: neutral.height)
                    )
                    frame.neutralPreviewTransform = transform
                }
                if frame.debugOverlayEnabled {
                    Task { await self.developFrame(frame) }
                }
            }
        }
    }
}
