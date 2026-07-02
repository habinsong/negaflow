import Foundation
import CoreGraphics
import ImageIO
import Chromabase
#if canImport(AppKit)
import AppKit
#endif

// MARK: - MockScannerBackend
//
// 하드웨어가 없거나 스캐너가 점유 중일 때도 앱 전체 흐름을 실행할 수 있게 하는 가상 백엔드.
// 사용자는 백엔드 종류를 몰라도 동일한 스캔 UX를 쓴다.
//
// 실제 네거티브 TIFF가 samples/에 있으면 그것을 스캔 결과로 반환해서,
// 하드웨어 없이도 Chromabase 엔진 end-to-end를 시연할 수 있다.
public final class MockScannerBackend: ScannerBackend, @unchecked Sendable {
    public let backendType: BackendType = .mock
    private var lastError: ScannerError?
    private var cancelled = false

    /// 샘플 네거티브 경로(있으면 Scan 결과로 사용). 없으면 합성 그라데이션을 만든다.
    public var sampleNegativesDir: URL? = {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let samples = here.appendingPathComponent("samples")
        return FileManager.default.fileExists(atPath: samples.path) ? samples : nil
    }()

    public init() {}

    public func getLastError() -> ScannerError? { lastError }

    public func detectScanners() async throws -> [ScannerDescriptor] {
        return [ScannerDescriptor(
            id: "mock-plustek-8200i",
            displayName: "Plustek OpticFilm 8200i (Demo)",
            vendor: "Plustek",
            model: "OpticFilm 8200i",
            backendType: .mock,
            connectionType: .internalBus,
            verifiedStatus: .verified,
            driverVersion: "mock"
        )]
    }

    public func getCapabilities(scannerID: String) async throws -> ScannerCapabilities {
        ScannerCapabilities(
            supportedResolutions: [.r900, .r1800, .r3600, .r7200],
            supportedModes: [.color, .gray],
            supportedBitDepths: [.eight, .sixteen],
            supportsPreview: true,
            supportsTransparency: true,
            supportsInfrared: false,
            supportsMultiExposure: false,
            supportsScanArea: true,
            supportsLampWarmupStatus: true,
            outputFormats: ["tiff"]
        )
    }

    public func startPreviewScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        var o = options; o.resolution = .preview; o.bitDepth = .eight
        return try await startFullScan(o, progress: progress)
    }

    public func startFullScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        cancelled = false
        progress(ScanProgress(phase: .connecting, fraction: 0.05, message: "Connecting scanner"))
        // 샘플 네거티브가 있으면 그것을 반환(진짜 엔진 테스트 입력).
        if let url = findSampleNegative() {
            try? await Task.sleep(nanoseconds: 300_000_000)
            progress(ScanProgress(phase: .scanningRGB, fraction: 0.5, message: "Scanning RGB"))
            try? await Task.sleep(nanoseconds: 300_000_000)
            progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))
            let (w, h) = ScanTempFile.imageSize(at: url)
            return ScanResult(
                rawFileURL: url, width: w, height: h,
                resolution: options.resolution, bitDepth: options.bitDepth,
                backendUsed: .mock
            )
        }
        // 없으면 합성 네거티브(오렌지 마스크 + 그라데이션) 생성.
        let outURL = options.temporaryOutputURL
            ?? ScanTempFile.makeURL(prefix: "negaflow_mock", suffix: ".tiff")
        let w = 1200, h = 800
        try Self.writeSyntheticNegative(width: w, height: h, to: outURL)
        for f in stride(from: 0.1, through: 0.9, by: 0.2) {
            if cancelled { throw ScannerError(.cancelled) }
            progress(ScanProgress(phase: .scanningRGB, fraction: f, message: "Scanning RGB"))
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))
        return ScanResult(
            rawFileURL: outURL, width: w, height: h,
            resolution: options.resolution, bitDepth: options.bitDepth,
            backendUsed: .mock
        )
    }

    public func cancelScan() async { cancelled = true }

    private func findSampleNegative() -> URL? {
        guard let dir = sampleNegativesDir else { return nil }
        let candidates = ["raw_3600_16bit.tiff", "_probe_600_16.tiff"]
        return candidates.compactMap { name in
            let u = dir.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }.first
    }

    /// 합성 컬러 네거티브. 오렌지 마스크 기저 + 위로 갈수록 밝은 그라데이션.
    /// Chromabase가 이것을 제대로 반전하면 벽/하늘이 깨끗한 회색~청색으로 나와야 한다.
    public static func writeSyntheticNegative(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.genericRGBLinear)!
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        // 오렌지 마스크 기저. 반전하면 청녹색 기조가 되도록 R>G>B.
        // 위쪽(하늘)은 더 밝게 → 반전 시 더 어두운 하늘이 되도록 역매핑.
        for y in 0..<height {
            for x in 0..<width {
                let t = Double(y) / Double(height)         // 0(아래) ~ 1(위)
                let horiz = Double(x) / Double(width)
                // 베이스 오렌지 마스크: R 높음, G 중간, B 낮음
                let baseR = 0.88, baseG = 0.62, baseB = 0.42
                // 위쪽(하늘)은 마스크 위에 약간 더 밝은 값을 얹음
                let sky = t * 0.08
                let side = (0.5 - abs(horiz - 0.5)) * 0.04   // 가운데 약간 더 밝
                let r = min(1.0, baseR + sky + side)
                let g = min(1.0, baseG + sky * 0.9 + side)
                let b = min(1.0, baseB + sky * 0.7 + side)
                let i = (y * width + x) * 4
                bytes[i]     = UInt8(r * 255)
                bytes[i + 1] = UInt8(g * 255)
                bytes[i + 2] = UInt8(b * 255)
                bytes[i + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        guard let img = ctx.makeImage() else { throw ScannerError(.ioFailure, "synthetic image") }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
