import Darwin
import Foundation

enum LibraryCatalogBenchmarkSupport {
    struct Outcome: Equatable {
        let frameCount: Int
        let rollFrameCount: Int
        let firstFrameID: UUID?
        let lastFrameID: UUID?
        let payloadBytes: Int
    }

    struct Report: Encodable {
        let schemaVersion: Int
        let catalogVersion: Int
        let storageKind: String
        let configuration: String
        let timingGateApplied: Bool
        let environment: EnvironmentReport
        let cases: [CaseReport]
    }

    struct CaseReport: Encodable {
        let scenario: String
        let frameCount: Int
        let payloadBytes: Int
        let bytesPerFrame: Double
        let warmupIterations: Int
        let measurementIterations: Int
        let durationMilliseconds: DurationReport
        let memory: MemoryReport
    }

    struct DurationReport: Encodable {
        let samples: [Double]
        let min: Double
        let p50: Double
        let p95: Double
        let max: Double
    }

    struct MemoryReport: Encodable {
        let residentBeforeBytes: Int64
        let residentAfterBytes: Int64
        let retainedDeltaBytes: Int64
        let maxRSSBeforeBytes: Int64
        let maxRSSAfterBytes: Int64
        let maxRSSGrowthBytes: Int64
    }

    struct EnvironmentReport: Encodable {
        let osVersion: String
        let architecture: String
        let hardwareModel: String
        let activeProcessorCount: Int
        let physicalMemoryBytes: UInt64
    }

    enum BenchmarkError: Error {
        case invalidDuration(String)
        case nondeterministicResult(String)
    }

    static func measure(
        scenario: String,
        frameCount: Int,
        warmupIterations: Int = 1,
        measurementIterations: Int,
        prepare: () throws -> Void = {},
        operation: () throws -> Outcome
    ) throws -> CaseReport {
        var expected: Outcome?
        for _ in 0..<warmupIterations {
            try prepare()
            try verify(try operation(), expected: &expected, scenario: scenario)
        }

        let memoryBefore = memorySnapshot()
        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<measurementIterations {
            try prepare()
            let started = clock.now
            let outcome = try operation()
            let duration = started.duration(to: clock.now)
            let milliseconds = milliseconds(duration)
            guard milliseconds.isFinite, milliseconds >= 0 else {
                throw BenchmarkError.invalidDuration(scenario)
            }
            samples.append(milliseconds)
            try verify(outcome, expected: &expected, scenario: scenario)
        }
        let memoryAfter = memorySnapshot()
        let outcome = expected ?? Outcome(
            frameCount: frameCount,
            rollFrameCount: 0,
            firstFrameID: nil,
            lastFrameID: nil,
            payloadBytes: 0
        )
        let sorted = samples.sorted()

        return CaseReport(
            scenario: scenario,
            frameCount: frameCount,
            payloadBytes: outcome.payloadBytes,
            bytesPerFrame: frameCount > 0
                ? Double(outcome.payloadBytes) / Double(frameCount)
                : 0,
            warmupIterations: warmupIterations,
            measurementIterations: measurementIterations,
            durationMilliseconds: DurationReport(
                samples: samples,
                min: sorted.first ?? 0,
                p50: percentile(sorted, fraction: 0.50),
                p95: percentile(sorted, fraction: 0.95),
                max: sorted.last ?? 0
            ),
            memory: MemoryReport(
                residentBeforeBytes: memoryBefore.residentBytes,
                residentAfterBytes: memoryAfter.residentBytes,
                retainedDeltaBytes: memoryAfter.residentBytes - memoryBefore.residentBytes,
                maxRSSBeforeBytes: memoryBefore.maxRSSBytes,
                maxRSSAfterBytes: memoryAfter.maxRSSBytes,
                maxRSSGrowthBytes: memoryAfter.maxRSSBytes - memoryBefore.maxRSSBytes
            )
        )
    }

    static func environmentReport() -> EnvironmentReport {
        EnvironmentReport(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: sysctlString("hw.machine") ?? "unknown",
            hardwareModel: sysctlString("hw.model") ?? "unknown",
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    static func write(_ report: Report, to path: String?) throws {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    private struct MemorySnapshot {
        let residentBytes: Int64
        let maxRSSBytes: Int64
    }

    private static func verify(
        _ outcome: Outcome,
        expected: inout Outcome?,
        scenario: String
    ) throws {
        if let expected, expected != outcome {
            throw BenchmarkError.nondeterministicResult(scenario)
        }
        expected = outcome
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func percentile(_ sorted: [Double], fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = max(1, Int(ceil(fraction * Double(sorted.count))))
        return sorted[min(rank - 1, sorted.count - 1)]
    }

    private static func memorySnapshot() -> MemorySnapshot {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return MemorySnapshot(
            residentBytes: status == KERN_SUCCESS ? Int64(info.resident_size) : 0,
            maxRSSBytes: Int64(usage.ru_maxrss)
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}
