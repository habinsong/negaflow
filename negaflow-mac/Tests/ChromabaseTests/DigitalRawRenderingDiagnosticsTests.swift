import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// 디지털 RAW 현상이 어둡고 밋밋한 원인을 숫자로 좁히는 opt-in 진단 하네스.
///
/// ```
/// NEGAFLOW_RAW_DIAG_DIRS=/Users/songhabin/tiff_test/digital_color:/Users/songhabin/Downloads \
/// swift test --filter DigitalRawRenderingDiagnosticsTests
/// ```
///
/// 판정은 눈이 아니라 sRGB 표시 도메인 백분위/채도로 한다.
final class DigitalRawRenderingDiagnosticsTests: XCTestCase {

    struct Stats {
        let p1: Double, p5: Double, p50: Double, p95: Double, p99: Double
        let mean: Double
        let aboveNinety: Double        // 휘도 0.9 초과 화소 비율(%)
        let meanSaturation: Double     // HSV S 평균
        let rmsContrast: Double
    }

    /// CIRAWFilter 의 손대지 않은 기본값을 확인한다 — "Apple 기본 = boost 1.0" 이 사실인지.
    func testReportsCIRAWFilterDefaults() throws {
        let files = try Self.rawFiles()
        try XCTSkipIf(files.isEmpty, "NEGAFLOW_RAW_DIAG_DIRS 를 지정하면 진단을 실행합니다.")
        let file = files[0]
        let filter = try XCTUnwrap(CIRAWFilter(imageURL: file))
        print("[raw-defaults] \(file.lastPathComponent) boostAmount=\(filter.boostAmount) "
            + "boostShadowAmount=\(filter.shadowBias) exposure=\(filter.exposure) "
            + "baselineExposure=\(filter.baselineExposure) decoder=\(filter.decoderVersion.rawValue)")
    }

    /// 포맷별로 boost 0(현재) / boost 1(Apple 기본) 을 재고, 현상 파이프라인이 그 값을 바꾸는지 본다.
    func testMeasuresEveryRawFormat() throws {
        let files = try Self.rawFiles()
        try XCTSkipIf(files.isEmpty, "NEGAFLOW_RAW_DIAG_DIRS 를 지정하면 진단을 실행합니다.")

        let engine = ChromabaseEngine()
        var rows: [String] = [
            "ext  file                                           case                p5    p50    p95    p99   >0.9%    sat    rms"
        ]
        var failures: [String] = []
        var deltaStops: [String: [Double]] = [:]

        print(rows[0])
        for file in files {
            let ext = file.pathExtension.lowercased()
            // 파일마다 CI 중간 버퍼를 즉시 반납한다 — 54개를 한 풀에 쌓으면 죽는다.
            let outcome: (zero: Stats, one: Stats, developed: Stats)? = autoreleasepool {
                guard let zero = Self.decode(file, boost: 0),
                      let one = Self.decode(file, boost: 1) else { return nil }
                var params = DevelopParameters()
                params.filmType = .colorPositive
                params.isDigitalSource = true
                params.developTarget = .main
                return (
                    Self.measure(zero),
                    Self.measure(one),
                    // 현상이 디코드 결과를 바꾸는지 — 바뀌지 않으면 패스스루가 증명된다.
                    Self.measure(engine.develop(image: zero, base: nil, params: params))
                )
            }
            guard let outcome else {
                failures.append("\(file.lastPathComponent): 디코드 실패")
                continue
            }
            for (label, stats) in [
                ("decode boost0", outcome.zero),
                ("decode boost1", outcome.one),
                ("develop digital", outcome.developed),
            ] {
                let line = Self.row(ext, file, label, stats)
                rows.append(line)
                print(line)
            }
            fflush(stdout)

            // 중간톤 밝기 차이를 스톱으로 환산(sRGB p50 → linear).
            let stops = log2(
                max(1e-6, Self.linear(outcome.one.p50)) / max(1e-6, Self.linear(outcome.zero.p50))
            )
            deltaStops[ext, default: []].append(stops)
        }

        print("\n[포맷별 boost1 − boost0 중간톤 차이(stop)]")
        for ext in deltaStops.keys.sorted() {
            let values = deltaStops[ext]!.sorted()
            let median = values[values.count / 2]
            print(String(format: "  %-4s n=%2d median=%+.2f min=%+.2f max=%+.2f",
                         (ext as NSString).utf8String!, values.count, median,
                         values.first!, values.last!))
        }
        if !failures.isEmpty { print("\n[디코드 실패]\n  " + failures.joined(separator: "\n  ")) }
    }

