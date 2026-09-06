import AppKit
import Combine
import CoreImage
import Darwin
import XCTest
@testable import Chromabase
@testable import negaflowApp

@MainActor
final class InputGammaLivePreviewPerformanceTests: XCTestCase {
    func testRealSourceDragPublishesBeforeCommitWithoutBlankFrames() async throws {
        let path = ProcessInfo.processInfo.environment["NEGAFLOW_GAMMA_LIVE_SOURCE"]
        try XCTSkipUnless(path != nil, "Set NEGAFLOW_GAMMA_LIVE_SOURCE for the real-source drag measurement.")
        let url = URL(fileURLWithPath: try XCTUnwrap(path))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative, sourceKind: .importedFile)
        let model = AppModel(libraryDefectDirectoryURL: directory)
        model.activeWorkspaceModule = .develop
        model.canvasDisplayTargetPixels = 1536
        model.frames = [frame]
        model.selectedFrameID = frame.id
        defer { model.frames = [] }
        await model.checkInputGammaSupport(for: frame)
        XCTAssertNotNil(frame.inputGammaPreviewSource)
        frame.params.inputGamma = try .power(2.2)
        frame.params.baseScale = try FilmBaseScale(0.75)
        await model.developFrame(frame)
        let warmDeadline = CFAbsoluteTimeGetCurrent() + 30
        while (!frame.developedIsSettled || frame.isDeveloping) && CFAbsoluteTimeGetCurrent() < warmDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(frame.developedImage)
        XCTAssertTrue(frame.developedIsSettled)
        let original = frame.params
        let initialMemory = Self.memoryMB()
        let started = CFAbsoluteTimeGetCurrent()
        var updates: [Double] = []
        var blanks = 0
        let subscription = frame.$developedImage.dropFirst().sink { image in
            if image == nil { blanks += 1 }
            else { updates.append(CFAbsoluteTimeGetCurrent() - started) }
        }
        defer { subscription.cancel() }
        var peakMemory = initialMemory
        for index in 0..<60 {
            let value = 1.8 + Double(index % 7) / 10
            model.previewInputGamma(try .power(value), for: frame)
            peakMemory = max(peakMemory, Self.memoryMB())
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        let dragDuration = CFAbsoluteTimeGetCurrent() - started
        let duringDrag = updates.count
        XCTAssertGreaterThan(duringDrag, 2, "Preview must update while the pointer is still held.")
        XCTAssertEqual(frame.params, original, "Draft must not enter persistence or output snapshots.")
        let committed = await model.setInputGamma(try .power(2.1), for: frame)
        model.previewInputGamma(nil, for: frame)
        XCTAssertTrue(committed)
        let deadline = CFAbsoluteTimeGetCurrent() + 20
        while (!frame.developedIsSettled || frame.isDeveloping) && CFAbsoluteTimeGetCurrent() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(frame.developedIsSettled)
        XCTAssertEqual(blanks, 0)
        XCTAssertEqual(frame.params.inputGamma.value, 2.1)
        XCTAssertEqual(frame.params.baseScale.value, 0.75)
        let result: [String: Any] = [
            "drag_seconds": dragDuration, "updates_during_drag": duringDrag,
            "updates_per_second": Double(duringDrag) / dragDuration,
            "first_update_ms": (updates.first ?? -1) * 1000,
            "blank_frames": blanks, "initial_memory_mb": initialMemory,
            "peak_memory_mb": peakMemory, "final_memory_mb": Self.memoryMB(),
            "encoded_source_bytes": frame.inputGammaPreviewSource?.byteCost ?? 0,
            "settle_ms": (CFAbsoluteTimeGetCurrent() - started - dragDuration) * 1000
        ]
        print("[gamma-live] " + String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }

    private static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / (1024 * 1024) : -1
    }
}
