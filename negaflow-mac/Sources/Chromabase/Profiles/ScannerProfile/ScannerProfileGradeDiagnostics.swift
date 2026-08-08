import Foundation

public struct ScannerProfileGradeDiagnostics: Codable, Sendable, Equatable {
    public var profileID: String
    public var sceneBucket: String?
    public var toneCorrection: String
    public var neutralCorrection: String
    public var chromaCorrection: String
    public var clipGuardTriggered: Bool
    public var toneGamma: Double?
    public var contrastAmount: Double?
    public var saturationAmount: Double?
    public var vibranceAmount: Double?
    public var redGain: Double?
    public var greenGain: Double?
    public var blueGain: Double?

    public init(profile: ScannerProfile) {
        let parameters = ScannerProfileGrade.parameters(for: profile)
        profileID = profile.id
        // 현재 grade는 scene classifier를 사용하지 않으므로 임의의 첫 bucket을 선택했다고 기록하지 않는다.
        sceneBucket = nil
        toneCorrection = String(
            format: "gamma=%.6f;contrast=%.6f;curve=%.6f,%.6f,%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            parameters.gamma,
            parameters.contrastAmount,
            parameters.shadowPoint,
            parameters.midPoint,
            parameters.highlightPoint
        )
        neutralCorrection = String(
            format: "rgb=%.6f,%.6f,%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            parameters.redGain,
            parameters.greenGain,
            parameters.blueGain
        )
        chromaCorrection = String(
            format: "saturation=%.6f;vibrance=%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            parameters.saturation,
            parameters.vibrance
        )
        clipGuardTriggered = parameters.parameterClampTriggered
        toneGamma = parameters.gamma
        contrastAmount = parameters.contrastAmount
        saturationAmount = parameters.saturation
        vibranceAmount = parameters.vibrance
        redGain = parameters.redGain
        greenGain = parameters.greenGain
        blueGain = parameters.blueGain
    }
}
