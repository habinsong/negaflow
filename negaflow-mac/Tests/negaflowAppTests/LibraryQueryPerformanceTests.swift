import Darwin
import Foundation
import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class LibraryQueryPerformanceTests: XCTestCase {
    private static let frameCounts = [1_000, 10_000, 50_000]
    private static let warmupIterations = 3
    private static let measurementIterations = 20

    func testDeterministicLibraryQueryPerformanceWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_LIBRARY_QUERY_PERF"] == "1" else {
            throw XCTSkip(
                "Set NEGAFLOW_LIBRARY_QUERY_PERF=1 to run the deterministic LibraryQuery benchmark."
            )
        }

        let allFacts = Self.makeFacts(count: try XCTUnwrap(Self.frameCounts.max()))
        var reports: [BenchmarkCaseReport] = []
        for frameCount in Self.frameCounts {
            let facts = Array(allFacts.prefix(frameCount))
            let sourceIDs = facts.map(\.id)
            let folderFacts = Self.makeFolderFacts(from: facts)
            let sourceChecksum = Self.checksum(sourceIDs)

            reports.append(try Self.measure(
                scenario: "context-index-build",
                frameCount: frameCount,
                sourceChecksum: sourceChecksum,
                operation: {
                    LibraryQueryContext(
                        generation: 1,
                        facts: facts,
                        activeRollID: facts.first?.rollID,
                        folderFacts: folderFacts
                    )
                },
                summarize: { context in
                    Self.contextOutcome(context, sourceIDs: sourceIDs)
                }
            ))

            let context = LibraryQueryContext(
                generation: 1,
                facts: facts,
                activeRollID: facts.first?.rollID,
                folderFacts: folderFacts
            )
            let interactiveQueries = ["n", "ni", "nig", "night"].map { text in
                LibraryQuery(conditions: [
                    .text(.init(field: .anySearchable, rule: .containsAll, value: text)),
                    .rating(comparison: .greaterThanOrEqual, value: 2),
                    .pickState(isAnyOf: [.picked, .unflagged]),
                    .sourceAvailability(isAnyOf: [.online]),
                ])
            }
            let interactiveBaseQuery = LibraryQuery(conditions: [
                .rating(comparison: .greaterThanOrEqual, value: 2),
                .pickState(isAnyOf: [.picked, .unflagged]),
                .sourceAvailability(isAnyOf: [.online]),
            ])
            let interactiveBaseProjection = LibraryBrowserProjection.make(
                sourceFrameIDs: sourceIDs,
                query: interactiveBaseQuery,
                context: context,
                sort: .init(key: .inputOrder, ascending: true)
            )
            reports.append(try Self.measure(
                scenario: "interactive-filter-input-order",
                frameCount: frameCount,
                sourceChecksum: sourceChecksum,
                operation: {
                    interactiveQueries.map { query in
                        LibraryBrowserProjection.make(
                            sourceFrameIDs: sourceIDs,
                            query: query,
                            context: context,
                            sort: .init(key: .inputOrder, ascending: true)
                        )
                    }
                },
                summarize: Self.projectionBatchOutcome
            ))
            reports.append(try Self.measure(
                scenario: "interactive-refinement-cache-input-order",
                frameCount: frameCount,
                sourceChecksum: sourceChecksum,
                operation: {
                    var cache = LibraryBrowserProjectionCache(
                        generation: context.generation,
                        sourceFrameIDs: sourceIDs,
                        query: interactiveBaseQuery,
                        sort: .init(key: .inputOrder, ascending: true),
                        projection: interactiveBaseProjection
                    )
                    return interactiveQueries.map { query in
                        let projection = cache.reusedProjection(
                            sourceFrameIDs: sourceIDs,
                            query: query,
                            context: context,
                            sort: .init(key: .inputOrder, ascending: true)
                        ) ?? LibraryBrowserProjection.make(
                            sourceFrameIDs: sourceIDs,
                            query: query,
                            context: context,
                            sort: .init(key: .inputOrder, ascending: true)
                        )
                        cache = LibraryBrowserProjectionCache(
                            generation: context.generation,
                            sourceFrameIDs: sourceIDs,
                            query: query,
                            sort: .init(key: .inputOrder, ascending: true),
                            projection: projection
                        )
                        return projection
                    }
                },
                summarize: Self.projectionBatchOutcome
            ))

            let filteredQuery = LibraryQuery(conditions: [
                .text(.init(
                    field: .anySearchable,
                    rule: .containsAll,
                    value: "night archive"
                )),
                .rating(comparison: .greaterThanOrEqual, value: 3),
                .sourceAvailability(isAnyOf: [.online]),
            ])
            reports.append(try Self.measure(
                scenario: "filtered-name-sort",
                frameCount: frameCount,
                sourceChecksum: sourceChecksum,
                operation: {
                    LibraryBrowserProjection.make(
                        sourceFrameIDs: sourceIDs,
                        query: filteredQuery,
                        context: context,
                        sort: .init(key: .name, ascending: true)
                    )
                },
                summarize: { Self.projectionBatchOutcome([$0]) }
            ))

            reports.append(try Self.measure(
                scenario: "match-all-name-sort",
                frameCount: frameCount,
                sourceChecksum: sourceChecksum,
                operation: {
                    LibraryBrowserProjection.make(
                        sourceFrameIDs: sourceIDs,
                        query: LibraryQuery(),
                        context: context,
                        sort: .init(key: .name, ascending: true)
                    )
                },
                summarize: { Self.projectionBatchOutcome([$0]) }
            ))
        }

        XCTAssertEqual(reports.count, Self.frameCounts.count * 5)
        XCTAssertTrue(reports.allSatisfy { $0.durationMilliseconds.samples.count == 20 })
        XCTAssertTrue(reports.allSatisfy { $0.resultChecksum != "0000000000000000" })
        try Self.writeReportIfRequested(BenchmarkReport(
            schemaVersion: 1,
            generatorVersion: 1,
            queryVersion: LibraryQuery.currentVersion,
            configuration: Self.buildConfiguration,
            timingGateApplied: false,
            warmupIterations: Self.warmupIterations,
            measurementIterations: Self.measurementIterations,
            environment: Self.environmentReport(),
            cases: reports.sorted {
                ($0.frameCount, $0.scenario) < ($1.frameCount, $1.scenario)
            }
        ))
    }

    private static func measure<Result>(
        scenario: String,
        frameCount: Int,
        sourceChecksum: String,
        operation: () -> Result,
        summarize: (Result) -> BenchmarkOutcome
    ) throws -> BenchmarkCaseReport {
        var expected: BenchmarkOutcome?
        for _ in 0..<warmupIterations {
            let outcome = summarize(operation())
            try verifyDeterminism(outcome, expected: &expected, scenario: scenario)
        }

        let memoryBefore = memorySnapshot()
        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<measurementIterations {
            let started = clock.now
            let result = operation()
            let elapsed = started.duration(to: clock.now)
            let milliseconds = Self.milliseconds(elapsed)
            guard milliseconds.isFinite, milliseconds >= 0 else {
                throw BenchmarkError.invalidDuration(scenario)
            }
            samples.append(milliseconds)
            let outcome = summarize(result)
            try verifyDeterminism(outcome, expected: &expected, scenario: scenario)
        }
        let memoryAfter = memorySnapshot()
        let outcome = try XCTUnwrap(expected)
        let sortedSamples = samples.sorted()

        return BenchmarkCaseReport(
            scenario: scenario,
            frameCount: frameCount,
            matchedCount: outcome.matchedCount,
            sourceChecksum: sourceChecksum,
            resultChecksum: String(format: "%016llx", outcome.checksum),
            durationMilliseconds: DurationReport(
                samples: samples,
                min: sortedSamples.first ?? 0,
                p50: percentile(sortedSamples, percentile: 0.50),
                p95: percentile(sortedSamples, percentile: 0.95),
                max: sortedSamples.last ?? 0
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

    private static func verifyDeterminism(
        _ outcome: BenchmarkOutcome,
        expected: inout BenchmarkOutcome?,
        scenario: String
    ) throws {
        if let expected, expected != outcome {
            throw BenchmarkError.nondeterministicResult(scenario)
        }
        expected = outcome
    }

    private static func contextOutcome(
        _ context: LibraryQueryContext,
        sourceIDs: [UUID]
    ) -> BenchmarkOutcome {
        var hasher = FNV1a64()
        hasher.update(context.generation)
        var matchedCount = 0
        for id in sourceIDs where context.factsByFrameID[id] != nil {
            matchedCount += 1
            hasher.update(id)
        }
        hasher.update(UInt64(matchedCount))
        return BenchmarkOutcome(matchedCount: matchedCount, checksum: hasher.value)
    }

    private static func projectionBatchOutcome(
        _ projections: [LibraryBrowserProjection]
    ) -> BenchmarkOutcome {
        var hasher = FNV1a64()
        var matchedCount = 0
        hasher.update(UInt64(projections.count))
        for projection in projections {
            matchedCount += projection.matchedCount
            hasher.update(UInt8(projection.queryWasValid ? 1 : 0))
            hasher.update(projection.contextGeneration)
            hasher.update(UInt64(projection.sourceCount))
            hasher.update(UInt64(projection.matchedCount))
            projection.orderedFrameIDs.forEach { hasher.update($0) }
            hasher.update(UInt64(projection.folderSections.count))
            for section in projection.folderSections {
                section.orderedFrameIDs.forEach { hasher.update($0) }
            }
        }
        return BenchmarkOutcome(matchedCount: matchedCount, checksum: hasher.value)
    }

    private static func makeFacts(count: Int) -> [LibraryFrameQueryFacts] {
        let words = ["night", "archive", "portrait", "train", "grain", "seoul", "studio"]
        let profileStates: [LibraryScannerProfileState] = [
            .unknown, .none, .missing, .draft, .realOnly, .pairedSmoke, .pairedValidated,
        ]
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            let id = deterministicUUID(index)
            let rollID = deterministicUUID(1_000_000 + index / 36)
            let padded = String(format: "%06d", index)
            let folder = "/benchmark/roll-\(String(format: "%04d", index / 100))"
            let firstWord = words[index % words.count]
            let secondWord = words[(index / words.count + 1) % words.count]
            return LibraryFrameQueryFacts(
                id: id,
                textValues: [
                    .displayName: ["Frame \(padded)"],
                    .fileName: ["frame-\(padded).tif"],
                    .folder: [folder],
                    .roll: ["Roll \(index / 36)"],
                    .film: ["color negative"],
                    .camera: [index.isMultiple(of: 2) ? "Nikon F3" : "Canon F-1"],
                    .lens: [index.isMultiple(of: 3) ? "50mm" : "35mm"],
                    .keywords: [firstWord, secondWord],
                    .titleDescription: ["\(firstWord) \(secondWord) contact sheet"],
                    .scannerProfile: ["profile-\(index % 12)"],
                    .scannerDevice: ["scanner-\(index % 4)"],
                    .lightSourceProfile: ["light-\(index % 3)"],
                    .collection: index.isMultiple(of: 5) ? ["Archive"] : [],
                ],
                sortName: "frame-\(padded)",
                folderPath: folder,
                scannedAt: epoch.addingTimeInterval(TimeInterval(index)),
                contentDate: epoch.addingTimeInterval(TimeInterval(index * 60)),
                contentCalendarDate: LibraryCalendarDate(
                    year: 2020 + index % 6,
                    month: index % 12 + 1,
                    day: index % 28 + 1
                ),
                fileSizeBytes: index.isMultiple(of: 19) ? nil : Int64(4_000_000 + index * 97),
                rollID: rollID,
                filmType: .colorNegative,
                rating: index % 6,
                pickState: index.isMultiple(of: 7)
                    ? .picked
                    : (index.isMultiple(of: 11) ? .rejected : .unflagged),
                availability: index.isMultiple(of: 29)
                    ? .unknown
                    : (index.isMultiple(of: 17) ? .offline : .online),
                isVirtualCopy: index.isMultiple(of: 13),
                hasInfraredCapture: index.isMultiple(of: 3),
                hasDefectRecipe: index.isMultiple(of: 5),
                scannerProfileState: profileStates[index % profileStates.count],
                metadataPresentFields: [.snapshot, .camera, .lens, .keywords, .descriptive],
                metadataReadProblem: false,
                hasCreativeCalibrationAdjustments: index.isMultiple(of: 23)
            )
        }
    }

    private static func makeFolderFacts(
        from facts: [LibraryFrameQueryFacts]
    ) -> [LibraryFolderQueryFact] {
        Array(Set(facts.map(\.folderPath))).sorted().map { path in
            LibraryFolderQueryFact(
                id: path,
                folderID: nil,
                title: URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
            )
        }
    }

    private static func deterministicUUID(_ index: Int) -> UUID {
        let suffix = String(format: "%012llx", UInt64(index + 1))
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
    }

    private static func checksum(_ ids: [UUID]) -> String {
        var hasher = FNV1a64()
        hasher.update(UInt64(ids.count))
        ids.forEach { hasher.update($0) }
        return String(format: "%016llx", hasher.value)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func percentile(_ sorted: [Double], percentile: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
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

    private static func environmentReport() -> EnvironmentReport {
        EnvironmentReport(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: sysctlString("hw.machine") ?? "unknown",
            hardwareModel: sysctlString("hw.model") ?? "unknown",
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }

    private static func writeReportIfRequested(_ report: BenchmarkReport) throws {
        guard let path = ProcessInfo.processInfo.environment["NEGAFLOW_LIBRARY_QUERY_PERF_REPORT"],
              !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    private static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }
}

private struct FNV1a64 {
    private(set) var value: UInt64 = 14_695_981_039_346_656_037

    mutating func update(_ byte: UInt8) {
        value ^= UInt64(byte)
        value &*= 1_099_511_628_211
    }

    mutating func update(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            bytes.forEach { update($0) }
        }
    }

    mutating func update(_ uuid: UUID) {
        var bytes = uuid.uuid
        withUnsafeBytes(of: &bytes) { raw in
            raw.forEach { update($0) }
        }
    }
}

private enum BenchmarkError: Error {
    case invalidDuration(String)
    case nondeterministicResult(String)
}

private struct BenchmarkOutcome: Equatable {
    let matchedCount: Int
    let checksum: UInt64
}

private struct MemorySnapshot {
    let residentBytes: Int64
    let maxRSSBytes: Int64
}

private struct BenchmarkReport: Encodable {
    let schemaVersion: Int
    let generatorVersion: Int
    let queryVersion: Int
    let configuration: String
    let timingGateApplied: Bool
    let warmupIterations: Int
    let measurementIterations: Int
    let environment: EnvironmentReport
    let cases: [BenchmarkCaseReport]
}

private struct EnvironmentReport: Encodable {
    let osVersion: String
    let architecture: String
    let hardwareModel: String
    let activeProcessorCount: Int
    let physicalMemoryBytes: UInt64
}

private struct BenchmarkCaseReport: Encodable {
    let scenario: String
    let frameCount: Int
    let matchedCount: Int
    let sourceChecksum: String
    let resultChecksum: String
    let durationMilliseconds: DurationReport
    let memory: MemoryReport
}

private struct DurationReport: Encodable {
    let samples: [Double]
    let min: Double
    let p50: Double
    let p95: Double
    let max: Double
}

private struct MemoryReport: Encodable {
    let residentBeforeBytes: Int64
    let residentAfterBytes: Int64
    let retainedDeltaBytes: Int64
    let maxRSSBeforeBytes: Int64
    let maxRSSAfterBytes: Int64
    let maxRSSGrowthBytes: Int64
}
