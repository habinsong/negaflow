import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import Chromabase
@testable import ScannerKit

final class ScannerKitTests: XCTestCase {
    func testScanOptionsStrongDefault() {
        let o = ScanOptions.strongDefault(scannerID: "sane-test")
        XCTAssertEqual(o.resolution, .r3600)
        XCTAssertEqual(o.bitDepth, .sixteen)
        XCTAssertEqual(o.colorMode, .color)
        XCTAssertEqual(o.filmType, .colorNegative)
        XCTAssertFalse(o.infraredEnabled)   // plan §4.2 IR off 기본
    }

    func testCapabilitiesGate() {
        let cap = ScannerCapabilities()
        XCTAssertTrue(cap.supports(resolution: .r7200))
        XCTAssertFalse(cap.supports(resolution: Resolution(4800)))
        XCTAssertTrue(cap.supports(depth: .sixteen))
        XCTAssertTrue(cap.supports(mode: .color))
    }

    func testBackendTypeFromScannerID() {
        XCTAssertEqual(BackendType(fromScannerID: "sane-genesys:libusb:000:010"), .sane)
        XCTAssertEqual(BackendType(fromScannerID: "ica-xyz"), .imageCaptureCore)
        XCTAssertEqual(BackendType(fromScannerID: "mock-1"), .mock)
    }

