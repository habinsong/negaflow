import Foundation
import CoreGraphics
import CoreImage

public enum SoftProofSimulation: String, CaseIterable, Codable, Sendable {
    case profileOnly
    case paperAndBlackInk

    public var uiLabel: String {
        switch self {
        case .profileOnly: return "Profile"
        case .paperAndBlackInk: return "Paper + Black"
        }
    }
}

public struct SoftProofSettings: Sendable {
    public var isEnabled: Bool
    public var colorSpace: ExportColorSpace
    public var simulation: SoftProofSimulation
    public var iccProfileData: Data?
    public var media: SoftProofMedia?

    public init(
        isEnabled: Bool = false,
        colorSpace: ExportColorSpace = .sRGB,
        simulation: SoftProofSimulation = .profileOnly,
        iccProfileData: Data? = nil,
        media: SoftProofMedia? = nil
    ) {
        self.isEnabled = isEnabled
        self.colorSpace = colorSpace
        self.simulation = simulation
        self.iccProfileData = iccProfileData
        self.media = media
    }

    public static let disabled = SoftProofSettings()
}

public struct SoftProofProfile: Sendable {
    public var iccData: Data
    public var colorSpaceModel: CGColorSpaceModel
    public var media: SoftProofMedia
}

public struct SoftProofMedia: Sendable, Equatable {
    public var white: SoftProofXYZ?
    public var black: SoftProofXYZ?

    public init(white: SoftProofXYZ?, black: SoftProofXYZ?) {
        self.white = white
        self.black = black
    }
}

public struct SoftProofXYZ: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public enum SoftProof {
    private static let referenceD50 = SoftProofXYZ(x: 0.9642, y: 1.0, z: 0.8249)

    public static func profile(for colorSpace: ExportColorSpace) -> SoftProofProfile? {
        let cgColorSpace = colorSpace.cgColorSpace
        guard let icc = cgColorSpace.copyICCData() else { return nil }
        let data = icc as Data
        return SoftProofProfile(
            iccData: data,
            colorSpaceModel: cgColorSpace.model,
            media: mediaTags(fromICCData: data) ?? SoftProofMedia(white: nil, black: nil)
        )
    }

    public static func proofColorSpace(for settings: SoftProofSettings) -> CGColorSpace {
        if settings.isEnabled,
           let data = settings.iccProfileData,
           let colorSpace = CGColorSpace(iccData: data as CFData) {
            return colorSpace
        }
        guard settings.isEnabled,
              let profile = profile(for: settings.colorSpace),
              let colorSpace = CGColorSpace(iccData: profile.iccData as CFData) else {
            return settings.colorSpace.cgColorSpace
        }
        return colorSpace
    }

    public static func apply(to image: CIImage, using settings: SoftProofSettings) -> CIImage {
        guard settings.isEnabled, settings.simulation == .paperAndBlackInk else { return image }
        let media = proofMedia(for: settings)
        guard let media, media.white != nil || media.black != nil else { return image }
        let white = paperWhiteRGB(from: media.white)
        let black = blackInkRGB(from: media.black)
        let scale = SIMD3<Double>(
            max(0, white.x - black.x),
            max(0, white.y - black.y),
            max(0, white.z - black.z)
        )
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale.x, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale.y, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale.z, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: black.x, y: black.y, z: black.z, w: 0),
        ])
    }

    public static func mediaTags(fromICCData data: Data) -> SoftProofMedia? {
        guard data.count >= 132 else { return nil }
        let tagCount = Int(readUInt32(data, at: 128))
        guard tagCount >= 0, data.count >= 132 + tagCount * 12 else { return nil }
        var white: SoftProofXYZ?
        var black: SoftProofXYZ?
        for index in 0..<tagCount {
            let entry = 132 + index * 12
            let signature = String(data: data[entry..<(entry + 4)], encoding: .ascii)
            let offset = Int(readUInt32(data, at: entry + 4))
            let size = Int(readUInt32(data, at: entry + 8))
            guard offset >= 0, size >= 20, offset + size <= data.count else { continue }
            switch signature {
            case "wtpt":
                white = readXYZType(data, at: offset)
            case "bkpt":
                black = readXYZType(data, at: offset)
            default:
                continue
            }
        }
        guard white != nil || black != nil else { return nil }
        return SoftProofMedia(white: white, black: black)
    }

    private static func readXYZType(_ data: Data, at offset: Int) -> SoftProofXYZ? {
        guard offset + 20 <= data.count,
              String(data: data[offset..<(offset + 4)], encoding: .ascii) == "XYZ " else {
            return nil
        }
        return SoftProofXYZ(
            x: readS15Fixed16(data, at: offset + 8),
            y: readS15Fixed16(data, at: offset + 12),
            z: readS15Fixed16(data, at: offset + 16)
        )
    }

    private static func paperWhiteRGB(from white: SoftProofXYZ?) -> SIMD3<Double> {
        guard let white else { return SIMD3<Double>(1, 1, 1) }
        return SIMD3<Double>(
            clamp(white.x / referenceD50.x, min: 0, max: 1.2),
            clamp(white.y / referenceD50.y, min: 0, max: 1.2),
            clamp(white.z / referenceD50.z, min: 0, max: 1.2)
        )
    }

    private static func blackInkRGB(from black: SoftProofXYZ?) -> SIMD3<Double> {
        guard let black else { return SIMD3<Double>(0, 0, 0) }
        return SIMD3<Double>(
            clamp(black.x / referenceD50.x, min: 0, max: 0.3),
            clamp(black.y / referenceD50.y, min: 0, max: 0.3),
            clamp(black.z / referenceD50.z, min: 0, max: 0.3)
        )
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    private static func readS15Fixed16(_ data: Data, at offset: Int) -> Double {
        let raw = readUInt32(data, at: offset)
        return Double(Int32(bitPattern: raw)) / 65536.0
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }

    private static func proofMedia(for settings: SoftProofSettings) -> SoftProofMedia? {
        if let data = settings.iccProfileData {
            return mediaTags(fromICCData: data)
        }
        return settings.media ?? profile(for: settings.colorSpace)?.media
    }
}
