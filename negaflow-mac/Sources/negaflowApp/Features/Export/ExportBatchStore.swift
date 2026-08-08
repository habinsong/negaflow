import Foundation

@MainActor
final class ExportBatchStore: ObservableObject {
    enum State: Equatable {
        case queued
        case running
        case succeeded
        case failed(String)
        case cancelled
    }

    struct Item: Identifiable, Equatable {
        let id: UUID
        let frameID: UUID
        let displayName: String
        var outputURL: URL
        var state: State
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var isCancellationRequested = false
    private var permissionContinuations: [CheckedContinuation<Bool, Never>] = []

    var completedCount: Int {
        items.count { item in
            if case .succeeded = item.state { return true }
            return false
        }
    }

    var failedCount: Int {
        items.count { item in
            if case .failed = item.state { return true }
            return false
        }
    }

    var cancelledCount: Int {
        items.count { item in
            if case .cancelled = item.state { return true }
            return false
        }
    }

    var finishedCount: Int { completedCount + failedCount + cancelledCount }

    var retryableItemIDs: Set<UUID> {
        Set(items.compactMap { item in
            switch item.state {
            case .failed, .cancelled: item.id
            default: nil
            }
        })
    }

    func begin(_ plans: [ExportBatchPlan]) {
        items = makeItems(plans) { _ in .queued }
        isRunning = !items.isEmpty
        isPaused = false
        isCancellationRequested = false
    }

    func restore(_ plans: [ExportBatchPlan], states: [UUID: State]) {
        items = makeItems(plans) { states[$0.id] ?? .cancelled }
        isRunning = false
        isPaused = false
        isCancellationRequested = false
    }

    func state(for id: UUID) -> State? {
        items.first(where: { $0.id == id })?.state
    }

    func markRunning(_ id: UUID) {
        update(id) { $0.state = .running }
    }

    func markFinished(_ id: UUID, result: ExportFrameTransactionResult) {
        update(id) { item in
            switch result {
            case .completed:
                item.state = .succeeded
            case .failed(let message):
                item.state = .failed(message)
            }
        }
    }

    func finish() {
        isRunning = false
        isPaused = false
        permissionContinuations.forEach { $0.resume(returning: false) }
        permissionContinuations.removeAll()
    }

    func requestPause() {
        guard isRunning, !isCancellationRequested else { return }
        isPaused = true
    }

    func resume() {
        guard isRunning, isPaused, !isCancellationRequested else { return }
        isPaused = false
        permissionContinuations.forEach { $0.resume(returning: true) }
        permissionContinuations.removeAll()
    }

    func requestCancellation() {
        guard isRunning else { return }
        isCancellationRequested = true
        isPaused = false
        for index in items.indices {
            if case .queued = items[index].state {
                items[index].state = .cancelled
            }
        }
        permissionContinuations.forEach { $0.resume(returning: false) }
        permissionContinuations.removeAll()
    }

    func prepareRetry(_ ids: Set<UUID>) {
        guard !isRunning, !ids.isEmpty else { return }
        for index in items.indices where ids.contains(items[index].id) {
            items[index].state = .queued
        }
        isRunning = true
        isPaused = false
        isCancellationRequested = false
    }

    func prepareRetry(_ plans: [ExportBatchPlan]) {
        let outputURLs = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0.outputURL) })
        prepareRetry(Set(outputURLs.keys))
        for index in items.indices {
            if let outputURL = outputURLs[items[index].id] {
                items[index].outputURL = outputURL
            }
        }
    }

    func awaitSchedulingPermission() async -> Bool {
        if isCancellationRequested { return false }
        if !isPaused { return true }
        return await withCheckedContinuation { continuation in
            permissionContinuations.append(continuation)
        }
    }

    private func update(_ id: UUID, mutation: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutation(&items[index])
    }

    private func makeItems(
        _ plans: [ExportBatchPlan],
        state: (ExportBatchPlan) -> State
    ) -> [Item] {
        plans.map {
            Item(
                id: $0.id,
                frameID: $0.frame.id,
                displayName: $0.frame.editableDisplayName,
                outputURL: $0.outputURL,
                state: state($0)
            )
        }
    }
}