    /// 수정 후 검증: 앱이 실제로 쓰는 로더가 의도대로 갈라지는가 + 카메라 JPEG 과의 격차.
    func testAppLoaderHonoursRenderingIntent() throws {
        let files = try Self.rawFiles()
        try XCTSkipIf(files.isEmpty, "NEGAFLOW_RAW_DIAG_DIRS 를 지정하면 진단을 실행합니다.")
        let engine = ChromabaseEngine()

        for file in files {
            autoreleasepool {
                guard let film = ImageLoader.loadImported(file) else { return }
                guard let digital = ImageLoader.loadImported(
                    file, rawRendering: .forDigitalSource(true)
                ) else { return }

                var params = DevelopParameters()
                params.filmType = .colorPositive
                params.isDigitalSource = true
                params.developTarget = .main
                let developed = Self.measure(
                    engine.develop(image: digital, base: nil, params: params)
                )
                let filmStats = Self.measure(film)
                print(Self.row(file.pathExtension.lowercased(), file, "film(default)", filmStats))
                print(Self.row(file.pathExtension.lowercased(), file, "digital develop", developed))

                // 필름 기본 경로는 linear 유지 — 톤 커브가 붙으면 반전이 무너진다.
                XCTAssertEqual(
                    Self.measure(ImageLoader.loadRAWControlled(file, boost: 0).map { $0 } ?? film).p50,
                    filmStats.p50,
                    accuracy: 0.002,
                    "\(file.lastPathComponent): 기본 로더가 더 이상 linear 가 아니다"
                )
                // 디지털 경로는 표시용 렌더링을 받아 명부/대비가 살아나야 한다.
                XCTAssertGreaterThan(
                    developed.rmsContrast, filmStats.rmsContrast * 1.05,
                    "\(file.lastPathComponent): 디지털 경로 대비가 개선되지 않았다"
                )

                let jpeg = file.deletingPathExtension().appendingPathExtension("JPG")
                if FileManager.default.fileExists(atPath: jpeg.path),
                   let reference = ImageLoader.loadStandard(jpeg) {
                    let ref = Self.measure(reference)
                    print(Self.row(file.pathExtension.lowercased(), file, "camera JPEG", ref))
                    let before = log2(max(1e-6, Self.linear(ref.p50)) / max(1e-6, Self.linear(filmStats.p50)))
                    let after = log2(max(1e-6, Self.linear(ref.p50)) / max(1e-6, Self.linear(developed.p50)))
                    print(String(format: "  → 카메라 JPEG 대비 중간톤 격차: %+.2f stop → %+.2f stop", before, after))
                }
                fflush(stdout)
            }
        }
    }

    // MARK: 입력

    static func rawFiles() throws -> [URL] {
        guard let raw = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_DIAG_DIRS"],
              !raw.isEmpty else { return [] }
        var files: [URL] = []
        for path in raw.split(separator: ":") {
            let directory = URL(fileURLWithPath: String(path), isDirectory: true)
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )) ?? []
            files += contents.filter {
                ImageLoader.rawExtensions.contains($0.pathExtension.lowercased())
            }
        }
        return files.sorted {
            ($0.pathExtension.lowercased(), $0.lastPathComponent)
                < ($1.pathExtension.lowercased(), $1.lastPathComponent)
        }
    }

    /// 진단 속도를 위해 축소 디코드한다. boost 는 톤 커브라 배율과 무관하다.
    static func decode(_ url: URL, boost: Float) -> CIImage? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        filter.boostAmount = boost
        filter.scaleFactor = 0.25
        return filter.outputImage
    }

    static func linear(_ srgb: Double) -> Double {
        srgb <= 0.04045 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
    }

    static func row(_ ext: String, _ file: URL, _ label: String, _ s: Stats) -> String {
        String(
            format: "%-4s %-46s %-16s %6.3f %6.3f %6.3f %6.3f %6.2f%% %6.3f %6.3f",
            (ext as NSString).utf8String!,
            (String(file.lastPathComponent.prefix(46)) as NSString).utf8String!,
            (label as NSString).utf8String!,
            s.p5, s.p50, s.p95, s.p99, s.aboveNinety, s.meanSaturation, s.rmsContrast
        )
    }

    // MARK: 측정

    /// 작업 이미지를 sRGB 8bit 표시 도메인으로 렌더해 통계를 낸다(긴 변 384 프록시).
    static func measure(_ image: CIImage) -> Stats {
        let extent = image.extent.integral
        let scale = min(1, 384 / max(extent.width, extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let target = scaled.extent.integral
        let width = max(1, Int(target.width)), height = max(1, Int(target.height))
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: srgb,
        ])
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(scaled, toBitmap: buffer.baseAddress!, rowBytes: width * 4,
                           bounds: target, format: .RGBA8, colorSpace: srgb)
        }

        var luma = [Double](); luma.reserveCapacity(width * height)
        var saturationSum = 0.0
        var bright = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let r = Double(bytes[index]) / 255
            let g = Double(bytes[index + 1]) / 255
            let b = Double(bytes[index + 2]) / 255
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            luma.append(y)
            if y > 0.9 { bright += 1 }
            let mx = max(r, max(g, b)), mn = min(r, min(g, b))
            saturationSum += mx > 0 ? (mx - mn) / mx : 0
        }
        luma.sort()
        let count = Double(luma.count)
        let mean = luma.reduce(0, +) / count
        let variance = luma.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count
        func percentile(_ q: Double) -> Double {
            luma[min(luma.count - 1, max(0, Int(q * (count - 1))))]
        }
        return Stats(
            p1: percentile(0.01), p5: percentile(0.05), p50: percentile(0.5),
            p95: percentile(0.95), p99: percentile(0.99),
            mean: mean,
            aboveNinety: 100 * Double(bright) / count,
            meanSaturation: saturationSum / count,
            rmsContrast: variance.squareRoot()
        )
    }
}
