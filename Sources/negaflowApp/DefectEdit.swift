import Foundation
import CoreGraphics

// 결함 제거 편집 한 단위. 브러시 ICE(스트로크 그룹)와 반자동 Region ICE(렌더된 마스크)를 하나의
// 순서 있는 히스토리(defectEdits)로 통합한다 — cleaned raw = 원본 raw + defectEdits 순차 적용.
//
// 이 통합이 핵심: 과거에는 브러시가 "원본 raw + strokes"로 cleaned raw를 재계산하고 반자동은
// 현재 cleaned raw에 직접 덮어써서, 한쪽을 rebuild(⌘Z/clear/증분 불가)하면 다른 쪽 결과가
// 사라졌다. 이제 두 편집이 같은 리스트에 순서대로 쌓이고 재빌드 시 전부 재적용되므로 서로
// 되살아나지 않는다.
//
// 메모리: region 은 무거운 ICELabelField(라벨맵 + 컴포넌트 픽셀) 대신 렌더된 마스크(Data)만
// 보관한다 — 편집을 픽셀 레이어로 구체화하지 않는 경량 command 객체(편집 스택의 정석).
enum DefectEdit {
    /// 브러시 스트로크 그룹(변형 전 raw 정규좌표).
    case brush([DefectStroke])
    /// 반자동 Region ICE 결과: 렌더된 결함 마스크(RGBA8, 흰색=제거) + raw(y-up) 픽셀 ROI.
    case region(mask: Data, roi: CGRect, width: Int, height: Int)
}
