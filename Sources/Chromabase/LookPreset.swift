import Foundation

// MARK: - LookPreset (plan §8.9, §8.10)
//
// JSON 기반 룩 프리셋. plan §8.10의 포맷을 따른다.
public struct LookPreset: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String           // 파일명(stem) = id
    public var name: String
    public var version: Int
    public var filmTypes: [String]  // 호환 필름 타입(rawValue)
    public var tone: ToneParams
    public var color: ColorParams
    public var texture: TextureParams

    public struct ToneParams: Codable, Sendable, Equatable {
        public var exposure: Double
        public var density: Double
        public var contrast: Double
        public var highlightRollOff: Double
        public var blackSoftness: Double
        public var midtoneLift: Double?
    }
    public struct ColorParams: Codable, Sendable, Equatable {
        public var warmth: Double
        public var tint: Double
        public var colorDepth: Double
        public var saturation: Double
    }
    public struct TextureParams: Codable, Sendable, Equatable {
        public var grain: Double
        public var sharpness: Double
        public var halation: Double
    }

    /// JSON 디코딩용(id는 파일명에서 주입되므로 기본값). id는 비-Codable 멤버로 취급.
    enum CodingKeys: String, CodingKey {
        case name, version, filmTypes, tone, color, texture
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = ""
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(Int.self, forKey: .version)
        filmTypes = try c.decode([String].self, forKey: .filmTypes)
        tone = try c.decode(ToneParams.self, forKey: .tone)
        color = try c.decode(ColorParams.self, forKey: .color)
        texture = try c.decode(TextureParams.self, forKey: .texture)
    }

    public init(id: String, name: String, version: Int, filmTypes: [String],
                tone: ToneParams, color: ColorParams, texture: TextureParams) {
        self.id = id; self.name = name; self.version = version
        self.filmTypes = filmTypes; self.tone = tone; self.color = color; self.texture = texture
    }

    /// SwiftUI Picker용 — 식별은 id로 충분하다.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: LookPreset, rhs: LookPreset) -> Bool { lhs.id == rhs.id }

    /// 프리셋을 DevelopParameters 기본값으로 변환한다.
    public var baseParameters: DevelopParameters {
        var p = DevelopParameters()
        p.density    = tone.density
        p.contrast   = tone.contrast
        p.highlight  = tone.highlightRollOff
        p.shadow     = tone.blackSoftness
        p.exposure   = tone.exposure + (tone.midtoneLift ?? 0) * 0.1
        p.warmth     = color.warmth
        p.tint       = color.tint
        p.colorDepth = color.colorDepth
        p.saturation = color.saturation
        p.grain      = texture.grain
        p.sharpness  = texture.sharpness
        p.halation   = texture.halation
        return p
    }
}

// MARK: - PresetRegistry
//
// 번들 리소스 Presets/*.json을 로드한다. plan §8.9 초기 6종.
public enum PresetRegistry {
    /// SPM 리소스 번들에서 프리셋을 로드한다.
    public static func loadAll() -> [LookPreset] {
        let names = ["neutral", "rich-neutral", "soft-print",
                     "clear-chrome", "warm-lab", "deep-slide"]
        return names.compactMap { load(named: $0) }
    }

    public static func load(named name: String) -> LookPreset? {
        // 리소스는 Presets/<name>.json 하위에 있다.
        if let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Presets"),
           let data = try? Data(contentsOf: url),
           var preset = try? JSONDecoder().decode(LookPreset.self, from: data) {
            preset.id = name
            return preset
        }
        // 번들이 평탄화된 경우(하위 디렉토리 없음) 대비.
        if let url = Bundle.module.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           var preset = try? JSONDecoder().decode(LookPreset.self, from: data) {
            preset.id = name
            return preset
        }
        return nil
    }
}
