import XCTest

/// 공용 비동기 폴링 헬퍼: 데드라인까지 조건을 폴링하고, 초과하면 XCTFail.
/// 각 테스트 파일에 사본으로 존재하던 waitUntil/waitForCondition 을 대체한다.
@MainActor
func waitUntil(
    _ description: String,
    timeout: TimeInterval = 5,
    pollIntervalNanoseconds: UInt64 = 20_000_000,
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(timeout))
    while !condition() {
        guard clock.now < deadline else {
            XCTFail("시간 초과: \(description)", file: file, line: line)
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}
