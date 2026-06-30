import Foundation

public struct DevelopUserPreset: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var params: DevelopParameters
    public var presetID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        params: DevelopParameters,
        presetID: String?
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        var presetParams = params
        presetParams.imageTransform = .identity
        self.params = presetParams
        self.presetID = presetID
    }
}
