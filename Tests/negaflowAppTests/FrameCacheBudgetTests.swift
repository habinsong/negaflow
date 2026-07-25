import XCTest
@testable import negaflowApp

/// 상주 한도 예산 계산 — 설치 메모리에서 자동값과 수동 상한을 유도한다.
final class FrameCacheBudgetTests: XCTestCase {
    private func gigabytes(_ value: Double) -> UInt64 {
        UInt64(value * 1_024 * 1_024 * 1_024)
    }

    func testEightGigabytesKeepsTheConservativeDefaults() {
        let limits = FrameCacheBudget.automaticLimits(physicalMemoryBytes: gigabytes(8))

        XCTAssertEqual(limits.cleanedRaw, 2)
        XCTAssertEqual(limits.developed, 3)
    }

    func testAutomaticLimitsGrowWithInstalledMemory() {
        let sizes: [Double] = [8, 16, 24, 32, 48, 64, 96]
        var previous = FrameCacheBudget.automaticLimits(physicalMemoryBytes: gigabytes(sizes[0]))

        for size in sizes.dropFirst() {
            let limits = FrameCacheBudget.automaticLimits(physicalMemoryBytes: gigabytes(size))
            XCTAssertGreaterThanOrEqual(limits.cleanedRaw, previous.cleanedRaw,
                                        "\(size)GB 자동값이 더 작아지면 안 된다")
            XCTAssertGreaterThanOrEqual(limits.developed, previous.developed)
            previous = limits
        }
        XCTAssertGreaterThan(previous.cleanedRaw, 2, "큰 메모리에서는 기본값보다 커져야 한다")
    }

    func testAutomaticBudgetStaysWithinThisMachinesFraction() {
        for size in [16.0, 24.0, 32.0, 48.0, 64.0, 96.0] {
            let bytes = gigabytes(size)
            let limits = FrameCacheBudget.automaticLimits(physicalMemoryBytes: bytes)
            let fraction = FrameCacheBudget.residentMemoryFraction(limits, physicalMemoryBytes: bytes)
            let budgetFraction = FrameCacheBudget.automaticMemoryFraction(physicalMemoryBytes: bytes)

            XCTAssertLessThanOrEqual(
                fraction,
                budgetFraction + 0.01,
                "\(size)GB 자동값이 예산을 넘었다"
            )
        }
    }

    /// 예산 비율은 작은 머신일수록 낮고, 메모리가 늘어도 상한을 넘지 않는다.
    func testAutomaticFractionRampsWithInstalledMemory() {
        XCTAssertEqual(
            FrameCacheBudget.automaticMemoryFraction(physicalMemoryBytes: gigabytes(16)),
            FrameCacheBudget.automaticMinimumFraction,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            FrameCacheBudget.automaticMemoryFraction(physicalMemoryBytes: gigabytes(8)),
            FrameCacheBudget.automaticMinimumFraction,
            accuracy: 1e-9
        )
        XCTAssertGreaterThan(
            FrameCacheBudget.automaticMemoryFraction(physicalMemoryBytes: gigabytes(32)),
            FrameCacheBudget.automaticMemoryFraction(physicalMemoryBytes: gigabytes(16))
        )
        XCTAssertEqual(
            FrameCacheBudget.automaticMemoryFraction(physicalMemoryBytes: gigabytes(256)),
            FrameCacheBudget.automaticMaximumFraction,
            accuracy: 1e-9
        )
    }

    func testManualCeilingStaysWithinSeventyPercentAndNeverBelowAutomatic() {
        for size in [8.0, 16.0, 32.0, 64.0, 96.0] {
            let bytes = gigabytes(size)
            let automatic = FrameCacheBudget.automaticLimits(physicalMemoryBytes: bytes)
            let manual = FrameCacheBudget.manualMaximumLimits(physicalMemoryBytes: bytes)
            let fraction = FrameCacheBudget.residentMemoryFraction(manual, physicalMemoryBytes: bytes)

            XCTAssertGreaterThanOrEqual(manual.cleanedRaw, automatic.cleanedRaw)
            XCTAssertGreaterThanOrEqual(manual.developed, automatic.developed)
            XCTAssertLessThanOrEqual(
                fraction,
                FrameCacheBudget.manualMemoryFraction + 0.01,
                "\(size)GB 수동 상한이 70%를 넘었다"
            )
        }
    }

    func testLimitsNeverDropBelowTheShippedMinimum() {
        for size in [4.0, 8.0, 16.0, 64.0] {
            let limits = FrameCacheBudget.automaticLimits(physicalMemoryBytes: gigabytes(size))
            XCTAssertGreaterThanOrEqual(limits.cleanedRaw, FrameCacheBudget.minimumCleanedRaw)
            XCTAssertGreaterThanOrEqual(limits.developed, FrameCacheBudget.minimumDeveloped)
        }
    }

    /// 참고용 — 실제 배분 값을 로그로 남긴다(회귀 시 눈으로 확인).
    func testReportAutomaticTiers() {
        for size in [8.0, 16.0, 24.0, 32.0, 48.0, 64.0, 96.0, 128.0] {
            let bytes = gigabytes(size)
            let automatic = FrameCacheBudget.automaticLimits(physicalMemoryBytes: bytes)
            let manual = FrameCacheBudget.manualMaximumLimits(physicalMemoryBytes: bytes)
            print(String(
                format: "[tier] %.0fGB auto=%d/%d (%.1fGB, %.0f%%) manualMax=%d/%d (%.1fGB)",
                size,
                automatic.cleanedRaw, automatic.developed,
                FrameCacheBudget.estimatedResidentMegabytes(automatic) / 1_024,
                FrameCacheBudget.residentMemoryFraction(automatic, physicalMemoryBytes: bytes) * 100,
                manual.cleanedRaw, manual.developed,
                FrameCacheBudget.estimatedResidentMegabytes(manual) / 1_024
            ))
        }
    }
}
