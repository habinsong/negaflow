import Foundation

enum LibraryArchivePayloadRole: String, Codable, Sendable {
    case catalog
    case original
    case infrared
    case defectRecipe
}

struct LibraryArchivePayload: Codable, Equatable, Sendable {
    var id: String
    var role: LibraryArchivePayloadRole
    var relativePath: String
    var originalFileName: String?
    var byteCount: Int64
    var sha256: String
}

struct LibraryArchiveFrame: Codable, Equatable, Sendable {
    var frameID: UUID
    var originalPayloadID: String
    var infraredPayloadID: String?
    var defectRecipePayloadID: String?
}

struct LibraryArchiveManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let formatIdentifier = "org.negaflow.library-archive"

    var format: String = formatIdentifier
    var version: Int = currentVersion
    var createdAt: Date
    var catalogVersion: Int
    var frames: [LibraryArchiveFrame]
    var payloads: [LibraryArchivePayload]
}

struct LibraryArchiveValidationReport: Equatable, Sendable {
    var frameCount: Int
    var payloadCount: Int
    var payloadByteCount: Int64
}

enum LibraryArchiveError: Error, Equatable {
    case destinationExists
    case invalidCatalog
    case missingSource(String)
    case unsafeSource(String)
    case sourceChanged(String)
    case missingDefectRecipe(UUID)
    case invalidPackage(String)
}
