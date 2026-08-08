import XCTest
@testable import Chromabase

final class ScannerNoiseProfileTests: XCTestCase {
    private let validHash = "sha256:" + String(repeating: "a", count: 64)

    func testRepeatedFlatFieldMeasurementFitsSignalDependentVariance() throws {
        let width = 96
        let slopes = SIMD3<Double>(0.0004, 0.0002, 0.0006)
        let intercepts = SIMD3<Double>(0.00001, 0.00002, 0.00003)
        let signs = [-1.0, 1.0, -1.0, 1.0]
        let frames = signs.map { sign in
            let pixels = (0..<width).map { index -> SIMD3<Float> in
                let signal = 0.1 + 0.8 * Double(index) / Double(width - 1)
                var value = SIMD3<Float>()
                for channel in 0..<3 {
                    let variance = slopes[channel] * signal + intercepts[channel]
                    let deviation = sqrt(variance * 0.75) * sign
                    value[channel] = Float(signal + deviation)
                }
                return value
            }
            return ScannerNoiseCalibrationFrame(width: width, height: 1, linearRGB: pixels)
        }

        let model = try ScannerNoiseProfileMeasurement.measure(frames: frames)

        for (channel, expectedSlope, expectedIntercept) in [
            (model.red, slopes.x, intercepts.x),
            (model.green, slopes.y, intercepts.y),
            (model.blue, slopes.z, intercepts.z),
        ] {
            XCTAssertEqual(channel.shotSlope, expectedSlope, accuracy: 0.000_002)
            XCTAssertEqual(channel.readIntercept, expectedIntercept, accuracy: 0.000_002)
            XCTAssertGreaterThan(channel.rSquared, 0.999)
            XCTAssertEqual(channel.observationCount, width)
        }
    }

    func testMeasurementRejectsInsufficientAndMismatchedInputs() {
        let frame = ScannerNoiseCalibrationFrame(
            width: 2,
            height: 2,
            linearRGB: Array(repeating: SIMD3<Float>(repeating: 0.5), count: 4)
        )
        XCTAssertThrowsError(try ScannerNoiseProfileMeasurement.measure(frames: [frame, frame])) {
            XCTAssertEqual($0 as? ScannerNoiseProfileMeasurementError, .insufficientFrames)
        }
        let mismatch = ScannerNoiseCalibrationFrame(
            width: 1,
            height: 1,
            linearRGB: [SIMD3<Float>(repeating: 0.5)]
        )
        XCTAssertThrowsError(
            try ScannerNoiseProfileMeasurement.measure(frames: [frame, frame, mismatch])
        ) {
            XCTAssertEqual($0 as? ScannerNoiseProfileMeasurementError, .invalidDimensions)
        }
    }

    func testAutomaticSelectionRequiresExactCaptureKeyAndHoldoutValidation() {
        let key = captureKey()
        let draft = profile(id: "draft", key: key, status: .draft)
        let measured = profile(id: "measured", key: key, status: .measured)
        let validated = profile(id: "validated", key: key, status: .holdoutValidated)

        XCTAssertTrue(draft.isStructurallyValid)
        XCTAssertFalse(draft.allowsAutomaticUse)
        XCTAssertFalse(measured.allowsAutomaticUse)
        XCTAssertTrue(validated.allowsAutomaticUse)
        XCTAssertEqual(
            ScannerNoiseProfileSelection.automaticProfile(
                for: key,
                profiles: [draft, measured, validated]
            )?.id,
            "validated"
        )

        let differentResolution = ScannerNoiseCaptureKey(
            scannerVendor: key.scannerVendor,
            scannerModel: key.scannerModel,
            resolutionDPI: 7200,
            bitDepth: key.bitDepth,
            colorMode: key.colorMode,
            multiExposure: key.multiExposure
        )
        XCTAssertNil(
            ScannerNoiseProfileSelection.automaticProfile(
                for: differentResolution,
                profiles: [validated]
            )
        )
        XCTAssertNil(
            ScannerNoiseProfileSelection.automaticProfile(
                for: key,
                profiles: [validated, profile(id: "duplicate", key: key, status: .holdoutValidated)]
            ),
            "같은 획득 조건의 자동 프로필이 중복되면 임의로 하나를 선택하면 안 됩니다"
        )
    }

    func testUnvalidatedProfileCannotChangeRuntimeTuning() {
        let key = captureKey()
        let draft = profile(id: "draft", key: key, status: .draft)
        let validated = profile(id: "validated", key: key, status: .holdoutValidated)

        XCTAssertEqual(ScannerNoiseReduction.tuning(for: draft), .generic)
        XCTAssertEqual(ScannerNoiseReduction.tuning(for: validated), validated.tuning)
    }

    func testMalformedEvidenceAndNonFiniteTuningAreRejected() {
        let key = captureKey()
        let malformedHash = ScannerNoiseProfile(
            id: "bad-hash",
            captureKey: key,
            validationStatus: .holdoutValidated,
            measurementFrameCount: 4,
            calibrationCorpusSHA256: "not-a-hash",
            holdoutCorpusSHA256: validHash,
            model: noiseModel(),
            tuning: tuning()
        )
        let nonFinite = ScannerNoiseProfile(
            id: "bad-tuning",
            captureKey: key,
            validationStatus: .holdoutValidated,
            measurementFrameCount: 4,
            calibrationCorpusSHA256: validHash,
            holdoutCorpusSHA256: validHash,
            model: noiseModel(),
            tuning: ScannerNoiseReductionTuning(
                chromaRadiusScale: .infinity,
                shadowRadiusScale: 1,
                lumaRadiusScale: 1,
                strengthScale: 1
            )
        )

        XCTAssertFalse(malformedHash.isStructurallyValid)
        XCTAssertFalse(nonFinite.isStructurallyValid)
        XCTAssertFalse(malformedHash.allowsAutomaticUse)
        XCTAssertFalse(nonFinite.allowsAutomaticUse)
    }

    private func captureKey() -> ScannerNoiseCaptureKey {
        ScannerNoiseCaptureKey(
            scannerVendor: "Measured Vendor",
            scannerModel: "Measured Model",
            resolutionDPI: 3600,
            bitDepth: 16,
            colorMode: "color",
            multiExposure: false
        )
    }

    private func profile(
        id: String,
        key: ScannerNoiseCaptureKey,
        status: ScannerNoiseProfileValidationStatus
    ) -> ScannerNoiseProfile {
        ScannerNoiseProfile(
            id: id,
            captureKey: key,
            validationStatus: status,
            measurementFrameCount: 4,
            calibrationCorpusSHA256: validHash,
            holdoutCorpusSHA256: status == .holdoutValidated ? validHash : nil,
            model: noiseModel(),
            tuning: tuning()
        )
    }

    private func noiseModel() -> ScannerNoiseModel {
        let channel = ScannerNoiseChannelModel(
            shotSlope: 0.0004,
            readIntercept: 0.00001,
            rSquared: 0.99,
            observedSignalMinimum: 0.1,
            observedSignalMaximum: 0.9,
            observationCount: 1000
        )
        return ScannerNoiseModel(red: channel, green: channel, blue: channel)
    }

    private func tuning() -> ScannerNoiseReductionTuning {
        ScannerNoiseReductionTuning(
            chromaRadiusScale: 1.1,
            shadowRadiusScale: 1.2,
            lumaRadiusScale: 0.9,
            strengthScale: 1.05
        )
    }
}
