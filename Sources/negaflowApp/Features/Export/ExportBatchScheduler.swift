import Foundation

@MainActor
enum ExportBatchScheduler {
    static func run<Element>(
        _ elements: [Element],
        maximumConcurrent: Int,
        operation: @escaping @MainActor (Element) async -> Void
    ) async {
        guard !elements.isEmpty else { return }
        let workerCount = min(max(1, maximumConcurrent), elements.count)
        let workers = (0..<workerCount).map { offset in
            Task { @MainActor in
                for index in stride(from: offset, to: elements.count, by: workerCount) {
                    await operation(elements[index])
                }
            }
        }
        for worker in workers {
            await worker.value
        }
    }
}
