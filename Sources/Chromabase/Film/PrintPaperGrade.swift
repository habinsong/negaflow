import CoreImage

// MARK: - PrintPaperGrade

/// PRINT의 작업공간 경계입니다.
///
/// 인화 결과는 프린터, 인화지/표면, 약품, 교정 상태를 함께 측정한 출력 ICC 없이 하나의
/// RGB 커브로 정할 수 없습니다. 따라서 엔진 안에서는 임의 감마/Dmin/Dmax를 굽지 않고
/// 완성된 MAIN 작업 이미지를 그대로 전달합니다. 실제 PRINT 변환은 검증된 `prtr` ICC가
/// 있을 때만 최종 출력 경계에서 정확히 한 번 수행합니다.
public enum PrintPaperGrade {
    public static func apply(to image: CIImage) -> CIImage {
        image
    }
}
