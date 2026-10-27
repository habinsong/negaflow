import CoreImage

// MARK: - BoundedChromaScale
//
// 채도(Saturation)와 색 깊이(Color Depth) 슬라이더가 함께 쓰는 크로마 배율이다.
// 계산은 `chromaScaleBounded` 커널(ChromabaseMetalKernels+ToneSources)이 한다.
//
// 이전에는 CIColorControls 의 채도(선형광에서 휘도 앵커 균일 배율)를 그대로 썼다. 식 자체는
// 같지만 키우는 쪽에 끝 보호가 없어서, 채도가 높은 화소(노을 주황·짙은 초록처럼 채널 하나가
// 0 에 가까운 색)는 +0.3 정도에서도 그 채널이 음수로 나가 뒤 단계에서 채널별로 잘렸다.
// 합성 격자 216색 실측(2026-10-27): 채도 +1 에서 180 색이 범위를 벗어나고 감마 HSV 색조가
// 최대 29.7° 돌았다.
//
// 지금은 [0,1] 안에 머무는 결과를 이전과 같게 두고, 한 채널이 경계에 닿는 배율을 넘는 부분만
// 지수 숄더로 접는다. 휘도·알파는 보존하고, 이미 범위 밖인 화소는 더 키우지 않는다.
// "같다"는 비트 단위가 아니다: CIColorControls 는 휘도 가중치가 Rec.709(0.2126/0.7152/0.0722)와
// 소수 넷째 자리에서 달라, 선형값 기준 최대 1.14e-4 의 차이가 있다(216색 격자 실측). 새 커널은
// Rec.709 를 그대로 써서 Windows `apply_saturation` 과 식이 일치한다.
enum BoundedChromaScale {
    /// 경계까지 남은 배율 여유(limit − 1) 중 선형으로 두는 비율. 이보다 안쪽 배율은 이전
    /// 결과와 같고, 바깥은 limit 에 점근한다. 커널·Windows `bounded_chroma_scale` 이 같은
    /// 값을 쓴다 — 한쪽만 바꾸면 두 앱의 결과가 갈라진다.
    ///
    /// 이 값은 측정으로 최적화한 것이 아니라 설계 선택이다. 크면 이전 결과를 더 넓게 유지하고
    /// 작으면 접힘이 일찍 시작한다. 합성 색 계산 예: 피부색 (0.55, 0.28, 0.20) 의 limit 는 약
    /// 2.5, 연한 하늘 (0.35, 0.50, 0.75) 는 약 1.9 라서 채도 +1(×1.6)에서도 접히지 않고, 노을
    /// 주황 (0.80, 0.25, 0.05) 는 약 1.17 이라 채도 +0.2 부터 접힌다. 실사진으로는 확인하지
    /// 않았다.
    static let kneeFraction: Float = 0.75

    static func apply(to image: CIImage, factor: Double) -> CIImage {
        guard factor.isFinite else { return image }
        if let kernel = ChromabaseMetalKernels.colorKernel(named: "chromaScaleBounded"),
           let output = kernel.apply(
               extent: image.extent,
               arguments: [image, Float(factor), kneeFraction]
           ) {
            return output.cropped(to: image.extent)
        }
        // 커널을 만들지 못한 경우에도 슬라이더가 멈추지 않게 이전 방식으로 둔다(끝 보호만 없다).
        return image.applyingFilter("CIColorControls", parameters: [
            "inputSaturation": NSNumber(value: factor),
            "inputContrast": 1.0,
            "inputBrightness": 0.0,
        ])
    }
}
