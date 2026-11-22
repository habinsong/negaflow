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
    public var printerOutputICCProfileData: Data?
    public var media: SoftProofMedia?

    public init(
        isEnabled: Bool = false,
        colorSpace: ExportColorSpace = .sRGB,
        simulation: SoftProofSimulation = .profileOnly,
        iccProfileData: Data? = nil,
        printerOutputICCProfileData: Data? = nil,
        media: SoftProofMedia? = nil
    ) {
        self.isEnabled = isEnabled
        self.colorSpace = colorSpace
        self.simulation = simulation
        self.iccProfileData = iccProfileData
        self.printerOutputICCProfileData = printerOutputICCProfileData
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
           let colorSpace = rgbOutputColorSpace(fromICCData: data) {
            return colorSpace
        }
        guard settings.isEnabled,
              let profile = profile(for: settings.colorSpace),
              let colorSpace = CGColorSpace(iccData: profile.iccData as CFData) else {
            return settings.colorSpace.cgColorSpace
        }
        return colorSpace
    }

    /// Core Image의 RGBA 출력 대상으로 쓸 수 있는 RGB ICC만 받는다. CMYK/입력 전용 프로파일을
    /// 허용하면 프루프 렌더가 nil이 되므로 선택 시점과 복원 시점에 같은 검증을 공유한다.
    public static func rgbOutputColorSpace(fromICCData data: Data) -> CGColorSpace? {
        guard let colorSpace = CGColorSpace(iccData: data as CFData),
              colorSpace.model == .rgb,
              colorSpace.supportsOutput else { return nil }
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

    public static func simulatedPaperWhiteRGB(
        for settings: SoftProofSettings
    ) -> SIMD3<Double>? {
        guard settings.isEnabled,
              settings.simulation == .paperAndBlackInk,
              let media = proofMedia(for: settings),
              media.white != nil else { return nil }
        return paperWhiteRGB(from: media.white)
    }

    /// 프로파일의 용지 흰색과 잉크 검정을 읽는다.
    ///
    /// ICC v2 행렬/TRC 프로파일은 `wtpt` 에 적응하지 않은 매체 흰색을 적어도 된다. 이 맥의
    /// 시스템 sRGB·Adobe RGB 프로파일이 그렇다 — `wtpt` 가 D65(0.9505, 1.0, 1.0891)라
    /// 그대로 D50 으로 나누면 파랑이 1.32(상한 1.2)·빨강이 0.986 이 되어 프루프가 파랗게
    /// 물든다(회색 200 → (199, 200, 218)). 그래서 행렬/TRC RGB 프로파일은 rXYZ+gXYZ+bXYZ,
    /// 곧 정의상 PCS 흰색을 흰색으로 쓴다. 실제 프린터·인화지 프로파일은 전부 LUT 형이라
    /// 지금처럼 `wtpt` 를 읽으므로 측정된 용지 흰색은 그대로 남는다. 윈도우
    /// `color::read_soft_proof_media` 와 같은 규칙이다.
    public static func mediaTags(fromICCData data: Data) -> SoftProofMedia? {
        guard data.count >= 132 else { return nil }
        let tagCount = Int(readUInt32(data, at: 128))
        guard tagCount >= 0, data.count >= 132 + tagCount * 12 else { return nil }
        var tags: [String: SoftProofXYZ] = [:]
        var signatures = Set<String>()
        for index in 0..<tagCount {
            let entry = 132 + index * 12
            guard let signature = String(data: data[entry..<(entry + 4)], encoding: .ascii) else {
                continue
            }
            let offset = Int(readUInt32(data, at: entry + 4))
            let size = Int(readUInt32(data, at: entry + 8))
            guard offset >= 0, size > 0, offset + size <= data.count else { continue }
            signatures.insert(signature)
            guard size >= 20,
                  ["wtpt", "bkpt", "rXYZ", "gXYZ", "bXYZ"].contains(signature),
                  let xyz = readXYZType(data, at: offset) else { continue }
            tags[signature] = xyz
        }
        let rgbDataSpace = String(data: data[16..<20], encoding: .ascii) == "RGB "
        let matrixTRC = rgbDataSpace
            && ["rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC"].allSatisfy(signatures.contains)
        var white = tags["wtpt"]
        if matrixTRC, let red = tags["rXYZ"], let green = tags["gXYZ"], let blue = tags["bXYZ"] {
            white = SoftProofXYZ(
                x: red.x + green.x + blue.x,
                y: red.y + green.y + blue.y,
                z: red.z + green.z + blue.z
            )
        }
        let black = tags["bkpt"]
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

    /// 색소 합은 s15Fixed16 반올림 때문에 D50 에서 2e-4 안쪽으로 어긋난다. 그대로 두면 배율
    /// 1.000006 이 8비트 경계의 화소 하나를 한 단계 넘기므로, 세 채널이 모두 이 안이면 정확한
    /// 값으로 맞춘다. 실제 용지는 이보다 두 자릿수 멀다(윈도우 `soft_proof_neutral_tolerance`).
    private static let neutralTolerance = 1.0e-3

    /// PCS XYZ(D50) → 선형 sRGB. ICC sRGB 색소(Bradford 로 D50 에 맞춘 값)의 역행렬이다. 용지 흰색·
    /// 잉크 검정을 XYZ/D50 비율 그대로 RGB 배율로 쓰던 앞 판은 따뜻한 용지(X·Y 0.97, Z 0.92)를
    /// (0.970, 0.970, 0.920) 으로 그렸지만 이 행렬로는 (0.990, 0.969, 0.912) 다(Gemini 보고, 2026-11-22).
    /// 윈도우 `soft_proof.cpp` `xyz_d50_to_linear_srgb` 와 같은 값.
    private static let xyzD50ToLinearSRGB: [SIMD3<Double>] = [
        SIMD3(3.133856368, -1.61686677, -0.490614773),
        SIMD3(-0.978768563, 1.916141553, 0.033454116),
        SIMD3(0.071945168, -0.228991277, 1.405242674),
    ]

    private static func linearSRGB(from xyz: SoftProofXYZ) -> SIMD3<Double> {
        let v = SIMD3(xyz.x, xyz.y, xyz.z)
        return SIMD3((xyzD50ToLinearSRGB[0] * v).sum(), (xyzD50ToLinearSRGB[1] * v).sum(), (xyzD50ToLinearSRGB[2] * v).sum())
    }

    private static func paperWhiteRGB(from white: SoftProofXYZ?) -> SIMD3<Double> {
        guard let white else { return SIMD3<Double>(1, 1, 1) }
        let rgb = linearSRGB(from: white)
        return snapped(SIMD3<Double>(
            clamp(rgb.x, min: 0, max: 1.2),
            clamp(rgb.y, min: 0, max: 1.2),
            clamp(rgb.z, min: 0, max: 1.2)
        ), to: 1)
    }

    private static func blackInkRGB(from black: SoftProofXYZ?) -> SIMD3<Double> {
        guard let black else { return SIMD3<Double>(0, 0, 0) }
        let rgb = linearSRGB(from: black)
        return snapped(SIMD3<Double>(
            clamp(rgb.x, min: 0, max: 0.3),
            clamp(rgb.y, min: 0, max: 0.3),
            clamp(rgb.z, min: 0, max: 0.3)
        ), to: 0)
    }

    /// 세 채널을 한 묶음으로 맞춘다. 두 채널만 중립이고 한 채널이 물든 용지는 진짜 용지다.
    private static func snapped(_ channels: SIMD3<Double>, to reference: Double) -> SIMD3<Double> {
        let near = abs(channels.x - reference) <= neutralTolerance
            && abs(channels.y - reference) <= neutralTolerance
            && abs(channels.z - reference) <= neutralTolerance
        return near ? SIMD3<Double>(repeating: reference) : channels
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
