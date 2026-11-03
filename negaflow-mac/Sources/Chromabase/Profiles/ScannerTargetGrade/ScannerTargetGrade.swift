import Foundation
import CoreImage
import simd

// MARK: - ScannerTargetGrade (SP / HS / F135 / HR 스캐너 타깃)
//
// 세 단계다(장치 정확 복제를 주장하지 않는다 — 근거와 한계는 +Targets.swift):
//   1. 렌더링(+Rendering.swift): 장면과 무관한 고정 변환. 휘도 톤 곡선, 밝기별 채도 게인,
//      회색축 오프셋. 프레임별 노출·색 맞춤은 반전과 우측 패널의 자동 기능 몫이다.
//   2. 실측 상대 차분(+Signature.swift): 사용자가 SP/HS 필름 프로파일을 직접 골랐을 때만, 두
//      스캐너의 같은 roll-label set 에서 분리한 상대 스타일을 3D LUT 로 얹는다.
//   3. 장치 질감(+Texture.swift): HS 의 끌 수 없는 기본 샤픈. 반경은 실기 출력 해상도 기준이다.
public enum ScannerTargetGrade {}
