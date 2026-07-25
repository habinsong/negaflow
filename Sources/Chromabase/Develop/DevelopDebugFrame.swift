import CoreImage
import Foundation

public enum DevelopDebugStage: String, Codable, Sendable, CaseIterable {
    case afterInversion
    case afterAutoLevels
    case afterPrintBase
    case finalTone

    public var displayName: String {
        switch self {
        case .afterInversion: return "After Inversion"
        case .afterAutoLevels: return "After AutoLevels"
        case .afterPrintBase: return "After PrintBase"
        case .finalTone: return "Final Tone"
        }
    }
}

public struct DevelopDebugMetrics: Sendable {
    public let baseRGB: SIMD3<Double>?
    public let dmin: SIMD3<Double>?
    public let dmaxNorm: SIMD3<Double>?
    public let blackInput: SIMD3<Double>?

    public init(
        baseRGB: SIMD3<Double>?,
        dmin: SIMD3<Double>?,
        dmaxNorm: SIMD3<Double>?,
        blackInput: SIMD3<Double>?
    ) {
        self.baseRGB = baseRGB
        self.dmin = dmin
        self.dmaxNorm = dmaxNorm
        self.blackInput = blackInput
    }
}

public struct DevelopDebugFrame: @unchecked Sendable {
    public let stage: DevelopDebugStage
    public let image: CIImage
    public let metrics: DevelopDebugMetrics?

    public init(stage: DevelopDebugStage, image: CIImage, metrics: DevelopDebugMetrics?) {
        self.stage = stage
        self.image = image
        self.metrics = metrics
    }
}
