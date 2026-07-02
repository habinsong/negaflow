import Foundation
import CoreImage

public enum ScannerProfileValidationStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case realOnly
    case pairedSmoke
    case pairedValidated
}

public struct ScannerProfileStat: Codable, Sendable, Equatable {
    public var count: Double
    public var mean: Double
    public var median: Double
    public var p10: Double
    public var p90: Double
    public var min: Double
    public var max: Double
}

public struct ScannerProfileCandidate: Codable, Sendable, Equatable {
    public var stem: String
    public var realFile: String
    public var p50: Double
    public var contrastP90P10: Double
    public var midChroma: Double
}

public struct ScannerProfileCoverageAxis: Codable, Sendable, Equatable {
    public var axis: String
    public var candidates: [ScannerProfileCandidate]
}

public struct ScannerProfileSceneBucket: Codable, Sendable, Equatable {
    public var family: String
    public var name: String
    public var imageCount: Int
    public var tone: [String: ScannerProfileStat]
    public var color: [String: ScannerProfileStat]
    public var texture: [String: ScannerProfileStat]
    public var representativeCandidates: [ScannerProfileCandidate]
}

public struct ScannerProfile: Codable, Sendable, Identifiable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var displayName: String
    public var scanner: String
    public var kind: String
    public var filmKey: String
    public var validationStatus: ScannerProfileValidationStatus
    public var rollCount: Int
    public var imageCount: Int
    public var singleRollLimited: Bool
    public var sourceProfiles: [String]
    public var tone: [String: ScannerProfileStat]
    public var color: [String: ScannerProfileStat]
    public var neutralAxis: [String: ScannerProfileStat]
    public var texture: [String: ScannerProfileStat]
    public var sceneBuckets: [ScannerProfileSceneBucket]
    public var coverageCandidates: [ScannerProfileCoverageAxis]
    public var profileHash: String
}

public enum ScannerProfileRegistry {
    // 프로파일은 immutable 리소스다. 과거엔 load(named:)가 매 현상마다(슬라이더 한 번에 한 번)
    // 번들 JSON을 다시 읽고 디코드해 핫패스에 디스크 I/O + JSON 파싱 비용을 매번 지불했다.
    // 한 번 디코드한 결과를 캐시한다. 여러 백그라운드 현상 스레드가 동시에 접근하므로 락으로 보호한다.
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cache: [String: ScannerProfile] = [:]
    private nonisolated(unsafe) static var missCache: Set<String> = []

    public static func loadAll() -> [ScannerProfile] {
        guard let manifestURL = Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "ScannerProfiles"),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ScannerProfileManifest.self, from: data) else {
            return []
        }
        return manifest.profiles.compactMap { load(named: $0.id) }
    }

    public static func load(named id: String) -> ScannerProfile? {
        cacheLock.lock()
        if let cached = cache[id] {
            cacheLock.unlock()
            return cached
        }
        if missCache.contains(id) {
            cacheLock.unlock()
            return nil
        }
        cacheLock.unlock()

        guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "ScannerProfiles"),
              let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(ScannerProfile.self, from: data) else {
            cacheLock.lock(); missCache.insert(id); cacheLock.unlock()
            return nil
        }
        cacheLock.lock(); cache[id] = profile; cacheLock.unlock()
        return profile
    }

    private struct ScannerProfileManifest: Codable {
        var profiles: [Entry]
        struct Entry: Codable {
            var id: String
        }
    }
}

public enum ScannerProfileMatcher {
    public static func matchingProfiles(
        target: DevelopTarget,
        filmType: FilmType,
        profiles: [ScannerProfile]
    ) -> [ScannerProfile] {
        guard let kind = profileKind(for: filmType) else { return [] }
        let scannerOrder = scannerNames(for: target)
        return profiles
            .filter { profile in
                scannerOrder.contains(profile.scanner) && profile.kind == kind
            }
            .sorted { lhs, rhs in
                let lhsScanner = scannerOrder.firstIndex(of: lhs.scanner) ?? Int.max
                let rhsScanner = scannerOrder.firstIndex(of: rhs.scanner) ?? Int.max
                if lhsScanner != rhsScanner { return lhsScanner < rhsScanner }
                return lhs.filmKey.localizedStandardCompare(rhs.filmKey) == .orderedAscending
            }
    }

    public static func preferredProfileID(
        target: DevelopTarget,
        filmType: FilmType,
        filmStockDminID: String?,
        currentID: String?,
        profiles: [ScannerProfile]
    ) -> String? {
        let matches = matchingProfiles(target: target, filmType: filmType, profiles: profiles)
        guard !matches.isEmpty else { return nil }

        if let filmStockDminID {
            let candidates = Set(filmKeyCandidates(for: filmStockDminID))
            if let exact = matches.first(where: { candidates.contains(normalizedFilmKey($0.filmKey)) }) {
                return exact.id
            }
        }

        if let currentID, matches.contains(where: { $0.id == currentID }) {
            return currentID
        }

        return matches.first?.id
    }

    public static func filmKeyCandidates(for filmStockDminID: String) -> [String] {
        var candidates = [normalizedFilmKey(filmStockDminID)]
        if filmStockDminID.hasPrefix("vision3-") {
            candidates.append(normalizedFilmKey("kodak-\(filmStockDminID)"))
        }
        return candidates
    }

    private static func scannerNames(for target: DevelopTarget) -> [String] {
        switch target {
        case .main, .print:
            return []
        case .noritsu:
            return ["NORITSU"]
        case .sp3000:
            return ["SP-3000"]
        }
    }

    private static func profileKind(for filmType: FilmType) -> String? {
        switch filmType {
        case .colorNegative:
            return "color nega"
        case .colorPositive:
            return "color slide"
        case .bwNegative, .bwPositive:
            return nil
        }
    }

