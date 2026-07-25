import Foundation

public struct DevelopHistoryEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let label: String
    public let createdAt: Date
    public let params: DevelopParameters
    public let presetID: String?

    public init(
        id: UUID = UUID(),
        label: String,
        createdAt: Date = Date(),
        params: DevelopParameters,
        presetID: String?
    ) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
        self.params = params
        self.presetID = presetID
    }
}
