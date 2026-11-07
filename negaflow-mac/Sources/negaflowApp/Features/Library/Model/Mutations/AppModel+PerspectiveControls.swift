import Chromabase
import CoreGraphics
import CoreImage
import Foundation

// 선 검출용 회색조를 만드는 CIContext. 출력은 sRGB 감마(사람 눈에 가까운 대비)로 읽는다.
private let perspectiveLumaContext = CIContext(options: [
    .useSoftwareRenderer: false,
    .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
])

extension AppModel {
    /// 변환 슬라이더·자르기 제한. 기하 변형이라 캐시된 현상 결과에 변형만 다시 얹는다.
    func updatePerspective(_ frame: ScanFrame, _ change: (inout PerspectiveCorrection) -> Void) {
        frame.updateTransform { change(&$0.perspective) }
        applyTransformFast(frame)
    }

    func resetPerspective(_ frame: ScanFrame) {
        updatePerspective(frame) { $0 = .identity }
    }

    /// 모드를 고른다. 자동 계열은 사진의 곧은 선을 한 번 찾아 푼 값을 저장하고, 도우미는 그려 둔
    /// 안내선으로 푼다. 끄면 푼 값만 지우고 슬라이더는 그대로 둔다.
    func selectPerspectiveMode(_ frame: ScanFrame, mode: PerspectiveMode) {
        switch mode {
        case .off:
            updatePerspective(frame) {
                $0.mode = .off
                $0.solvedVertical = 0
                $0.solvedHorizontal = 0
                $0.solvedRotate = 0
            }
        case .guided:
            updatePerspective(frame) {
                $0.mode = .guided
                Self.applyGuidedSolution(to: &$0, orientedSize: orientedSize(of: frame))
            }
        case .auto, .level, .vertical, .full:
            updatePerspective(frame) { $0.mode = mode }
            solvePerspectiveFromImage(frame, mode: mode)
        }
    }

    /// 도우미 안내선을 바꾸고 바로 다시 푼다. 안내선은 회전·뒤집기 뒤, 원근 보정 앞 좌표다.
    func setPerspectiveGuides(_ frame: ScanFrame, guides: [PerspectiveGuide]) {
        updatePerspective(frame) {
            $0.mode = .guided
            $0.guides = Array(guides.prefix(PerspectiveCorrection.maximumGuides))
            Self.applyGuidedSolution(to: &$0, orientedSize: orientedSize(of: frame))
        }
    }

    private func orientedSize(of frame: ScanFrame) -> CGSize? {
        let base: CGSize
        if let width = frame.sourcePixelWidth, let height = frame.sourcePixelHeight, width > 0, height > 0 {
            base = CGSize(width: width, height: height)
        } else if let cg = frame.cachedDevelopedBase {
            base = CGSize(width: cg.width, height: cg.height)
        } else {
            return nil
        }
        return frame.imageTransform.orientedSize(baseSize: base)
    }

    nonisolated static func applyGuidedSolution(to correction: inout PerspectiveCorrection, orientedSize: CGSize?) {
        let segments = correction.guides.map {
            PerspectiveLineSegment(start: $0.start, end: $0.end, length: 1)
        }
        guard let orientedSize,
              let solution = PerspectiveSolver.solve(mode: .guided, segments: segments, size: orientedSize)
        else {
            correction.solvedVertical = 0
            correction.solvedHorizontal = 0
            correction.solvedRotate = 0
            return
        }
        correction.solvedVertical = solution.vertical
        correction.solvedHorizontal = solution.horizontal
        correction.solvedRotate = solution.rotate
    }

    /// 선 찾기는 무거워 백그라운드에서 돈다. 결과를 걸기 직전에 같은 프레임·같은 방향·같은 모드인지
    /// 다시 본다 — 그 사이 사용자가 사진을 돌렸거나 다른 모드를 골랐으면 버린다.
    private func solvePerspectiveFromImage(_ frame: ScanFrame, mode: PerspectiveMode) {
        guard let developed = frame.cachedDevelopedBase else { return }
        let orientation = frame.imageTransform.orientationTemplate
        let frameID = frame.id
        Task { [weak self] in
            let solution = await Task.detached(priority: .userInitiated) {
                Self.detectAndSolve(developed, orientation: orientation, mode: mode)
            }.value
            guard let self,
                  let current = self.frames.first(where: { $0.id == frameID }),
                  current === frame,
                  current.imageTransform.orientationTemplate == orientation,
                  current.imageTransform.perspective.mode == mode else { return }
            self.updatePerspective(current) {
                $0.solvedVertical = solution?.vertical ?? 0
                $0.solvedHorizontal = solution?.horizontal ?? 0
                $0.solvedRotate = solution?.rotate ?? 0
            }
            if solution == nil {
                self.statusMessage = self.text(AppLocalizedPhrase.transformAutoNoLines)
            }
        }
    }

    nonisolated static func detectAndSolve(
        _ developed: CGImage,
        orientation: ImageTransform,
        mode: PerspectiveMode
    ) -> PerspectiveSolver.Solution? {
        guard let (luma, width, height) = orientedLuma(developed, orientation: orientation) else { return nil }
        let segments = PerspectiveLineDetector.detect(luma: luma, width: width, height: height)
        return PerspectiveSolver.solve(
            mode: mode,
            segments: segments,
            size: CGSize(width: width, height: height)
        )
    }

    /// 회전·뒤집기만 건 그림을 긴 변 `analysisLongEdge` 로 줄인 감마 밝기.
    nonisolated static func orientedLuma(
        _ developed: CGImage,
        orientation: ImageTransform
    ) -> ([Float], Int, Int)? {
        var image = ImageTransformStage.apply(to: CIImage(cgImage: developed), transform: orientation)
        let extent = image.extent
        guard extent.width >= 16, extent.height >= 16 else { return nil }
        let scale = min(1, CGFloat(PerspectiveLineDetector.analysisLongEdge) / max(extent.width, extent.height))
        if scale < 1 {
            image = image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0,
            ])
        }
        let width = Int((extent.width * scale).rounded(.down))
        let height = Int((extent.height * scale).rounded(.down))
        guard width >= 16, height >= 16,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let bounds = CGRect(x: image.extent.minX, y: image.extent.minY, width: CGFloat(width), height: CGFloat(height))
        perspectiveLumaContext.render(image, toBitmap: &rgba, rowBytes: width * 4, bounds: bounds,
                                      format: .RGBA8, colorSpace: srgb)
        var luma = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            luma[i] = (0.2126 * Float(rgba[i * 4]) + 0.7152 * Float(rgba[i * 4 + 1])
                + 0.0722 * Float(rgba[i * 4 + 2])) / 255
        }
        return (luma, width, height)
    }
}
