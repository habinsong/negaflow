import SwiftUI
import AppKit
import Chromabase

extension CanvasView {
    /// 캔버스가 현재 이미지에 실제로 쓰는 디바이스 픽셀(긴 변). 줌·Retina 배율을 반영하며,
    /// 인터랙티브 현상 프록시가 이 값 이상으로 렌더돼 업스케일 블러가 생기지 않는다.
    /// 이미지가 아직 없으면 캔버스 크기로 상한 추정한다(과대추정은 안전 — 블러 없음).
    func displayTargetPixels(imageSize: NSSize?, canvasSize: CGSize) -> CGFloat {
        let scale = max(displayScale, 1)
        guard let imageSize else {
            return max(canvasSize.width, canvasSize.height) * scale
        }
        let fitted = canvasFittedImageFrame(for: imageSize, in: canvasSize, scale: viewport.scale, offset: .zero)
        return max(fitted.width, fitted.height) * scale
    }

    func resetViewport(animated: Bool = true) {
        if animated {
            withAnimation(.snappy(duration: 0.18)) { viewport.reset() }
        } else {
            viewport.reset()
        }
    }

    func setScale(_ newScale: CGFloat, imageSize: NSSize, canvasSize: CGSize) {
        withAnimation(.snappy(duration: 0.16)) {
            viewport.setScale(newScale, imageSize: imageSize, canvasSize: canvasSize)
        }
    }

    func zoomBy(_ multiplier: CGFloat, imageSize: NSSize?, canvasSize: CGSize) {
        guard let imageSize else { return }
        setScale(viewport.scale * multiplier, imageSize: imageSize, canvasSize: canvasSize)
    }

    func setZoomPercent(_ percent: Double, imageSize: NSSize, canvasSize: CGSize) {
        let scale = CGFloat(percent / 100)
        setScale(scale, imageSize: imageSize, canvasSize: canvasSize)
    }

    func panGesture(imageSize: NSSize?, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                guard let imageSize,
                      !cropMode,
                      !brushMode,
                      !regionDefectMode,
                      !basePickerMode,
                      !localAdjustmentSession.isActive(for: frame) else { return }
                viewport.updatePan(translation: value.translation, imageSize: imageSize, canvasSize: canvasSize)
            }
            .onEnded { _ in
                viewport.endPan()
            }
    }

    func zoomGesture(imageSize: NSSize?, canvasSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard let imageSize else { return }
                viewport.updateMagnification(value, imageSize: imageSize, canvasSize: canvasSize)
            }
            .onEnded { _ in
                viewport.endMagnification()
            }
    }

    /// 엔진 크롭(y-up 정규좌표 (x, y, w, h))을 표시 좌표(y-down) 선택 사각형으로 변환.
    /// 크롭은 회전/플립 **이후** 마지막에 적용되므로 표시 좌표계와 동일 축이다(y만 뒤집음).
    func displayRect(for crop: SIMD4<Double>?) -> CGRect {
        guard let c = crop else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return clampedUnitRect(CGRect(
            x: c.x,
            y: 1 - (c.y + c.w),
            width: c.z,
            height: c.w
        ))
    }

    func cropAspectLockRatio(for imageSize: NSSize) -> CGFloat? {
        guard isCropAspectLocked, imageSize.width > 0, imageSize.height > 0 else { return nil }
        if let aspect = frame.imageTransform.cropAspect, aspect > 0 {
            return CGFloat(aspect)
        }
        let visible = clampedUnitRect(cropRect)
        guard visible.width > 0, visible.height > 0 else {
            return imageSize.width / imageSize.height
        }
        return max(0.05, min(20, (visible.width * imageSize.width) / (visible.height * imageSize.height)))
    }

    func applyCrop() {
        // 진입 시 크롭을 해제해 전체를 보고 있으므로, 선택 영역을 **절대 크롭**으로 그대로 설정한다(중첩 없음).
        frame.updateTransform {
            $0.cropRect = engineCrop(from: cropRect, existingCrop: nil)
        }
        cropSessionActive = false
        preCropRect = nil
        cropMode = false
        resetViewport()
        model.applyTransformFast(frame)
    }

    func resetCrop() {
        // "Full": 크롭 없음. 이미 전체를 보고 있으니 선택만 가득 채우고 복원 대상도 비운다.
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        preCropRect = nil
    }

    func cancelCrop() {
        restorePreCropAfterCancellation()
        cropMode = false
    }

    func restorePreCropAfterCancellation() {
        guard cropSessionActive else { return }
        defer {
            cropSessionActive = false
            preCropRect = nil
        }
        if frame.imageTransform.cropRect != preCropRect {
            frame.updateTransform { $0.cropRect = preCropRect }
            model.applyTransformFast(frame)
        }
    }

}
