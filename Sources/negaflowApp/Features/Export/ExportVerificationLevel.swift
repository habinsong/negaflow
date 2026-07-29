import Foundation

/// 내보내기 happy path 에서 같은 파일을 몇 번 다시 확인할지 정하는 수준.
///
/// 두 수준 모두 저널에 남는 `Artifact.identity` 는 **항상 실제 SHA-256** 이다. 즉 크래시 복구
/// (`reconcile`)와 롤백 판정의 보증은 수준과 무관하게 동일하다. 달라지는 건 한 번의 성공적인
/// 내보내기 안에서 "방금 확인한 파일을 또 확인"하는 중복 패스뿐이다.
///
/// - standard: 최초 1회 해시로 세대를 고정하고, 이후 재확인은 stat identity(dev/inode/size/
///   mtime/ctime)로 한다. stat 이 하나라도 달라지면 그 자리에서 실제 해시로 되돌아가 판정하므로
///   "바뀌지 않았는데 실패" 하는 경우가 없다.
/// - strict: 모든 확인 지점에서 전체 바이트를 다시 해시한다(1.0.2 까지의 동작).
enum ExportVerificationLevel: String, Codable, CaseIterable, Sendable {
    case standard
    case strict

    static let `default` = ExportVerificationLevel.standard

    /// 재확인 지점에서 전체 바이트 해시를 다시 계산할지 여부.
    var rehashesOnRecheck: Bool { self == .strict }
}
