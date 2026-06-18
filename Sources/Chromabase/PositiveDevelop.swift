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

        let baseScale = 1.08
        let baseBias = -0.03
        img = img.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: baseScale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: baseScale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: baseScale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: baseBias, y: baseBias, z: baseBias, w: 0),
        ])

        // (a) 흑점 회복: 딥 블랙을 위해 살짝 어둡게 시작.
        // 스캐너 양화는 종종 블랙이 0.02~0.04 정도에 걸쳐 평탄하다.
        img = img.applyingFilter("CIColorControls", parameters: [
            "inputBrightness": NSNumber(value: 0.0),
            "inputContrast":   NSNumber(value: 1.10),   // 미드톤 대비 = 밀도 회복
            "inputSaturation": NSNumber(value: 1.0),
        ])

        // (b) 하이라이트 roll-off: 슬라이드 하이라이트 보호.
        // 감마를 살짝 올려 라이트 쪽을 압축.
        img = img.applyingFilter("CIGammaAdjust", parameters: [
            "inputPower": NSNumber(value: 1.0),
        ])

        // (c) B&W 포지티브면 채도 제거.
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
