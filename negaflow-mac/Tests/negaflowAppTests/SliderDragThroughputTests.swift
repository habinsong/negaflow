import Combine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import negaflowApp

/// 슬라이더를 실제로 끄는 동안 화면이 몇 번 갱신되는지 재는 계측.
/// NEGAFLOW_SLIDER_DRAG_PERF=1 일 때만 돈다(시간 의존이라 일반 실행에서는 건너뛴다).
@MainActor
final class SliderDragThroughputTests: XCTestCase {
    func testDragPublishRate() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NEGAFLOW_SLIDER_DRAG_PERF"] == "1",
            "Set NEGAFLOW_SLIDER_DRAG_PERF=1 to run the drag throughput probe."
        )
        // 원본이 정착 상한(3600px)보다 큰지 아닌지로 입력 경로가 갈린다.
        // 큰 쪽만 프리뷰 raw 프록시를 캐시하고, 작은 쪽은 매 틱 원본을 다시 디코딩한다.
        try await measureDrag(width: 2_816, height: 1_877, label: "원본 2816px")
        try await measureDrag(width: 5_200, height: 3_467, label: "원본 5200px")
    }

    /// 요청 간격과 정착 폴링을 화면 주사율에서 뽑으므로, 이 기기에 없는 주사율까지 갈아끼워
    /// 실제 파이프라인을 돌려 본다. 60 Hz 부터 ProMotion·게이밍 패널 대역까지.
    func testDragHoldsUpAcrossRefreshRates() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NEGAFLOW_SLIDER_DRAG_PERF"] == "1",
            "Set NEGAFLOW_SLIDER_DRAG_PERF=1 to run the drag throughput probe."
        )
        for hz in [60, 120, 144, 240] {
            try await measureDrag(
                width: 2_816, height: 1_877, label: "\(hz)Hz", refreshRate: hz
            )
        }
        // 위 케이스는 현상 한 장(~14 ms)이 화면 한 프레임보다 길어 요청 간격을 현상 소요가
        // 지배한다. 주사율이 실제로 지배하는 건 그 반대, 즉 **작은 창 + 고주사율**이다
        // (1024px 프록시는 한 장이 2 ms 대라 240 Hz 의 4.2 ms 보다 빠르다).
        for hz in [120, 240] {
            try await measureDrag(
                width: 2_816, height: 1_877, label: "\(hz)Hz 작은창",
                refreshRate: hz, canvasPixels: 1_024
            )
        }
    }

    private func measureDrag(
        width: Int, height: Int, label: String,
        refreshRate: Int? = nil, canvasPixels: CGFloat = 2_816
    ) async throws {
        let url = try Self.writeSyntheticNegativeTIFF(width: width, height: height)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel(
            developController: refreshRate.map { hz in
                DevelopController(displayRefreshRate: { hz })
            }
        )
        model.activeWorkspaceModule = .develop
        model.canvasDisplayTargetPixels = canvasPixels
        let frame = ScanFrame(
            scanIndex: 1, rawScanURL: url, filmType: .colorNegative, sourceKind: .importedFile
        )
        model.frames = [frame]
        model.selectedFrameID = frame.id

        // 첫 현상(입력 디코드 + 프록시 생성)은 드래그 측정에서 제외한다.
        await model.developFrame(frame)
        XCTAssertTrue(frame.hasDevelopedOnce)

        var publishes = 0
        let cancellable = frame.$developedImage
            .dropFirst()
            .sink { _ in publishes += 1 }
        defer { cancellable.cancel() }

        // 드래그: 8 ms 간격(≈120 Hz 트랙패드)으로 값만 바꾼다.
        let tickInterval: UInt64 = 8_000_000
        let tickCount = 125          // ≈1.0 초
        let started = CFAbsoluteTimeGetCurrent()
        for step in 0..<tickCount {
            frame.updateParams { $0.exposure = Double(step) * 0.008 - 0.5 }
            model.requestDevelop(frame)
            try await Task.sleep(nanoseconds: tickInterval)
        }
        let dragElapsed = CFAbsoluteTimeGetCurrent() - started

        // 손을 뗀 뒤 마지막 값이 화면에 붙을 때까지.
        let settleDeadline = CFAbsoluteTimeGetCurrent() + 5
        while frame.isDeveloping, CFAbsoluteTimeGetCurrent() < settleDeadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let totalElapsed = CFAbsoluteTimeGetCurrent() - started

        print(String(
            format: "[drag] %@ throttle %.0f ms   publishes %d in %.2f s (%.1f/s)   settle total %.2f s   footprint %.0f MB",
            label as NSString,
            model.developController.throttleInterval * 1000,
            publishes, dragElapsed, Double(publishes) / dragElapsed, totalElapsed,
            Self.memoryFootprintMB()
        ))
        XCTAssertGreaterThan(publishes, 0, "드래그 중 화면이 한 번도 갱신되지 않았다")

        // 손을 뗐다 **다시 잡는 첫 틱**. 사용자가 값을 처음 움직일 때 느끼는 지연이고,
        // 정착 패스가 캐시를 자기 것으로 바꿔 놓은 뒤라 재측정이 끼어들기 쉬운 자리다.
        var restartTicks: [Double] = []
        for round in 0..<3 {
            // 손을 뗀 상태(정착 완료)를 만든다.
            let settledDeadline = CFAbsoluteTimeGetCurrent() + 10
            while !(frame.developedIsSettled && !frame.isDeveloping),
                  CFAbsoluteTimeGetCurrent() < settledDeadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let restartBaseKey = FilmBaseCacheKey(
                filmType: frame.filmType,
                mode: frame.params.baseEstimationMode,
                manualBaseRGB: frame.params.manualBaseRGB,
                filmStockDminID: frame.params.filmStockDminID,
                lightSourceProfileID: frame.params.lightSourceProfileID
            )
            frame.updateParams { $0.exposure = 0.2 + Double(round) * 0.05 }
            let started = CFAbsoluteTimeGetCurrent()
            let snapshot = model.makeSnapshot(
                for: frame, baseKey: restartBaseKey,
                needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
                needsThumbnail: false,
                proxyMaxDimension: DevelopFrameRenderer.interactiveProxyDimension(
                    displayTargetPixels: model.canvasDisplayTargetPixels
                )
            )
            _ = try DevelopFrameRenderer.render(snapshot)
            restartTicks.append(CFAbsoluteTimeGetCurrent() - started)
            // 다음 라운드를 위해 정착 패스를 한 번 더 돌려 캐시를 정착 쪽으로 되돌린다.
            let revision = frame.developRevision
            model.requestDevelop(frame)
            let deadline = CFAbsoluteTimeGetCurrent() + 10
            while !(frame.developRevision > revision && frame.developedIsSettled && !frame.isDeveloping),
                  CFAbsoluteTimeGetCurrent() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        print(String(
            format: "[drag]   └ %@ 재시작 첫 틱 %.1f ms (개별 %@)",
            label as NSString,
            median(restartTicks) * 1000,
            restartTicks.map { String(format: "%.1f", $0 * 1000) }.joined(separator: ", ") as NSString
        ))

        // 한 틱을 갈라 본다: 순수 렌더 vs 그 밖(스냅샷 준비·NSImage·발행·태스크 왕복).
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        var snapshotTimes: [Double] = []
        var renderTimes: [Double] = []
        var imageTimes: [Double] = []
        for step in 0..<8 {
            frame.updateParams { $0.exposure = Double(step) * 0.01 }
            let t0 = CFAbsoluteTimeGetCurrent()
            let snapshot = model.makeSnapshot(
                for: frame, baseKey: baseKey,
                needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
                needsThumbnail: false,
                proxyMaxDimension: DevelopFrameRenderer.interactiveProxyDimension(
                    displayTargetPixels: model.canvasDisplayTargetPixels
                )
            )
            let t1 = CFAbsoluteTimeGetCurrent()
            let rendered = try DevelopFrameRenderer.render(snapshot)
            let t2 = CFAbsoluteTimeGetCurrent()
            _ = NSImage(
                cgImage: rendered.developed,
                size: NSSize(width: rendered.developed.width, height: rendered.developed.height)
            )
            let t3 = CFAbsoluteTimeGetCurrent()
            snapshotTimes.append(t1 - t0)
            renderTimes.append(t2 - t1)
            imageTimes.append(t3 - t2)
        }
        print(String(
            format: "[drag]   └ %@ snapshot %.1f ms   render %.1f ms   NSImage %.1f ms",
            label as NSString,
            median(snapshotTimes) * 1000, median(renderTimes) * 1000, median(imageTimes) * 1000
        ))

        // 다시 잡는 첫 틱이 이어지는 틱보다 눈에 띄게 느리면, 정착 패스가 드래그용 캐시를
        // 밀어냈다는 뜻이다(측정 슬롯을 하나로 합치면 41.8 ms vs 15.1 ms 로 벌어졌다).
        // 기기 성능에 무관하도록 절대값이 아니라 이어지는 틱과의 비로 못박는다.
        XCTAssertLessThan(
            median(restartTicks), median(renderTimes) * 1.8,
            "\(label): 다시 잡는 첫 틱 \(median(restartTicks) * 1000) ms 가 이어지는 틱 \(median(renderTimes) * 1000) ms 보다 많이 느리다"
        )
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// 프로세스 실사용 메모리(MB). 최적화가 메모리를 대신 태우고 있지 않은지 같이 본다.
    private static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }

    /// 오렌지 마스크 위에 장면 밀도가 실린 합성 네거티브(실사진 미사용).
    private static func writeSyntheticNegativeTIFF(width: Int, height: Int) throws -> URL {
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let fy = Double(y) / Double(height - 1)
            for x in 0..<width {
                let fx = Double(x) / Double(width - 1)
                let scene = 0.05 + 0.9 * (0.5 + 0.5 * sin(fx * 7.1) * cos(fy * 5.3))
                let density = 1.0 - scene
                let i = (y * width + x) * 4
                pixels[i] = UInt16(0.86 * (0.12 + 0.88 * density) * 65_535)
                pixels[i + 1] = UInt16(0.68 * (0.10 + 0.90 * density * 0.94) * 65_535)
                pixels[i + 2] = UInt16(0.50 * (0.08 + 0.92 * density * 0.88) * 65_535)
                pixels[i + 3] = UInt16.max
            }
        }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let data = Data(bytes: pixels, count: pixels.count * MemoryLayout<UInt16>.size)
        let provider = CGDataProvider(data: data as CFData)!
        guard let cg = CGImage(
            width: width, height: height,
            bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 4 * MemoryLayout<UInt16>.size,
            space: linear,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { throw CocoaError(.fileWriteUnknown) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-drag-\(UUID().uuidString).tiff")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
