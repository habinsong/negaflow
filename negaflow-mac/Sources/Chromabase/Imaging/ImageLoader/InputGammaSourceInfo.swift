import Foundation
import CoreGraphics
import ImageIO

/// 파일에 기록된 곡선을 우선하며 지원되는 무ICC RGB TIFF만 경계 표본으로 추정합니다.
public struct InputGammaSourceInfo: Equatable, Sendable {
    public enum Curve: Equatable, Sendable {
        case embeddedPower(Double)
        case embeddedProfile
        case estimatedPower(Double, evidence: Double, edgeCount: Int)
        case assumedLinear
        case assumedSRGB
        case decoder
    }

    public let curve: Curve
    public let manualError: InputGammaDecodeError?
    /// 수동 전환용 기본값을 파일에서 확인한 자동 감마로 표시하지 않습니다.
    public var automaticValue: Double? {
        switch curve {
        case .embeddedPower(let value), .estimatedPower(let value, _, _):
            return value.isFinite && value > 0 ? value : nil
        case .assumedLinear: return 1
        case .assumedSRGB: return 2.2
        case .embeddedProfile, .decoder: return nil
        }
    }

    public var manualSeed: Double {
        if case .embeddedPower(let value) = curve, InputGammaInterpretation.range.contains(value) { return value }
        if case .estimatedPower(let value, _, _) = curve { return value }
        return curve == .assumedLinear ? 1 : 2.2
    }
    public var estimatedGamma: InputGammaInterpretation? {
        if case .estimatedPower(let value, _, _) = curve { return try? .power(value) }
        return nil
    }
}

extension ImageLoader {
    public static func inputGammaSourceInfo(_ url: URL) throws -> InputGammaSourceInfo {
        try InputGammaSourceInfoCache.read(url) { try inspectInputGammaSource(url) }
    }

    private static func inspectInputGammaSource(_ url: URL) throws -> InputGammaSourceInfo {
        guard kind(of: url) != .rawDng else { return .init(curve: .decoder, manualError: .unsupportedSource) }
        guard let source = imageSource(url),
              let cg = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { throw InputGammaDecodeError.decodeFailed }
        let isTIFF = CGImageSourceGetType(source) as String? == "public.tiff"
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let metadata: TIFFInputProfileReader.Metadata?
        do { metadata = isTIFF ? try TIFFInputProfileReader.read(url) : nil }
        catch {
            // 수동 지원 검사가 기존 자동 디코더에서 열리던 파일까지 막지 않습니다.
            return .init(curve: .decoder, manualError: (error as? InputGammaDecodeError) ?? .decodeFailed)
        }
        let profile = metadata?.profile
        var curve: InputGammaSourceInfo.Curve
        if let profile {
            curve = InputGammaProfile.recordedPower(profile).map { .embeddedPower($0) } ?? .embeddedProfile
        } else if isTIFF, shouldInterpretAsLinearRaw(cg, properties: properties) {
            curve = .assumedLinear
        } else if properties?[kCGImagePropertyProfileName] != nil {
            curve = .embeddedProfile
        } else {
            curve = .assumedSRGB
        }
        var failure: InputGammaDecodeError?
        do {
            guard isTIFF else { throw InputGammaDecodeError.unsupportedSource }
            guard metadata?.supportsPower == true else { throw InputGammaDecodeError.unsupportedPixels }
            try InputGammaDecoder.validate(cg)
            if let profile { _ = try InputGammaProfile.linearized(profile) }
        } catch { failure = (error as? InputGammaDecodeError) ?? .decodeFailed }
        if profile == nil, failure == nil, let estimate = InputGammaEstimator.estimate(cg) {
            curve = .estimatedPower(estimate.gamma, evidence: estimate.evidence, edgeCount: estimate.edgeCount)
        }
        return .init(curve: curve, manualError: failure)
    }
}
