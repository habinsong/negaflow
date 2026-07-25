import Foundation

public struct LocalDodgeBurnPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct LocalDodgeBurnStroke: Codable, Sendable, Equatable {
    public var points: [LocalDodgeBurnPoint]
    public var thickness: Double
    public var feather: Double

    public init(points: [LocalDodgeBurnPoint], thickness: Double = 0.04, feather: Double = 0.02) {
        self.points = points
        self.thickness = thickness
        self.feather = feather
    }

    enum CodingKeys: String, CodingKey { case points, thickness, feather }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decodeIfPresent([LocalDodgeBurnPoint].self, forKey: .points) ?? []
        thickness = try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 0.04
        feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.02
    }
}

public enum LocalDodgeBurnMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case dodge
    case burn
}

public struct LocalDodgeBurnMask: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case brush
        case radial
        case linear
        case polygon
    }

    public var kind: Kind
    public var strokes: [LocalDodgeBurnStroke]
    public var center: LocalDodgeBurnPoint
    public var radius: Double
    public var feather: Double
    public var start: LocalDodgeBurnPoint
    public var end: LocalDodgeBurnPoint
    public var points: [LocalDodgeBurnPoint]

    public static func brush(strokes: [LocalDodgeBurnStroke]) -> LocalDodgeBurnMask {
        LocalDodgeBurnMask(kind: .brush, strokes: strokes)
    }

    public static func radial(center: LocalDodgeBurnPoint, radius: Double, feather: Double) -> LocalDodgeBurnMask {
        LocalDodgeBurnMask(kind: .radial, center: center, radius: radius, feather: feather)
    }

    public static func linear(
        start: LocalDodgeBurnPoint,
        end: LocalDodgeBurnPoint,
        feather: Double
    ) -> LocalDodgeBurnMask {
        LocalDodgeBurnMask(kind: .linear, feather: feather, start: start, end: end)
    }

    public static func polygon(points: [LocalDodgeBurnPoint], feather: Double) -> LocalDodgeBurnMask {
        LocalDodgeBurnMask(kind: .polygon, feather: feather, points: points)
    }

    public init(
        kind: Kind,
        strokes: [LocalDodgeBurnStroke] = [],
        center: LocalDodgeBurnPoint = LocalDodgeBurnPoint(x: 0.5, y: 0.5),
        radius: Double = 0.25,
        feather: Double = 0.25,
        start: LocalDodgeBurnPoint = LocalDodgeBurnPoint(x: 0.5, y: 0.0),
        end: LocalDodgeBurnPoint = LocalDodgeBurnPoint(x: 0.5, y: 1.0),
        points: [LocalDodgeBurnPoint] = []
    ) {
        self.kind = kind
        self.strokes = strokes
        self.center = center
        self.radius = radius
        self.feather = feather
        self.start = start
        self.end = end
        self.points = points
    }

    enum CodingKeys: String, CodingKey {
        case kind, strokes, center, radius, feather, start, end, points
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        strokes = try c.decodeIfPresent([LocalDodgeBurnStroke].self, forKey: .strokes) ?? []
        center = try c.decodeIfPresent(LocalDodgeBurnPoint.self, forKey: .center) ?? LocalDodgeBurnPoint(x: 0.5, y: 0.5)
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0.25
        feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.25
        start = try c.decodeIfPresent(LocalDodgeBurnPoint.self, forKey: .start) ?? LocalDodgeBurnPoint(x: 0.5, y: 0.0)
        end = try c.decodeIfPresent(LocalDodgeBurnPoint.self, forKey: .end) ?? LocalDodgeBurnPoint(x: 0.5, y: 1.0)
        points = try c.decodeIfPresent([LocalDodgeBurnPoint].self, forKey: .points) ?? []
    }
}

public struct LocalDodgeBurnAdjustment: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var mode: LocalDodgeBurnMode
    public var amount: Double
    public var isEnabled: Bool
    public var mask: LocalDodgeBurnMask

    public init(
        id: UUID = UUID(),
        mode: LocalDodgeBurnMode,
        amount: Double,
        isEnabled: Bool = true,
        mask: LocalDodgeBurnMask
    ) {
        self.id = id
        self.mode = mode
        self.amount = amount
        self.isEnabled = isEnabled
        self.mask = mask
    }

    enum CodingKeys: String, CodingKey { case id, mode, amount, isEnabled, mask }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mode = try c.decodeIfPresent(LocalDodgeBurnMode.self, forKey: .mode) ?? .dodge
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mask = try c.decode(LocalDodgeBurnMask.self, forKey: .mask)
    }
}
