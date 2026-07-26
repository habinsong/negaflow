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
// 번들된 사용자 제공 네거티브 TIFF로 하드웨어 없이 전체 스캔 흐름을 시연한다.
public final class MockScannerBackend: ScannerBackend, @unchecked Sendable {
    public static let filmScannerID = "mock-plustek-8200i"
    public static let flatbedScannerID = "mock-negaflow-flatbed"
    public static let scannerDescriptors: [ScannerDescriptor] = [
        ScannerDescriptor(
            id: filmScannerID,
            displayName: "negaflow Scanner",
            vendor: "negaflow",
            model: "OpticFilm 8200i",
            backendType: .mock,
            connectionType: .internalBus,
            verifiedStatus: .verified,
            driverVersion: "mock"
        ),
        ScannerDescriptor(
            id: flatbedScannerID,
            displayName: "negaflow Flatbed Scanner",
            vendor: "negaflow",
            model: "Flatbed Scanner Simulator",
            backendType: .mock,
            connectionType: .internalBus,
            verifiedStatus: .verified,
            driverVersion: "mock"
        ),
    ]

    public let backendType: BackendType = .mock
    private var lastError: ScannerError?
    private var cancelled = false
    public private(set) var simulatorIncludesPerforation = false
    public private(set) var simulatorFrameFormat: FilmFrameFormat = .fullFrame35mm

    /// 테스트에서 명시적으로 지정한 샘플 네거티브 경로입니다.
    public var sampleNegativesDir: URL?

    public init() {}

    public func setSimulatorIncludesPerforation(_ includesPerforation: Bool) {
        simulatorIncludesPerforation = includesPerforation
    }

    public func setSimulatorFrameFormat(_ frameFormat: FilmFrameFormat) {
        simulatorFrameFormat = frameFormat
    }

    public func getLastError() -> ScannerError? { lastError }

    public func detectScanners() async throws -> [ScannerDescriptor] {
        Self.scannerDescriptors
    }

    public func getCapabilities(scannerID: String) async throws -> ScannerCapabilities {
        switch scannerID {
        case Self.filmScannerID:
            return ScannerCapabilities(
                supportedResolutions: [.r900, .r1800, .r3600, .r7200],
                supportedModes: [.color, .gray],
                supportedBitDepths: [.eight, .sixteen],
                sourceModes: ["Transparency Adapter"],
                transparencyModes: ["Transparency Adapter"],
                supportsPreview: true,
                supportsTransparency: true,
                supportsInfrared: false,
                supportsMultiExposure: false,
                supportsScanArea: true,
                supportsPositionedScanArea: false,
                supportsLampWarmupStatus: true,
                disabledReasons: Self.disabledReasons,
                maxScanArea: .fullFrame35mm,
                minScanArea: ScanArea(widthMM: 4, heightMM: 4),
                scanAreaUnit: .millimeter,
                outputFormats: ["tiff"],
                estimatedScanSpeeds: [900: 4, 1800: 9, 3600: 28, 7200: 95]
            )
        case Self.flatbedScannerID:
            return ScannerCapabilities(
                supportedResolutions: [.r900, .r1800, .r3600],
                supportedModes: [.color, .gray],
                supportedBitDepths: [.eight, .sixteen],
                sourceModes: ["Flatbed", "Transparency Unit"],
                transparencyModes: ["Transparency Unit"],
                supportsPreview: true,
                supportsTransparency: true,
                supportsInfrared: false,
                supportsMultiExposure: false,
                supportsScanArea: true,
                supportsPositionedScanArea: true,
                supportsLampWarmupStatus: true,
                scanOriginXRange: ScannerOptionRange(minimum: 0, maximum: 205, step: 0.1),
                scanOriginYRange: ScannerOptionRange(minimum: 0, maximum: 292, step: 0.1),
                scanWidthRange: ScannerOptionRange(minimum: 5, maximum: 210, step: 0.1),
                scanHeightRange: ScannerOptionRange(minimum: 5, maximum: 297, step: 0.1),
                disabledReasons: Self.disabledReasons,
                maxScanArea: ScanArea(widthMM: 210, heightMM: 297),
                minScanArea: ScanArea(widthMM: 5, heightMM: 5),
                scanAreaUnit: .millimeter,
                outputFormats: ["tiff"],
                estimatedScanSpeeds: [900: 4, 1800: 9, 3600: 28]
            )
        default:
            throw ScannerError(.notConnected, "Unknown mock scanner: \(scannerID)")
        }
    }

