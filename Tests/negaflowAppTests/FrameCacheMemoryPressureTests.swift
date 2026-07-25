import CoreGraphics
import Foundation
import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class FrameCacheMemoryPressureTests: XCTestCase {
    func testPolicyReducesLimitsMonotonically() {
        let policy = FrameCachePolicy(
            normalLimits: FrameCacheLimits(cleanedRaw: 4, developed: 5)
        )

        XCTAssertEqual(policy.limits(for: .normal), FrameCacheLimits(cleanedRaw: 4, developed: 5))
        XCTAssertEqual(policy.limits(for: .warning), FrameCacheLimits(cleanedRaw: 1, developed: 2))
        XCTAssertEqual(policy.limits(for: .critical), FrameCacheLimits(cleanedRaw: 0, developed: 1))
    }

    func testCombinedEventUsesMostSeverePressure() {
        XCTAssertEqual(FrameCachePressureLevel(event: [.normal]), .normal)
        XCTAssertEqual(FrameCachePressureLevel(event: [.warning]), .warning)
        XCTAssertEqual(FrameCachePressureLevel(event: [.warning, .critical]), .critical)
    }

    func testWarningImmediatelyTrimsBothResidentListsAndPreservesSelection() {
        let manager = FrameCacheManager(maxResidentCleanedRaw: 3, maxResidentDeveloped: 3)
        let frames = (1...3).map(Self.makeFrame)
        var cleanedEvictions: [UUID] = []
        var developedEvictions: [UUID] = []

        for frame in frames {
            manager.markCleanedRawResident(frame, frames: frames) { _ in }
            manager.markDevelopedResident(
                frame,
                selectedFrameID: frames[0].id,
                frames: frames
            ) { _ in }
        }
        manager.applyPressure(
            .warning,
            selectedFrameID: frames[0].id,
            frames: frames,
            evictCleanedRaw: { cleanedEvictions.append($0.id) },
            evictDeveloped: { developedEvictions.append($0.id) }
        )

        XCTAssertEqual(manager.maxResidentCleanedRaw, 1)
        XCTAssertEqual(manager.maxResidentDeveloped, 2)
        XCTAssertEqual(manager.residentCleanedRawIDs, [frames[2].id])
        XCTAssertEqual(cleanedEvictions, [frames[0].id, frames[1].id])
        XCTAssertTrue(manager.residentDevelopedIDs.contains(frames[0].id))
        XCTAssertEqual(developedEvictions, [frames[1].id])
    }

    func testCriticalDropsRegenerableCleanedRawAndKeepsOnlySelectedDevelopedFrame() {
        let manager = FrameCacheManager(maxResidentCleanedRaw: 2, maxResidentDeveloped: 3)
        let frames = (1...3).map(Self.makeFrame)
        var cleanedEvictions: [UUID] = []
        var developedEvictions: [UUID] = []

        for frame in frames {
            manager.markCleanedRawResident(frame, frames: frames) { _ in }
            manager.markDevelopedResident(
                frame,
                selectedFrameID: frames[1].id,
                frames: frames
            ) { _ in }
        }
        manager.applyPressure(
            .critical,
            selectedFrameID: frames[1].id,
            frames: frames,
            evictCleanedRaw: { cleanedEvictions.append($0.id) },
            evictDeveloped: { developedEvictions.append($0.id) }
        )

        XCTAssertTrue(manager.residentCleanedRawIDs.isEmpty)
        XCTAssertEqual(Set(cleanedEvictions), Set([frames[1].id, frames[2].id]))
        XCTAssertEqual(manager.residentDevelopedIDs, [frames[1].id])
        XCTAssertEqual(Set(developedEvictions), Set([frames[0].id, frames[2].id]))
    }

    func testReturningToNormalRaisesFutureLimitWithoutInventingResidents() {
        let manager = FrameCacheManager(maxResidentCleanedRaw: 2, maxResidentDeveloped: 3)
        let frame = Self.makeFrame(1)
        manager.markCleanedRawResident(frame, frames: [frame]) { _ in }
        manager.applyPressure(
            .critical,
            selectedFrameID: frame.id,
            frames: [frame],
            evictCleanedRaw: { _ in },
            evictDeveloped: { _ in }
        )
        manager.applyPressure(
            .normal,
            selectedFrameID: frame.id,
            frames: [frame],
            evictCleanedRaw: { _ in },
            evictDeveloped: { _ in }
        )

        XCTAssertEqual(manager.maxResidentCleanedRaw, 2)
        XCTAssertEqual(manager.maxResidentDeveloped, 3)
        XCTAssertTrue(manager.residentCleanedRawIDs.isEmpty)
    }

    private static func makeFrame(_ index: Int) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-pressure-\(index).tif"),
            filmType: .colorNegative
        )
    }
}
