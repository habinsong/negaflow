import Foundation

public enum ScannerNoiseProfileValidationStatus: String, Codable, Sendable {
    case draft
    case measured
    case holdoutValidated
}

public struct ScannerNoiseCaptureKey: Codable, Sendable, Equatable, Hashable {
    public let scannerVendor: String
    public let scannerModel: String
    public let resolutionDPI: Int
    public let bitDepth: Int
    public let colorMode: String
    public let multiExposure: Bool

    public init(
        scannerVendor: String,
        scannerModel: String,
        resolutionDPI: Int,
        bitDepth: Int,
        colorMode: String,
        multiExposure: Bool
    ) {
        self.scannerVendor = scannerVendor
        self.scannerModel = scannerModel
        self.resolutionDPI = resolutionDPI
        self.bitDepth = bitDepth
        self.colorMode = colorMode
        self.multiExposure = multiExposure
    }
}

public struct ScannerNoiseChannelModel: Codable, Sendable, Equatable {
    public let shotSlope: Double
    public let readIntercept: Double
    public let rSquared: Double
    public let observedSignalMinimum: Double
    public let observedSignalMaximum: Double
    public let observationCount: Int

    public init(
        shotSlope: Double,
        readIntercept: Double,
        rSquared: Double,
        observedSignalMinimum: Double,
        observedSignalMaximum: Double,
        observationCount: Int
    ) {
        self.shotSlope = shotSlope
        self.readIntercept = readIntercept
        self.rSquared = rSquared
        self.observedSignalMinimum = observedSignalMinimum
        self.observedSignalMaximum = observedSignalMaximum
        self.observationCount = observationCount
    }
}

public struct ScannerNoiseModel: Codable, Sendable, Equatable {
    public let red: ScannerNoiseChannelModel
    public let green: ScannerNoiseChannelModel
    public let blue: ScannerNoiseChannelModel

    public init(
        red: ScannerNoiseChannelModel,
        green: ScannerNoiseChannelModel,
        blue: ScannerNoiseChannelModel
    ) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct ScannerNoiseReductionTuning: Codable, Sendable, Equatable {
    public let chromaRadiusScale: Double
    public let shadowRadiusScale: Double
    public let lumaRadiusScale: Double
    public let strengthScale: Double

    public init(
        chromaRadiusScale: Double,
        shadowRadiusScale: Double,
        lumaRadiusScale: Double,
        strengthScale: Double
    ) {
        self.chromaRadiusScale = chromaRadiusScale
        self.shadowRadiusScale = shadowRadiusScale
        self.lumaRadiusScale = lumaRadiusScale
        self.strengthScale = strengthScale
    }

    static let generic = ScannerNoiseReductionTuning(
        chromaRadiusScale: 1,
        shadowRadiusScale: 1,
        lumaRadiusScale: 1,
        strengthScale: 1
    )
}

public struct ScannerNoiseProfile: Codable, Sendable, Equatable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let captureKey: ScannerNoiseCaptureKey
    public let validationStatus: ScannerNoiseProfileValidationStatus
    public let measurementFrameCount: Int
    public let calibrationCorpusSHA256: String
    public let holdoutCorpusSHA256: String?
    public let model: ScannerNoiseModel
    public let tuning: ScannerNoiseReductionTuning

    public init(
        schemaVersion: Int = 1,
        id: String,
        captureKey: ScannerNoiseCaptureKey,
        validationStatus: ScannerNoiseProfileValidationStatus,
        measurementFrameCount: Int,
        calibrationCorpusSHA256: String,
        holdoutCorpusSHA256: String?,
        model: ScannerNoiseModel,
        tuning: ScannerNoiseReductionTuning
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.captureKey = captureKey
        self.validationStatus = validationStatus
        self.measurementFrameCount = measurementFrameCount
        self.calibrationCorpusSHA256 = calibrationCorpusSHA256
        self.holdoutCorpusSHA256 = holdoutCorpusSHA256
        self.model = model
        self.tuning = tuning
    }
}
