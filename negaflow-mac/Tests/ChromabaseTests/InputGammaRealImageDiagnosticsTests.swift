import XCTest
import CoreImage
import ImageIO
@testable import Chromabase

final class InputGammaRealImageDiagnosticsTests: XCTestCase {
    func testRenderGammaSweepWhenRequested() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["NEGAFLOW_GAMMA_QA_INPUT"], let output = env["NEGAFLOW_GAMMA_QA_OUTPUT"] else {
            throw XCTSkip("Set NEGAFLOW_GAMMA_QA_INPUT and NEGAFLOW_GAMMA_QA_OUTPUT for real-image diagnostics.")
        }
        let url = URL(fileURLWithPath: path), directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let info = try ImageLoader.inputGammaSourceInfo(url)
        print("GAMMA_SOURCE \(info)")
        let engine = ChromabaseEngine()
        var rows: [[String: Any]] = []
        for value in [0.1, 0.22, 0.32, 0.33, 0.34, 0.5, 1, 1.8, 2.2, 4] {
            try autoreleasepool {
                let gamma = try InputGammaInterpretation.power(value)
                let raw = try XCTUnwrap(ImageLoader.loadImportedPreview(url, maxDimension: 640,
                    highResolutionThreshold: 0, inputGamma: gamma)).image
                for stock in ["auto", "vision3-250d"] {
                    var params = DevelopParameters()
                    params.filmType = .colorNegative
                    params.developTarget = .main
                    params.inputGamma = gamma
                    params.baseEstimationMode = stock == "auto" ? .auto : .preset
                    params.filmStockDminID = stock == "auto" ? nil : stock
                    let base = try XCTUnwrap(engine.estimateFilmBase(in: raw, mode: params.baseEstimationMode,
                        filmStockDminID: params.filmStockDminID))
                    let stats = try XCTUnwrap(NegativeInversion.sampleStats(raw, base: base))
                    var measurements = DevelopSceneMeasurements()
                    try InputGammaRenderReference.prepare(source: url, params: params, measurements: &measurements)
                    let result = engine.developScanner(image: raw, base: base, params: params, measurements: &measurements)
                    let cg = try XCTUnwrap(ChromabaseEngine.sharedLinearRenderContext.createCGImage(result,
                        from: result.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
                    let name = "\(stock)-\(String(format: "%.2f", value)).png"
                    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL,
                        "public.png" as CFString, 1, nil))
                    CGImageDestinationAddImage(destination, cg, nil)
                    XCTAssertTrue(CGImageDestinationFinalize(destination))
                    let row: [String: Any] = ["gamma": value, "stock": stock, "file": name,
                        "base": [base.rgb.x, base.rgb.y, base.rgb.z],
                        "dmax": [stats.dmaxNorm.x, stats.dmaxNorm.y, stats.dmaxNorm.z], "midDensity": stats.midDensity,
                        "usedDmax": measurements.inversionStats.map { [$0.dmaxNorm.x, $0.dmaxNorm.y, $0.dmaxNorm.z] } ?? []]
                    rows.append(row)
                    print("GAMMA_SWEEP \(row)")
                }
            }
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("sweep.json"))
    }
}
