import Foundation
@testable import negaflowApp

/// cleaned-raw persist 디렉터리(UserDefault `disk.cleanedRawFolder`)를 per-test temp 로 격리한다.
///
/// 왜 필요한가: 인자 없는 `CleanedRawCacheFile.makeBuildURL(frameID:)` 은
/// `defaultDirectoryURL()` 을 쓰고, 그 값은 사용자 UserDefault(`disk.cleanedRawFolder`)를
/// 우선한다. 격리하지 않으면 테스트가 개발자 머신의 실제 폴더(예: iCloud Drive)에 스크래치
/// TIFF 를 쓴다. iCloud 가 파일을 플레이스홀더로 dematerialize 하면 디렉터리 목록이
/// 비결정적이 되어(릴리즈 타이밍에서 결정적 실패) 테스트가 깨지고, 매 실행이 사용자 클라우드를
/// 오염시킨다.
///
/// 사용: setUp 에서 `isolation = CleanedRawFolderIsolation()`, tearDown 에서 `isolation?.restore()`.
/// UserDefaults/FileManager 만 다루므로 액터 격리가 필요 없다(sync·async setUp 양쪽에서 쓴다).
final class CleanedRawFolderIsolation {
    private let directory: URL
    private let savedValue: String?

    init() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-cleaned-raw-isolation-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savedValue = UserDefaults.standard.string(
            forKey: CleanedRawCacheFile.customDirectoryDefaultsKey
        )
        UserDefaults.standard.set(
            directory.path,
            forKey: CleanedRawCacheFile.customDirectoryDefaultsKey
        )
    }

    /// 원래 UserDefault 값을 복원하고 격리 디렉터리를 지운다. tearDown 에서 반드시 호출한다.
    func restore() {
        if let savedValue {
            UserDefaults.standard.set(
                savedValue,
                forKey: CleanedRawCacheFile.customDirectoryDefaultsKey
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: CleanedRawCacheFile.customDirectoryDefaultsKey
            )
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
