import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
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
        frame.updateTransform { $0.rotatePreservingCrop(clockwise: clockwise) }
        applyTransformFast(frame)
    }

    func flipHorizontally(_ frame: ScanFrame) {
        frame.updateTransform { $0.toggleHorizontalFlipPreservingCrop() }
        applyTransformFast(frame)
    }

    func flipVertically(_ frame: ScanFrame) {
        frame.updateTransform { $0.toggleVerticalFlipPreservingCrop() }
        applyTransformFast(frame)
    }

    func resetTransform(_ frame: ScanFrame) {
        frame.imageTransform = .identity
        applyTransformFast(frame)
    }

    func resetPhotoAngle(_ frame: ScanFrame) {
        frame.updateTransform {
            $0.rotation = .deg0
            $0.straightenAngle = 0
        }
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

    /// 회전/플립/크롭/수평보정(Angle)을 즉시 반영한다. 변형은 순수 기하 연산이라 무거운 색 현상
    /// 파이프라인을 다시 돌릴 필요 없이, 캐시된 변형-전 결과에 `ImageTransformStage`만 다시 적용한다.
    /// 캐시가 없으면(최초 현상 전) 전체 현상으로 폴백한다.
    ///
    /// Angle 슬라이더 같은 연속 편집은 틱마다 새 렌더 태스크를 쌓지 않는다(과거: 틱마다 풀해상도
    /// 3장 + 썸네일 렌더/readback ≈ 130MB → GPU 백로그로 슬라이더가 이미지를 앞질렀다).
    /// 대신 현상 경로(renderLatestDevelopment)와 같은 코얼레싱 루프: 진행 중이면 리비전만 올리고,
    /// 루프가 항상 최신 transform 하나만 렌더한다 — 드래그 중엔 표시 해상도 한 장(작은 readback),
    /// 정착 후 풀해상도 + raw/무보정/썸네일을 채운다.
    func applyTransformFast(_ frame: ScanFrame) {
        nextScanOrientation = frame.imageTransform.orientationTemplate
        frame.transformRevision += 1
        // 변형 전 현상 결과를 변형한다. 입력 raw가 cleaned raw라 결함 제거도 이미 포함되어 있어
        // 회전/플립/크롭 후에도 유지된다.
        guard frame.cachedDevelopedBase != nil else {
            Task { await developFrame(frame) }
            return
        }
        guard frame.transformTask == nil else { return }
        frame.transformTask = Task { [weak self] in
            await self?.renderLatestTransform(for: frame)
        }
    }


}

private extension ImageTransform {
    mutating func rotatePreservingCrop(clockwise: Bool) {
        rotation = clockwise
            ? rotation.rotatedClockwise()
            : rotation.rotatedCounterClockwise()

        if let cropAspect, cropAspect > 0 {
            self.cropAspect = 1 / cropAspect
        }
        guard let cropRect else { return }
        self.cropRect = clockwise
            ? SIMD4(cropRect.y, 1 - cropRect.x - cropRect.z, cropRect.w, cropRect.z)
            : SIMD4(1 - cropRect.y - cropRect.w, cropRect.x, cropRect.w, cropRect.z)
    }

    mutating func toggleHorizontalFlipPreservingCrop() {
        toggleFlipPreservingCrop(displayHorizontal: true)
    }

    mutating func toggleVerticalFlipPreservingCrop() {
        toggleFlipPreservingCrop(displayHorizontal: false)
    }

    /// 사용자가 누르는 축은 **화면에 보이는** 축이다. 변형 순서가 flip → rotate 라서 90/270 회전에서는
    /// 소스 수평 플립이 화면에서는 수직으로 나타난다 — 그래서 회전한 뒤 "좌우 뒤집기"를 누르면
    /// 상하가 뒤집혔다. 화면 축을 소스 축으로 옮겨 토글한다.
    mutating func toggleFlipPreservingCrop(displayHorizontal: Bool) {
        let rotationSwapsAxes = rotation == .deg90 || rotation == .deg270
        if displayHorizontal != rotationSwapsAxes {
            flipHorizontal.toggle()
        } else {
            flipVertical.toggle()
        }

        straightenAngle = -straightenAngle
        guard var cropRect else { return }
        // cropRect 는 회전 뒤(=화면) 좌표계라 누른 축 그대로 미러한다.
        if displayHorizontal {
            cropRect.x = 1 - cropRect.x - cropRect.z
        } else {
            cropRect.y = 1 - cropRect.y - cropRect.w
        }
        self.cropRect = cropRect
    }
}
