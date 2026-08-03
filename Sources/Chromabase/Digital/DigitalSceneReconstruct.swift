import CoreImage

// MARK: - DigitalSceneReconstruct (디지털 소스 전용)
//
// 디지털 사진은 이미 카메라가 디스플레이용으로 렌더한 결과다. 명부는 숄더로 눌려 1 근처에
// 몰려 있고, 그 상태에 필름 곡선을 다시 얹으면 계조가 남지 않는다(측정: 카메라 렌더 입력에서
// 명부 스텝 간격이 0.0031 까지 붕괴 — 플랫 입력의 0.044 대비 1/14).
//
// 이 스테이지는 그 숄더를 역으로 풀어 **필름이 받는 노출**을 추정한다. 중간 회색은 그대로
// 두고 명부만 펴므로, 뒤따르는 필름 특성곡선이 자기 숄더를 쓸 헤드룸이 생긴다.
//
// 한계를 분명히 해 둔다: 클리핑으로 사라진 정보는 돌아오지 않는다. 이것은 복원이 아니라
// 그럴듯한 재구성이며, 전역 단조 곡선만 쓰는 이유도 국소 재구성이 만드는 아티팩트를 피하기
// 위해서다.
public enum DigitalSceneReconstruct {

    /// 중간 회색 앵커. 이 값은 입출력에서 동일하게 유지된다.
    static let midGray = 0.18
    /// 명부 확장 상한(배).
    ///
    /// 크게 잡으면 디스플레이 흰색이 중간 회색 위 6 스톱대로 날아가는데, 실제 장면의 흰
    /// 표면은 그보다 훨씬 가깝다. 그 상태로 필름 곡선에 넣으면 흰색이 곡선 끝에 눌려
    /// 회색으로 내려앉는다(측정: 입력 0.98 이 출력 0.61). 카메라가 실제로 압축한 만큼만
    /// 되돌린다.
    static let maxGain = 3.5

    public static func apply(to image: CIImage) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalSceneReconstruct") else {
            return image
        }
        let extent = image.extent
        let p = parameters
        return kernel.apply(
            extent: extent,
            arguments: [image, CIVector(x: p.a, y: p.dmin, z: p.scale, w: 0)]
        )?.cropped(to: extent) ?? image
    }

    /// 커널 계수. `scale` 은 중간 회색이 정확히 자기 자신으로 돌아오도록 맞추는 정규화다.
    static var parameters: (a: CGFloat, dmin: CGFloat, scale: CGFloat) {
        let a = 1.0 - midGray
        let dmin = a / maxGain
        let om = a                              // 중간 회색에서의 (1 - v)
        let denom = 0.5 * (om + (om * om + 4 * dmin * dmin).squareRoot())
        return (CGFloat(a), CGFloat(dmin), CGFloat(denom / a))
    }

    /// 디스플레이 흰색(1.0)이 재구성 뒤 중간 회색보다 몇 스톱 위에 놓이는지. 가상 현상이
    /// 장면 범위를 유제 관용도에 맞출 때 기준으로 쓴다.
    static var displayWhiteStops: Double {
        log2(expose(1.0) / midGray)
    }

    /// 커널과 같은 곡선의 CPU 구현. 테스트가 GPU 결과를 대조하는 기준으로 쓴다.
    static func expose(_ v: Double) -> Double {
        let p = parameters
        let om = 1.0 - v
        let dmin = Double(p.dmin)
        let denom = 0.5 * (om + (om * om + 4 * dmin * dmin).squareRoot())
        return Double(p.a) * v / denom * Double(p.scale)
    }
}
