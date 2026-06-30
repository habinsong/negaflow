import Foundation

public enum FramePickState: String, CaseIterable, Codable, Sendable, Equatable {
    case unflagged
    case picked
    case rejected
}
