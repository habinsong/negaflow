import Foundation

@MainActor
enum ExportBatchScheduler {
    /// 워커가 공유 커서에서 다음 항목을 하나씩 집어간다.
    ///
    /// 예전에는 워커마다 인덱스를 미리 나눠 가졌다(stride). 그러면 한 장이 오래 걸릴 때 — 원본
    /// 다운로드, 결함 raw 재빌드 — 그 워커가 맡기로 예약된 나머지 장들이 전부 뒤에서 대기했다.
    /// 다른 워커는 자기 몫을 끝내고 놀았고, 사용자에게는 "중간 어느 장에서 멈춘" 것으로 보였다.
    /// 커서를 공유하면 느린 한 장이 자기 자신만 붙잡는다.
    static func run<Element>(
        _ elements: [Element],
        maximumConcurrent: Int,
        operation: @escaping @MainActor (Element) async -> Void
    ) async {
        guard !elements.isEmpty else { return }
        let workerCount = min(max(1, maximumConcurrent), elements.count)
        let cursor = Cursor(limit: elements.count)
        let workers = (0..<workerCount).map { _ in
            Task { @MainActor in
                while let index = cursor.next() {
                    await operation(elements[index])
                }
            }
        }
        for worker in workers {
            await worker.value
        }
    }
}

/// MainActor 격리 커서. 워커가 모두 MainActor 에서 도는 동안 await 지점에서만 교대하므로
/// 별도 락 없이 다음 인덱스를 정확히 한 번씩 나눠줄 수 있다.
@MainActor
private final class Cursor {
    private var index = 0
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func next() -> Int? {
        guard index < limit else { return nil }
        defer { index += 1 }
        return index
    }
}
