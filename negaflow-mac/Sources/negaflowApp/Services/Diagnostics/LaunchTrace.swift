import Darwin
import Foundation

/// 앱 시작 → 첫 사진 표시 구간의 타임라인. `NEGAFLOW_LAUNCH_TRACE=1` 일 때만 표준 오류에
/// `[launch] +<프로세스 시작 이후 ms> <단계>` 를 찍는다. 꺼져 있으면 아무 일도 하지 않는다.
enum LaunchTrace {
    static let enabled = ProcessInfo.processInfo.environment["NEGAFLOW_LAUNCH_TRACE"] == "1"

    private final class Marks: @unchecked Sendable {
        let lock = NSLock()
        var once: Set<String> = []
    }
    private static let marks = Marks()

    /// 커널이 기록한 프로세스 시작 시각. 읽지 못하면 첫 기록 시각을 쓴다.
    private static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }()

    static func mark(_ label: @autoclosure () -> String) {
        guard enabled else { return }
        let elapsed = Date().timeIntervalSince(processStart) * 1000
        FileHandle.standardError.write(Data(String(format: "[launch] +%.0fms %@\n", elapsed, label()).utf8))
    }

    /// 같은 `key` 는 처음 한 번만 찍는다(첫 썸네일·첫 프리뷰 같은 자리).
    static func markOnce(_ key: String, _ detail: @autoclosure () -> String = "") {
        guard enabled else { return }
        marks.lock.lock()
        let isFirst = marks.once.insert(key).inserted
        marks.lock.unlock()
        guard isFirst else { return }
        let text = detail()
        mark(text.isEmpty ? key : "\(key) \(text)")
    }
}

/// 실제 카탈로그에서 선택→표시 시간을 잰다. RAW_TRACE를 명시한 로컬 실행에서만 기록한다.
@MainActor
enum CameraRAWSelectionTrace {
    private static let enabled = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TRACE"] == "1"
    private static var selection: (id: UUID, start: UInt64, first: Bool)?

    static func begin(_ frame: ScanFrame?) {
        guard enabled else { return }
        selection = frame.map { ($0.id, DispatchTime.now().uptimeNanoseconds, false) }
    }

    static func presented(_ frame: ScanFrame, settled: Bool) {
        guard enabled, var current = selection, current.id == frame.id,
              settled || !current.first else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - current.start) / 1e6
        let phase = settled ? "settled" : "first"
        FileHandle.standardError.write(Data(String(format: "[raw-selection] %@ %@ %.0f ms\n",
            frame.rawScanURL.lastPathComponent, phase, elapsed).utf8))
        current.first = true
        selection = settled ? nil : current
    }

    static func note(_ frame: ScanFrame, _ detail: @autoclosure () -> String) {
        guard enabled, let current = selection, current.id == frame.id else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - current.start) / 1e6
        FileHandle.standardError.write(Data(String(format: "[raw-selection-stage] %@ %.0f ms %@\n",
            frame.rawScanURL.lastPathComponent, elapsed, detail()).utf8))
    }
}
