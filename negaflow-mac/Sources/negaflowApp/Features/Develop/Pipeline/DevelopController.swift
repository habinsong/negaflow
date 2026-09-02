import AppKit
import Combine
import Foundation

@MainActor
final class DevelopController: ObservableObject {
    nonisolated static let defaultMaxConcurrentDevelopments = 3

    @Published private(set) var processingActive: Bool = false
    @Published private(set) var processingDetail: String = ""

    let maxConcurrentDevelopments: Int

    private var inFlight: Int = 0
    private var throttleLast: Date = .distantPast
    /// 이 기기에서 실제로 잰 인터랙티브 현상 1회 소요(지수 이동 평균).
    private var measuredDevelopDuration: TimeInterval?
    private var pendingThrottleTask: Task<Void, Never>?
    private var activeRequestTasks: [UUID: Task<Void, Never>] = [:]
    private var activeFrameIDs = Set<UUID>()
    private var activeDevelopSlots: Int = 0
    private var pendingDevelopSlots: [PendingDevelopSlot] = []

    /// 창이 놓인 화면의 주사율(Hz)을 돌려준다. 테스트가 이 기기에 없는 주사율까지 재보려고
    /// 갈아끼울 수 있게 열어 뒀다 — 제품 경로는 항상 실제 화면을 읽는다.
    private let displayRefreshRate: @MainActor () -> Int

    init(
        maxConcurrentDevelopments: Int = DevelopController.defaultMaxConcurrentDevelopments,
        displayRefreshRate: @escaping @MainActor () -> Int = DevelopController.currentDisplayRefreshRate
    ) {
        self.maxConcurrentDevelopments = max(1, maxConcurrentDevelopments)
        self.displayRefreshRate = displayRefreshRate
    }

    /// 화면을 못 읽으면 가장 흔한 60 Hz 로 본다.
    @MainActor
    static func currentDisplayRefreshRate() -> Int {
        NSApplication.shared.keyWindow?.screen?.maximumFramesPerSecond
            ?? NSScreen.main?.maximumFramesPerSecond
            ?? 60
    }

    /// 슬라이더 라이브 갱신 요청을 얼마나 촘촘히 받을지. 기기 성능도 화면 주사율도 제각각이라
    /// 고정값을 둘 수 없다 — 이 기기에서 실제로 잰 두 값의 절반 중 **긴 쪽**을 쓴다.
    ///
    ///   • 화면 한 프레임의 절반 — 화면이 한 장 뿌리는 사이 최소 한 번은 새 값이 예약되게 한다.
    ///   • 실측 현상 소요의 절반 — 느린 기기에서 요청만 쌓이지 않게 한다.
    ///
    /// 왜 절반인가: 요청 간격이 현상 소요보다 **짧아야** 한 장을 그리고 났을 때 다음 값이 이미
    /// 들어와 있어 루프가 쉬지 않고 다음 장으로 넘어간다. 요청 간격이 소요보다 길면 매 장마다
    /// 정착 대기로 들어갔다 깨어나느라 갱신이 반 토막 난다(실측: 요청 간격 17 ms 에서 37/s,
    /// 8 ms 에서 84/s — 현상 자체는 13 ms). 요청은 코얼레싱되므로(진행 중이면 값만 갱신) 촘촘히
    /// 받아도 현상이 겹쳐 돌지는 않는다.
    var throttleInterval: TimeInterval {
        max(displayFrameInterval, measuredDevelopDuration ?? 0) / 2
    }

    /// 정착 대기가 새 편집을 알아채는 간격. 요청 간격과 같은 근거로 화면 한 프레임의 절반이면
    /// 충분하다 — 이보다 촘촘히 봐도 화면에 더 자주 닿지 않는다.
    var editPollInterval: TimeInterval {
        displayFrameInterval / 2
    }

    /// 창이 놓인 화면의 한 프레임.
    ///
    /// 실사용 크기(2816px 프록시, 한 장 ~14 ms)에서는 현상 소요가 화면 프레임보다 길어 이 값이
    /// 지배하지 않는다 — 60·120·144·240 Hz 를 갈아끼워 재도 요청 간격 7~8 ms, 다시 잡는 첫 틱
    /// 15.0~15.3 ms 로 같았다. 이 값이 실제로 지배하는 건 작은 창처럼 현상이 화면보다 빠를 때인데,
    /// 그 경우(1024px·240 Hz, 요청 간격 2 ms)도 갱신 110/s·첫 틱 3.2 ms 로 정상이었다.
    private var displayFrameInterval: TimeInterval {
        1.0 / Double(max(displayRefreshRate(), 1))
    }

    /// 인터랙티브 현상 한 장이 끝날 때마다 호출한다. 급변에 흔들리지 않게 지수 이동 평균으로
    /// 섞되, 새 값에 충분히 따라붙도록 가중치를 크게 둔다(창 크기·사진 크기가 바뀌면 소요도 바뀐다).
    func noteInteractiveDevelopDuration(_ duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else { return }
        measuredDevelopDuration = measuredDevelopDuration.map { $0 * 0.6 + duration * 0.4 } ?? duration
    }

    func requestDevelop(
        _ frame: ScanFrame,
        perform: @escaping @MainActor (ScanFrame) async -> Void
    ) {
        let interval = throttleInterval
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
