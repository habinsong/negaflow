import Foundation

extension ScannerNoiseProfile {
    public var isStructurallyValid: Bool {
        schemaVersion == 1
            && !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && captureKey.isStructurallyValid
            && measurementFrameCount >= 3
            && Self.isSHA256(calibrationCorpusSHA256)
            && model.isStructurallyValid
            && tuning.isStructurallyValid
            && (validationStatus != .holdoutValidated
                || holdoutCorpusSHA256.map(Self.isSHA256) == true)
    }

    public var allowsAutomaticUse: Bool {
        validationStatus == .holdoutValidated && isStructurallyValid
    }

    private static func isSHA256(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:") else { return false }
        let digest = value.dropFirst("sha256:".count)
        return digest.count == 64 && digest.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

private extension ScannerNoiseCaptureKey {
    var isStructurallyValid: Bool {
        !scannerVendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !scannerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && resolutionDPI > 0
            && [8, 16].contains(bitDepth)
            && !colorMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension ScannerNoiseModel {
    var isStructurallyValid: Bool {
        red.isStructurallyValid && green.isStructurallyValid && blue.isStructurallyValid
    }
}

private extension ScannerNoiseChannelModel {
    var isStructurallyValid: Bool {
        let values = [
            shotSlope,
            readIntercept,
            rSquared,
            observedSignalMinimum,
            observedSignalMaximum,
        ]
        return values.allSatisfy(\.isFinite)
            && shotSlope >= 0
            && readIntercept >= 0
            && (0...1).contains(rSquared)
            && (0...1).contains(observedSignalMinimum)
            && (0...1).contains(observedSignalMaximum)
            && observedSignalMinimum < observedSignalMaximum
            && observationCount > 0
    }
}

private extension ScannerNoiseReductionTuning {
    var isStructurallyValid: Bool {
        [chromaRadiusScale, shadowRadiusScale, lumaRadiusScale, strengthScale]
            .allSatisfy { $0.isFinite && (0...4).contains($0) }
    }
}
