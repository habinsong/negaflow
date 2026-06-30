import Foundation
import CoreImage

// MARK: - PositiveDevelop (포지티브 / 슬라이드)
//
// 포지티브(슬라이드, B&W 양화)는 이미 올바른 양극성 상태이므로 반전이 필요 없다.
// 대신 스캐너가 잡은 양화는 보통 약간 평탄하고, 슬라이드 특유의
// "높은 밀도 + 선명한 컬러 + 딥 블랙 + 보호된 하이라이트"를 복원하는 베이스 그레이딩이 필요하다.
//
// 여기서는 사용자 Look/슬라이더가 얹히기 전의 **기본 베이스**만 만든다:
//   • 살짝 플랫한 스캐너 입력에 미드톤 대비(밀도) 회복
//   • 하이라이트 클리핑 보호(roll-off)
//   • 흑점을 살짝 내려 딥 블랙
//   • (B&W 포지티브는 채도를 0으로)
public enum PositiveDevelop {
    public static func applyBaseGrade(to image: CIImage, filmType: FilmType) -> CIImage {
        // 입력 extent를 미리 캡처 — 필터 체인이 무한 extent로 확장되는 것을 막는다.
        let extent = image.extent
        var img = image

        // 미드톤 대비(밀도)는 아주 약하게만. 과거 contrast 1.10 + bias -0.03은 피벗 아래
        // (암부)를 강하게 눌러 "어두운 곳은 전부 검정"으로 뭉갰다. Raw에선 보이던 암부가
        // Developed에서 사라지던 원인. 대비를 낮추고 음수 bias를 제거한다.
        img = img.applyingFilter("CIColorControls", parameters: [
            "inputBrightness": NSNumber(value: 0.0),
            "inputContrast":   NSNumber(value: 1.04),
            "inputSaturation": NSNumber(value: 1.0),
        ])

        // 톤 커브: 암부 계조를 살리고(0 근처를 0으로 뭉개지 않음) 하이라이트는 숄더로
        // 1.0 직전에서 굴려 클리핑을 막는다. 슬라이드의 딥 블랙은 유지하되 디테일을 남긴다.
        img = img.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0.00, y: 0.010),
            "inputPoint1": CIVector(x: 0.22, y: 0.205),
            "inputPoint2": CIVector(x: 0.50, y: 0.510),
            "inputPoint3": CIVector(x: 0.80, y: 0.815),
            "inputPoint4": CIVector(x: 1.00, y: 0.965),
        ])

        // B&W 포지티브면 채도 제거.
        if filmType == .bwPositive {
            img = img.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": NSNumber(value: 0.0),
                "inputContrast":   NSNumber(value: 1.0),
                "inputBrightness": NSNumber(value: 0.0),
            ])
        }

        // 입력 영역으로 명시적으로 crop — 유한 extent 보장.
        return img.cropped(to: extent)
    }
}
