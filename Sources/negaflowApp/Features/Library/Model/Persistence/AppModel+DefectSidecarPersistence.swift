import AppKit
import Combine
import CoreImage
import Foundation
import Chromabase
import ScannerKit

extension AppModel {
    // 결함 기록(sidecar)은 더 이상 디스크에 저장하지 않는다 — 종료 시 cleaned raw가
    // 이미지에 구워지고 기록은 세션과 함께 사라진다.

    // MARK: 저장(디바운스)

    /// 프레임 목록 변경(추가/삭제/복원) 시: 프레임별 변경 관찰을 재구독하고 저장을 예약한다.

}
