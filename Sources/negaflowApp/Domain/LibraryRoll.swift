import Foundation
import Chromabase

enum LibraryRollKind: String, Codable, Equatable, Sendable {
    case physical
    case unassigned
}

struct LibraryRoll: Identifiable, Codable, Equatable, Sendable {
    static let unassignedID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    let id: UUID
    let kind: LibraryRollKind
    var name: String?
    let createdAt: Date
    var filmType: FilmType?
    var frameIDs: [UUID]

    static func physical(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        filmType: FilmType,
        frameIDs: [UUID] = []
    ) -> LibraryRoll? {
        guard id != unassignedID,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return LibraryRoll(
            id: id,
            kind: .physical,
            name: name,
            createdAt: createdAt,
            filmType: filmType,
            frameIDs: frameIDs
        )
    }

    static func unassigned(
        createdAt: Date,
        frameIDs: [UUID]
    ) -> LibraryRoll {
        LibraryRoll(
            id: unassignedID,
            kind: .unassigned,
            name: nil,
            createdAt: createdAt,
            filmType: nil,
            frameIDs: frameIDs
        )
    }
}
