import Combine
import Foundation

@MainActor
final class DevelopController: ObservableObject {
    static let throttleInterval: TimeInterval = 0.045
    nonisolated static let defaultMaxConcurrentDevelopments = 3

    @Published private(set) var processingActive: Bool = false
    @Published private(set) var processingDetail: String = ""

    let maxConcurrentDevelopments: Int

    private var inFlight: Int = 0
    private var throttleLast: Date = .distantPast
    private var pendingThrottleTask: Task<Void, Never>?
    private var activeRequestTasks: [UUID: Task<Void, Never>] = [:]
    private var activeFrameIDs = Set<UUID>()
    private var activeDevelopSlots: Int = 0
    private var pendingDevelopSlots: [PendingDevelopSlot] = []

    init(maxConcurrentDevelopments: Int = DevelopController.defaultMaxConcurrentDevelopments) {
        self.maxConcurrentDevelopments = max(1, maxConcurrentDevelopments)
    }

    func requestDevelop(
        _ frame: ScanFrame,
        perform: @escaping @MainActor (ScanFrame) async -> Void
    ) {
        let interval = Self.throttleInterval
        let now = Date()
        let elapsed = now.timeIntervalSince(throttleLast)
        pendingThrottleTask?.cancel()
        pendingThrottleTask = nil
        if elapsed >= interval {
            throttleLast = now
            startDevelopRequest(frame, perform: perform)
        } else {
            let wait = interval - elapsed
            pendingThrottleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.pendingThrottleTask = nil
                self.throttleLast = Date()
                self.startDevelopRequest(frame, perform: perform)
            }
        }
    }

    func cancelPendingDevelopRequest() {
        pendingThrottleTask?.cancel()
        pendingThrottleTask = nil
        let activeTasks = Array(activeRequestTasks.values)
        activeRequestTasks.removeAll()
        for task in activeTasks {
            task.cancel()
        }
    }

    private func startDevelopRequest(
        _ frame: ScanFrame,
        perform: @escaping @MainActor (ScanFrame) async -> Void
    ) {
        let requestID = UUID()
        let task = Task { [weak self] in
            await perform(frame)
            self?.activeRequestTasks.removeValue(forKey: requestID)
        }
        activeRequestTasks[requestID] = task
    }

    func beginFrame(_ frame: ScanFrame) -> Bool {
        activeFrameIDs.insert(frame.id).inserted
    }

    func endFrame(_ frame: ScanFrame) {
        activeFrameIDs.remove(frame.id)
    }

    func isDevelopingFrame(_ frame: ScanFrame) -> Bool {
        activeFrameIDs.contains(frame.id)
    }

    func acquireDevelopSlot() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard activeDevelopSlots >= maxConcurrentDevelopments else {
            activeDevelopSlots += 1
            return true
        }

        let id = UUID()
        let state = PendingDevelopSlotState()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingDevelopSlots.append(PendingDevelopSlot(id: id, continuation: continuation, state: state))
            }
        } onCancel: {
            state.cancel()
            Task { @MainActor [weak self] in
                self?.cancelPendingDevelopSlot(id)
            }
        }
    }

    func releaseDevelopSlot() {
        while !pendingDevelopSlots.isEmpty {
            let pending = pendingDevelopSlots.removeFirst()
            if pending.resume() {
                return
            }
        }
        activeDevelopSlots = max(0, activeDevelopSlots - 1)
    }

    private func cancelPendingDevelopSlot(_ id: UUID) {
        guard let index = pendingDevelopSlots.firstIndex(where: { $0.id == id }) else { return }
        let pending = pendingDevelopSlots.remove(at: index)
        pending.resumeCanceled()
    }

    func developBegan() {
        inFlight += 1
        processingActive = true
    }

    func developEnded() {
        inFlight = max(0, inFlight - 1)
        if inFlight == 0 {
            processingActive = false
            processingDetail = ""
        }
    }

    func updateProcessingDetail(
        interactive: Bool,
        proxyPixels: Int,
        isScanning: Bool,
        language: AppLanguage = .system
    ) {
        guard !isScanning else { return }
        if inFlight > 1 {
            processingDetail = AppLocalization.format(AppLocalizedPhrase.developingFramesFormat, language: language, inFlight)
        } else {
            processingDetail = interactive
                ? AppLocalization.format(AppLocalizedPhrase.generatingPreviewFormat, language: language, proxyPixels)
                : AppLocalization.format(AppLocalizedPhrase.generatingSettledPreviewFormat, language: language, proxyPixels)
        }
    }
}

private struct PendingDevelopSlot {
    let id: UUID
    let continuation: CheckedContinuation<Bool, Never>
    let state: PendingDevelopSlotState

    func resume() -> Bool {
        guard let shouldAcquire = state.takeResumeValue() else { return false }
        continuation.resume(returning: shouldAcquire)
        return shouldAcquire
    }

    func resumeCanceled() {
        state.cancel()
        guard let shouldAcquire = state.takeResumeValue() else { return }
        continuation.resume(returning: shouldAcquire)
    }
}

private final class PendingDevelopSlotState: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false
    private var resumed = false

    func cancel() {
        lock.lock()
        canceled = true
        lock.unlock()
    }

    func takeResumeValue() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return nil }
        resumed = true
        return !canceled
    }
}