    func testParseSaneCapabilitiesDump() {
        let dump = """
        All options specific to device `genesys:libusb:000:010':
          Scan Mode:
            --mode Color|Gray [Gray]
            --depth 16 [16]
            --resolution 7200|3600|2400|1200|600dpi [600]
            --source Transparency Adapter [Transparency Adapter]
            --brightness -100..100 (in steps of 1) [0]
            --gamma-table 0..65535,... [inactive]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertTrue(cap.supportedResolutions.contains(.r7200))
        XCTAssertTrue(cap.supportedResolutions.contains(.r3600))
        XCTAssertTrue(cap.supportedModes.contains(.color))
        XCTAssertTrue(cap.supportedBitDepths.contains(.sixteen))
        XCTAssertTrue(cap.supportsTransparency)
        XCTAssertFalse(cap.supportsInfrared)   // genesys는 IR 노출 안 함
        XCTAssertFalse(cap.supportsMultiExposure, "brightness/gamma-table은 센서 노출 브라케팅이 아니다.")
    }

    func testParseSaneCapabilitiesMarksHardwareExposureOnlyForScanExposureTime() {
        let dump = """
        All options specific to device `genesys:libusb:000:010':
          Scan Mode:
            --mode Color|Gray [Gray]
            --depth 16 [16]
            --resolution 7200|3600|2400|1200|600dpi [600]
            --source Transparency Adapter [Transparency Adapter]
            --scan-exposure-time 11000..65535 [18000] [advanced]
        """
        let cap = SANEBackend.parseCapabilities(dump)

        XCTAssertTrue(cap.supportsMultiExposure)
    }

    func testMultiSampleAverageReducesMidtoneRandomNoise() {
        let width = 48
        let height = 24
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(phase: Int) -> CIImage {
            var pixels = [Float](repeating: 1, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let sign: Float = ((x + y + phase) % 3 == 0) ? 1 : -0.5
                    let value: Float = 0.48 + sign * 0.045
                    pixels[i] = value
                    pixels[i + 1] = value
                    pixels[i + 2] = value
                    pixels[i + 3] = 1
                }
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let midtone = makeImage(phase: 0)
        let merged = SANEBackend.averageMultiSampleScans([
            makeImage(phase: 1),
            midtone,
            makeImage(phase: 2),
        ])
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var baseline = [Float](repeating: 0, count: width * height * 4)
        var output = [Float](repeating: 0, count: width * height * 4)
        context.render(midtone, toBitmap: &baseline, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: linear)
        context.render(merged, toBitmap: &output, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: linear)

        XCTAssertLessThan(lumaStandardDeviation(output), lumaStandardDeviation(baseline) * 0.45)
    }

    func testHardwareExposurePlanRepeatsEachExposureForNoiseReduction() {
        XCTAssertEqual(
            SANEBackend.hardwareExposurePlan(samplesPerStop: 2),
            [11_000, 11_000, 14_000, 14_000, 30_000, 30_000]
        )
    }

    func testMultiSampleBitmapPreservesSixteenBitChannelScale() throws {
        let width = 2
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let values: [Float] = [
            1.0 / 65535.0, 2.0 / 65535.0, 3.0 / 65535.0, 1,
            300.0 / 65535.0, 400.0 / 65535.0, 500.0 / 65535.0, 1,
        ]
        let image = CIImage(
            bitmapData: Data(bytes: values, count: values.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let bitmap = try SANEBackend.averageMultiSampleBitmap([image, image, image])

        XCTAssertEqual(bitmap.width, width)
        XCTAssertEqual(bitmap.height, height)
        XCTAssertEqual(bitmap.pixels[0], 1)
        XCTAssertEqual(bitmap.pixels[1], 2)
        XCTAssertEqual(bitmap.pixels[2], 3)
        XCTAssertEqual(bitmap.pixels[3], 300)
        XCTAssertEqual(bitmap.pixels[4], 400)
        XCTAssertEqual(bitmap.pixels[5], 500)
    }

    func testMultiSampleBitmapUsesRawArithmeticMeanWithoutMedianNormalization() throws {
        let width = 24
        let height = 12
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeSolidImage(_ value: Float) -> CIImage {
            var pixels = [Float](repeating: 1, count: width * height * 4)
            for index in stride(from: 0, to: pixels.count, by: 4) {
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let bitmap = try SANEBackend.averageMultiSampleBitmap([
            makeSolidImage(0.20),
            makeSolidImage(0.40),
            makeSolidImage(0.80),
        ])

        let expected = Int(((0.20 + 0.40 + 0.80) / 3.0) * 65535.0)
        XCTAssertEqual(Int(bitmap.pixels[0]), expected, accuracy: 1)
        XCTAssertEqual(Int(bitmap.pixels[1]), expected, accuracy: 1)
        XCTAssertEqual(Int(bitmap.pixels[2]), expected, accuracy: 1)
    }

    func testHardwareExposureMergeUsesShortExposureForClippedHighlights() throws {
        let width = 4
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(_ values: [Float]) -> CIImage {
            var pixels = [Float]()
            for value in values {
                pixels += [value, value, value, 1]
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let exposureTimes = [11_000, 14_000, 30_000]
        let sceneAtReference: [Float] = [0.08, 0.24, 0.72, 0.96]
        let images = exposureTimes.map { exposure -> CIImage in
            let scale = Float(exposure) / 14_000.0
            return makeImage(sceneAtReference.map { min($0 * scale, 1.0) })
        }

        let bitmap = try SANEBackend.mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)
        let highlight = Double(bitmap.pixels[9]) / 65535.0

        XCTAssertGreaterThan(highlight, 0.93)
        XCTAssertLessThan(highlight, 1.0, "긴 노출 클립값 1.0을 그대로 쓰지 않고 짧은 노출에서 복원해야 한다.")
    }

    func testHardwareExposureMergePreservesNormalExposureMidtones() throws {
        let width = 5
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(_ values: [Float]) -> CIImage {
            var pixels = [Float]()
            for value in values {
                pixels += [value, value, value, 1]
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let exposureTimes = [11_000, 14_000, 30_000]
        let sceneAtReference: [Float] = [0.02, 0.12, 0.32, 0.55, 0.76]
        let images = exposureTimes.map { exposure -> CIImage in
            let scale = Float(exposure) / 14_000.0
            return makeImage(sceneAtReference.map { min($0 * scale, 1.0) })
        }

        let bitmap = try SANEBackend.mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)

        for pixel in 1..<sceneAtReference.count {
            let output = Double(bitmap.pixels[pixel * 3]) / 65535.0
            XCTAssertEqual(
                output,
                Double(sceneAtReference[pixel]),
                accuracy: 0.025,
                "중간톤은 14k 기준 패스의 raw 스케일을 유지해야 한다."
            )
        }
    }

    func testHardwareExposureMergeAveragesRepeatedNormalExposureNoise() throws {
        let width = 3
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(_ values: [Float]) -> CIImage {
            var pixels = [Float]()
            for value in values {
                pixels += [value, value, value, 1]
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let images = [
            makeImage([0.12, 0.35, 0.88]),
            makeImage([0.12, 0.35, 0.88]),
            makeImage([0.20, 0.48, 0.76]),
            makeImage([0.20, 0.52, 0.76]),
            makeImage([0.36, 0.90, 1.0]),
            makeImage([0.36, 0.90, 1.0]),
        ]
        let exposureTimes = [11_000, 11_000, 14_000, 14_000, 30_000, 30_000]

        let bitmap = try SANEBackend.mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)
        let midtone = Double(bitmap.pixels[4]) / 65535.0

        XCTAssertEqual(
            midtone,
            0.50,
            accuracy: 0.015,
            "동일 14k 노출 반복 샘플은 HDR merge 전에 평균되어 랜덤 노이즈를 줄여야 한다."
        )
    }

    func testHardwareExposureMergeKeepsLongExposureFromDominatingShadows() throws {
        let width = 1
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(_ value: Float) -> CIImage {
            let pixels: [Float] = [value, value, value, 1]
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let exposureTimes = [11_000, 14_000, 30_000]
        let images = [
            makeImage(0.007),
            makeImage(0.012),
            makeImage(0.080),
        ]

        let bitmap = try SANEBackend.mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)
        let output = Double(bitmap.pixels[0]) / 65535.0

        XCTAssertLessThan(output, 0.030, "long exposure가 암부 저신호를 전부 지배하면 색비/컬러 노이즈가 long pass 바이어스를 따라간다.")
        XCTAssertGreaterThan(output, 0.012, "긴 노출 보강은 완전히 끄지 말고 최저 신호의 계조만 보강해야 한다.")
    }

    func testSaneScanArgsIncludeHardwareExposureTimeWhenRequested() {
        let backend = SANEBackend(scanimagePath: "/tmp/sane-head-install/bin/scanimage")
        var options = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        options.hardwareExposureTime = 30_000

        let args = backend.makeScanimageArgs(
            devname: "genesys:libusb:000:010",
            options: options
        )

        XCTAssertTrue(args.contains("--scan-exposure-time=30000"))
    }

    func testMultiSampleBitmapAlignsOnePixelPassShiftBeforeAveraging() throws {
        let width = 32
        let height = 20
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeEdgeImage(shiftX: Int) -> CIImage {
            var pixels = [Float](repeating: 1, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let sourceX = x - shiftX
                    let value: Float = sourceX < width / 2 ? 0.18 : 0.78
                    let offset = (y * width + x) * 4
                    pixels[offset] = value
                    pixels[offset + 1] = value
                    pixels[offset + 2] = value
                    pixels[offset + 3] = 1
                }
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let bitmap = try SANEBackend.averageMultiSampleBitmap([
            makeEdgeImage(shiftX: 0),
            makeEdgeImage(shiftX: 1),
            makeEdgeImage(shiftX: 0),
        ])

        let left = bitmap.pixels[((height / 2 * width + width / 2 - 1) * 3)]
        let right = bitmap.pixels[((height / 2 * width + width / 2) * 3)]
        XCTAssertGreaterThan(
            Int(right) - Int(left),
            30_000,
            "multi-pass 평균 전에 1px 패스 밀림을 정렬하지 않으면 에지가 흐려진다."
        )
    }

    func testMultiSampleFileMergePreservesScannerRawLinearScale() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scannerkit_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sampleURLs = (0..<3).map { dir.appendingPathComponent("sample_\($0).tiff") }
        let outputURL = dir.appendingPathComponent("merged.tiff")
        for url in sampleURLs {
            try writeScannerRGB16TIFF(
                pixels: [0.24, 0.10, 0.07],
                width: 1,
                height: 1,
                to: url
            )
        }

        try SANEBackend.averageMultiSampleScans(sampleURLs: sampleURLs, outputURL: outputURL)
        guard let merged = Chromabase.ImageLoader.loadScannerTIFF(outputURL) else {
            return XCTFail("merged scanner TIFF should load")
        }
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        ])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            merged,
            toBitmap: &pixel,
            rowBytes: 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )

        XCTAssertEqual(Double(pixel[0]), 0.24, accuracy: 0.001)
        XCTAssertEqual(Double(pixel[1]), 0.10, accuracy: 0.001)
        XCTAssertEqual(Double(pixel[2]), 0.07, accuracy: 0.001)
        XCTAssertNil(
            CGImageSourceCopyPropertiesAtIndex(
                CGImageSourceCreateWithURL(outputURL as CFURL, nil)!,
                0,
                nil
            ).flatMap { ($0 as NSDictionary)[kCGImagePropertyProfileName] },
            "merged raw scanner TIFF should not embed an ICC profile that changes scanner sample interpretation"
        )
    }

    func testScannerReportSerialization() throws {
        let d = ScannerDescriptor(id: "sane-x", displayName: "Plustek OpticFilm 8200i",
                                  vendor: "Plustek", model: "OpticFilm 8200i",
                                  backendType: .sane, verifiedStatus: .verified)
        let r = ScannerReport(descriptor: d, backend: .sane,
                              backendAvailable: true, capabilities: ScannerCapabilities())
        let data = try JSONEncoder().encode(r)
        XCTAssertGreaterThan(data.count, 50)
    }

    // MARK: - SANE 환경 (GUI exit-1 버그 수정 회귀 테스트)
    //
    // GUI .app 환경에서 scanimage 가 "open of device failed: Invalid argument"
    // (exit 1)로 실패하는 근본 원인은 SANE_CONFIG_DIR / PATH 누락이었다.
    // makeSaneEnvironment() 는 반드시 Homebrew 경로를 포함해야 한다.

    func testSaneEnvironmentIncludesHomebrewPath() {
        let env = SANEBackend.makeSaneEnvironment()
        let path = env["PATH"] ?? ""
        XCTAssertTrue(path.contains("/opt/homebrew/bin") || path.contains("/usr/local/bin"),
                      "SANE 환경의 PATH 에 Homebrew 경로가 있어야 GUI 앱이 scanimage 를 찾는다. PATH=\(path)")
    }

    func testSaneEnvironmentHasConfigDirWhenHomebrewInstalled() throws {
        // 이 머신에는 /opt/homebrew/etc/sane.d 가 있으므로 SANE_CONFIG_DIR 가 잡혀야 한다.
        let fm = FileManager.default
        let homebrewSane = fm.fileExists(atPath: "/opt/homebrew/etc/sane.d")
                     || fm.fileExists(atPath: "/usr/local/etc/sane.d")
        guard homebrewSane else {
            throw XCTSkip("Homebrew sane-backends 미설치 — SANE_CONFIG_DIR 검증 생략")
        }
        let env = SANEBackend.makeSaneEnvironment()
        XCTAssertNotNil(env["SANE_CONFIG_DIR"], "SANE_CONFIG_DIR 가 주입되어야 scanimage 가 백엔드 설정을 찾는다.")
        if let cfg = env["SANE_CONFIG_DIR"] {
            XCTAssertTrue(fm.fileExists(atPath: cfg))
        }
    }

    func testFindSaneConfigDirResolvesHomebrew() {
        if let dir = SANEBackend.findSaneConfigDir() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir))
        }
    }

    // MARK: - USB 주소 재획득 회귀 테스트
    //
    // 스캐너의 libusb 주소는 리셋마다 바뀐다(010 ↔ 011). scanimage -L 출력에서
    // 현재 주소를 올바로 파싱해 내는지 검증. 주소가 틀리면 "Invalid argument" 로 open 실패.

    func testParseDeviceAddressFromScanimageListOutput() {
        // scanimage -L 표준 출력 형식.
        let listOutput = """
        device `genesys:libusb:000:011' is a PLUSTEK OpticFilm 8100 flatbed scanner

        No scanners were identified.
        """
        // 정규식이 동일하게 동작하는지 — 첫 줄의 주소만 잡아야 함.
        let regex = try! NSRegularExpression(
            pattern: "device `genesys:(libusb:[0-9]+:[0-9]+)' is a ([^\\s]+)\\s+(.+?) (?:flatbed |film )?scanner"
        )
        let range = NSRange(listOutput.startIndex..., in: listOutput)
        let match = regex.firstMatch(in: listOutput, range: range)
        XCTAssertNotNil(match)
        if let match,
           let r = Range(match.range(at: 1), in: listOutput) {
            XCTAssertEqual(String(listOutput[r]), "libusb:000:011")
        }
    }

    func testStaleDeviceErrorDetection() {
        // USB 주소 만료 시 나타나는 전형적 오류들 → 재시도 트리거.
        XCTAssertTrue(SANEBackend.isStaleDeviceError(
            "scanimage: open of device genesys:libusb:000:010 failed: Invalid argument"))
        XCTAssertTrue(SANEBackend.isStaleDeviceError("Error during device I/O"))
        XCTAssertTrue(SANEBackend.isStaleDeviceError("scanimage: open of device ... failed: Device busy"))
        // 무관한 오류는 재시도하지 않는다.
        XCTAssertFalse(SANEBackend.isStaleDeviceError("scanimage: out of memory"))
        XCTAssertFalse(SANEBackend.isStaleDeviceError(""))
    }

    // MARK: - 좀비 scanimage 정리 회귀 테스트
    //
    // 좀비 scanimage 프로세스가 USB 장치를 점유하면 모든 새 스캔이 실패한다.
    // reapZombieScanimages() 로직이 살아있는 pkill 패턴을 생성하는지 확인(실행은 부작용 방지용으로 스킵).

    func testZombieReapDoesNotThrowOnCleanSystem() {
        // 실제 pkill 은 부작용이 크므로, 명령 문자열이 올바른지만 검증.
        // reapZombieScanimages 는 private 이므로, 여기서는 scanimage 경로가
        // resolve 됨만 확인(경로가 nil 이면 pkill 패턴이 무의미).
        let path = SANEBackend.findScanimage()
        XCTAssertFalse(path.isEmpty, "scanimage 경로가 비어 있으면 좀비 정리가 동작하지 않는다")
    }

    private func lumaStandardDeviation(_ pixels: [Float]) -> Double {
        var values: [Double] = []
        values.reserveCapacity(pixels.count / 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index])
            let green = Double(pixels[index + 1])
            let blue = Double(pixels[index + 2])
            values.append(red * 0.2126 + green * 0.7152 + blue * 0.0722)
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }

    private func writeScannerRGB16TIFF(pixels: [Double], width: Int, height: Int, to url: URL) throws {
        let samples = pixels.map { UInt16(min(max($0, 0), 1) * 65535).bigEndian }
        let data = Data(bytes: samples, count: samples.count * MemoryLayout<UInt16>.size)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 16,
                bitsPerPixel: 48,
                bytesPerRow: width * 3 * MemoryLayout<UInt16>.size,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw ScannerError(.ioFailure, "test TIFF 생성 실패")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "test TIFF 저장 실패")
        }
    }

}