    private static func normalizedFilmKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }
}

public struct ScannerProfileGradeDiagnostics: Codable, Sendable, Equatable {
    public var profileID: String
    public var sceneBucket: String?
    public var toneCorrection: String
    public var neutralCorrection: String
    public var chromaCorrection: String
    public var clipGuardTriggered: Bool

    public init(profile: ScannerProfile) {
        profileID = profile.id
        sceneBucket = profile.sceneBuckets.first?.name
        toneCorrection = "bounded"
        neutralCorrection = "bounded"
        chromaCorrection = "bounded"
        clipGuardTriggered = false
    }
}

public enum ScannerProfileGrade {
    public static func apply(to image: CIImage, profile: ScannerProfile) -> CIImage {
        let extent = image.extent
        let p10 = clamp(profile.tone["p10"]?.median ?? 0.10, 0.0, 1.0)
        let p50 = clamp(profile.tone["p50"]?.median ?? 0.55, 0.0, 1.0)
        let p90 = clamp(profile.tone["p90"]?.median ?? 0.90, 0.0, 1.0)
        let contrast = clamp(profile.tone["contrast_p90_p10"]?.median ?? (p90 - p10), 0.0, 1.0)
        let midRG = profile.color["mid_rg"]?.median ?? 0
        let midGB = profile.color["mid_gb"]?.median ?? 0
        let midChroma = profile.color["mid_chroma"]?.median ?? 20
        let sharpness = profile.texture["texture_sharpness_p95"]?.median ?? 0.5

        let isSlide = profile.kind == "color slide"
        let gamma = clamp(0.98 + (0.56 - p50) * 0.14, 0.88, 1.08)
        let contrastAmount = clamp(1.06 + (contrast - 0.72) * 0.55, 1.00, 1.22)

        // Saturation — `mid_chroma` is a roll-wide median, so it reflects how vivid the
        // SCENES in that roll happened to be, not a property of the film. Driving saturation
        // directly off it cranked vivid rolls (e.g. SP-3000 Ektar, mid_chroma≈62) to ×1.46
        // and blew neutral frames into magenta/purple. Use a gentle film-class base with only
        // a whisper of chroma modulation, tightly clamped, so no frame is over-saturated.
        let satBase = isSlide ? 1.07 : 1.03
        let saturation = clamp(satBase + (midChroma - 24.0) / 450.0,
                               isSlide ? 1.02 : 0.99,
                               isSlide ? 1.16 : 1.10)
        let vibrance = clamp(0.04 + (midChroma - 24.0) / 800.0, 0.0, 0.14)

        // Film hue character — per-channel balance toward the film's mid R−G / G−B, so distinct
        // films (e.g. yellow-leaning Ektar vs blue-leaning UltraMax) separate visibly. A global
        // gain would also tint the white point (the green/cyan-sky artifact), so this is applied
        // with highlight preservation (see applyFilmTint) and bounded to ±6%.
        let k = 0.55
        let redGain = clamp(1.0 + midRG / 255.0 * k, 0.94, 1.06)
        let greenGain = clamp(1.0 - midRG / 255.0 * (k * 0.34) + midGB / 255.0 * (k * 0.32), 0.94, 1.06)
        let blueGain = clamp(1.0 - midGB / 255.0 * k, 0.94, 1.06)
        let shadowPoint = clamp(0.215 + (p10 - 0.11) * 0.22, 0.175, 0.255)
        let midPoint = clamp(0.505 + (p50 - 0.55) * 0.12, 0.455, 0.560)
        let highlightPoint = clamp(0.830 + (p90 - 0.88) * 0.12, 0.795, 0.875)
        let unsharp = clamp((sharpness - 0.38) * 0.62, 0.0, 0.38)

        var out = image
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": gamma])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: saturation,
                kCIInputContrastKey: contrastAmount,
            ])
        if vibrance > 1e-3 {
            out = out.applyingFilter("CIVibrance", parameters: ["inputAmount": vibrance])
        }
        out = applyFilmTint(to: out, red: redGain, green: greenGain, blue: blueGain)
        out = out
            .applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0.00, y: 0.00),
                "inputPoint1": CIVector(x: 0.23, y: shadowPoint),
                "inputPoint2": CIVector(x: 0.50, y: midPoint),
                "inputPoint3": CIVector(x: 0.82, y: highlightPoint),
                "inputPoint4": CIVector(x: 1.00, y: 1.00),
            ])
        if unsharp > 0 {
            out = out.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": 1.8,
                "inputIntensity": unsharp,
            ])
        }
        return out
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
            ])
            .cropped(to: extent)
    }

    /// Apply a gentle per-channel film hue balance, but keep neutral highlights neutral.
    /// A flat per-channel gain tints the white point (the green/cyan-sky artifact); here the
    /// tint is blended back out as luma approaches white, so bright skies stay neutral while
    /// mid/shadow tones still carry the film's character.
    private static func applyFilmTint(to image: CIImage,
                                      red: Double, green: Double, blue: Double) -> CIImage {
        let extent = image.extent
        let tinted = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: extent)
        // Highlight mask: 0 below `lo` (full tint), ramping to 1 by `hi` (revert to neutral).
        // `hi` is kept well below white so bright skies see no tint at all.
        let lo = 0.50, hi = 0.72
        let scale = 1.0 / (hi - lo)
        let highlightMask = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: -lo * scale, y: -lo * scale, z: -lo * scale, w: 0),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]).cropped(to: extent)
        // mask=1 → original (neutral highlight); mask=0 → tinted (mid/shadow film character).
        return CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: image,
            kCIInputBackgroundImageKey: tinted,
            "inputMaskImage": highlightMask,
        ])?.outputImage?.cropped(to: extent) ?? tinted
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}
