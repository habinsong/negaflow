import XCTest
import Foundation
import Chromabase
@testable import negaflowApp

@MainActor
final class AutoAdjustRealInputTests: XCTestCase {
    func testRealInputGammaScaleAndAutomaticCorrectionsWhenRequested() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let source = env["NEGAFLOW_AUTO_INPUT_QA"], let output = env["NEGAFLOW_AUTO_INPUT_OUTPUT"] else {
            throw XCTSkip("Set NEGAFLOW_AUTO_INPUT_QA and NEGAFLOW_AUTO_INPUT_OUTPUT for the real TIFF matrix.")
        }
        let url = URL(fileURLWithPath: source)
        let before = try Data(contentsOf: url)
        let model = AppModel()
        let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative, sourceKind: .importedFile)
        model.frames = [frame]
        defer { model.frames = [] }
        var rows: [[String: Any]] = []
        for gamma in [1.8, 2.4] {
            for scale in [0.75, 1.25] {
                for levels in [false, true] {
                    for color in [false, true] {
                        var params = DevelopParameters()
                        params.inputGamma = try .power(gamma); params.baseScale = try FilmBaseScale(scale)
                        params.autoLevels = levels; params.autoNeutralBalance = color
                        frame.params = params
                        await model.autoTone(frame).value
                        let tone = frame.params
                        await model.autoTone(frame).value
                        XCTAssertEqual(frame.params, tone)
                        await model.autoWhiteBalance(frame).value
                        let wb = frame.params
                        await model.autoWhiteBalance(frame).value
                        XCTAssertEqual(frame.params, wb)
                        XCTAssertEqual(wb.inputGamma.value, gamma)
                        XCTAssertEqual(wb.baseScale.value, scale)
                        XCTAssertEqual(wb.autoLevels, levels); XCTAssertEqual(wb.autoNeutralBalance, color)
                        let values = [wb.exposure, wb.contrast, wb.whites, wb.blacks, wb.density, wb.warmth, wb.tint]
                        XCTAssertTrue(values.allSatisfy(\.isFinite))
                        rows.append(["gamma": gamma, "baseScale": scale, "autoLevels": levels, "autoColor": color,
                            "exposure": wb.exposure, "contrast": wb.contrast, "whites": wb.whites, "blacks": wb.blacks,
                            "density": wb.density, "warmth": wb.warmth, "tint": wb.tint])
                    }
                }
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: output), options: .atomic)
    }
}
