import Combine
import Foundation

/// 앱 전역 상태 메시지의 전용 발행 경계(관찰 경계 축소 1단계).
///
/// statusMessage 는 150여 곳에서 대입되는 최고 빈도 발행원이지만 읽는 곳은 상태바와 스캔
/// 오버레이뿐이다. AppModel 의 @Published 로 두면 메시지 한 줄마다 AppModel 을 관찰하는
/// 모든 뷰(100+ 파일)가 무효화된다 — 전용 ObservableObject 로 떼어 읽는 뷰만 다시 그린다.
/// 대입 지점은 AppModel.statusMessage facade 가 그대로 흡수한다.
@MainActor
final class StatusMessageCenter: ObservableObject {
    @Published var message = AppLocalization.text(
        AppLocalizedPhrase.idleStatus,
        language: .system
    )
}