    public func startPreviewScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        guard options.scannerID == Self.flatbedScannerID else {
            guard options.scannerID == Self.filmScannerID else {
                throw ScannerError(.notConnected, "Unknown mock scanner: \(options.scannerID)")
            }
            var appliedOptions = options
            appliedOptions.resolution = .preview
            appliedOptions.bitDepth = .eight
            return try await startFullScan(appliedOptions, progress: progress)
        }
        cancelled = false
        var appliedOptions = options
        appliedOptions.resolution = .preview
        appliedOptions.bitDepth = .eight
        let outURL = appliedOptions.temporaryOutputURL
            ?? ScanTempFile.makeURL(prefix: "negaflow_mock_flatbed_preview", suffix: ".tiff")
        appliedOptions.temporaryOutputURL = outURL
        progress(ScanProgress(phase: .connecting, fraction: 0.05, message: "Connecting scanner"))
        try Self.writeFlatbedPreview(
            includesPerforation: simulatorIncludesPerforation,
            frameFormat: simulatorFrameFormat,
            to: outURL
        )
        if cancelled { throw ScannerError(.cancelled) }
        progress(ScanProgress(phase: .previewScanning, fraction: 0.65, message: "Scanning preview"))
        try? await Task.sleep(nanoseconds: 250_000_000)
        if cancelled { throw ScannerError(.cancelled) }
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))
        let (width, height) = ScanTempFile.imageSize(at: outURL)
        return ScanResult(
            rawFileURL: outURL,
            width: width,
            height: height,
            resolution: .preview,
            bitDepth: .eight,
            reportedResolution: .preview,
            reportedBitDepth: .eight,
            backendUsed: .mock,
            appliedOptionsEvidence: .verified(appliedOptions)
        )
    }

    public func startFullScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        guard options.scannerID == Self.filmScannerID
                || options.scannerID == Self.flatbedScannerID else {
            throw ScannerError(.notConnected, "Unknown mock scanner: \(options.scannerID)")
        }
        cancelled = false
        progress(ScanProgress(phase: .connecting, fraction: 0.05, message: "Connecting scanner"))
        if options.scannerID == Self.flatbedScannerID {
            let outURL = options.temporaryOutputURL
                ?? ScanTempFile.makeURL(prefix: "negaflow_mock_flatbed_frame", suffix: ".tiff")
            let size = try Self.writeFlatbedRegion(
                options.scanArea,
                includesPerforation: simulatorIncludesPerforation,
                frameFormat: simulatorFrameFormat,
                to: outURL
            )
            for fraction in stride(from: 0.1, through: 0.9, by: 0.2) {
                if cancelled { throw ScannerError(.cancelled) }
                progress(ScanProgress(
                    phase: .scanningRGB,
                    fraction: fraction,
                    message: "Scanning selected area"
                ))
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))
            var appliedOptions = options
            appliedOptions.temporaryOutputURL = outURL
            return ScanResult(
                rawFileURL: outURL,
                width: size.width,
                height: size.height,
                resolution: options.resolution,
                bitDepth: options.bitDepth,
                reportedResolution: options.resolution,
                reportedBitDepth: options.bitDepth,
                backendUsed: .mock,
                appliedOptionsEvidence: .verified(appliedOptions)
            )
        }
        // 샘플 네거티브가 있으면 그것을 반환(진짜 엔진 테스트 입력).
        if let url = findSampleNegative() {
            try? await Task.sleep(nanoseconds: 300_000_000)
            progress(ScanProgress(phase: .scanningRGB, fraction: 0.5, message: "Scanning RGB"))
            try? await Task.sleep(nanoseconds: 300_000_000)
            progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))
            let resultURL: URL
            if let requestedURL = options.temporaryOutputURL,
               requestedURL.standardizedFileURL != url.standardizedFileURL {
                guard !FileManager.default.fileExists(atPath: requestedURL.path) else {
                    throw ScannerError(.ioFailure, "mock scan 최종 경로가 이미 존재함: \(requestedURL.path)")
                }
                do {
                    try FileManager.default.copyItem(at: url, to: requestedURL)
                } catch {
                    throw ScannerError(.ioFailure, "mock sample copy 실패: \(error.localizedDescription)")
                }
                resultURL = requestedURL
            } else {
                resultURL = url
            }
            let (w, h) = ScanTempFile.imageSize(at: resultURL)
            var appliedOptions = options
            appliedOptions.temporaryOutputURL = resultURL
            return ScanResult(
                rawFileURL: resultURL, width: w, height: h,
                resolution: options.resolution, bitDepth: options.bitDepth,
                reportedResolution: options.resolution,
                reportedBitDepth: options.bitDepth,
                backendUsed: .mock,
                appliedOptionsEvidence: .verified(appliedOptions)
            )
        }
        // 사용자 제공 단일 프레임 샘플을 사용한다.
        let outURL = options.temporaryOutputURL
            ?? ScanTempFile.makeURL(prefix: "negaflow_mock_frame", suffix: ".tiff")
        try Self.writeSimulatorFrame(
            includesPerforation: simulatorIncludesPerforation,
            to: outURL
        )
        let (w, h) = ScanTempFile.imageSize(at: outURL)
        for f in stride(from: 0.1, through: 0.9, by: 0.2) {
            if cancelled { throw ScannerError(.cancelled) }
            progress(ScanProgress(phase: .scanningRGB, fraction: f, message: "Scanning RGB"))
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))
        var appliedOptions = options
        appliedOptions.temporaryOutputURL = outURL
        return ScanResult(
            rawFileURL: outURL, width: w, height: h,
            resolution: options.resolution, bitDepth: options.bitDepth,
            reportedResolution: options.resolution,
            reportedBitDepth: options.bitDepth,
            backendUsed: .mock,
            appliedOptionsEvidence: .verified(appliedOptions)
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

    private static let disabledReasons = [
        "brightness": "Demo backend does not expose hardware brightness.",
        "contrast": "Demo backend does not expose hardware contrast.",
        "infrared": "Demo backend has no real IR channel.",
        "multiExposure": "Demo backend has no hardware exposure control."
    ]

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
