import Foundation

extension RenderManifest {
    public enum DigestAlgorithm: String, Codable, Sendable {
        case sha256 = "sha-256"
    }

    public enum RenderInputKind: String, Codable, Sendable {
        case source
        case cleanedFile
        case cleanedMemory
    }

    public enum Coverage: String, Codable, Sendable {
        case completeRenderInput
        case sourceAndDevelopRecipe
    }

    public struct SourceIdentity: Codable, Sendable, Equatable {
        public var algorithm: DigestAlgorithm
        public var byteCount: Int64
        public var sha256: String

        public init(
            algorithm: DigestAlgorithm = .sha256,
            byteCount: Int64,
            sha256: String
        ) {
            self.algorithm = algorithm
            self.byteCount = byteCount
            self.sha256 = sha256
        }

        private enum CodingKeys: String, CodingKey {
            case algorithm, byteCount, sha256
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            algorithm = try container.decodeIfPresent(
                DigestAlgorithm.self,
                forKey: .algorithm
            ) ?? .sha256
            byteCount = try container.decode(Int64.self, forKey: .byteCount)
            sha256 = try container.decode(String.self, forKey: .sha256)
        }
    }

    public struct OutputArtifact: Codable, Sendable, Equatable {
        public var identity: SourceIdentity
        public var format: ExportFormat
        public var pixelWidth: Int
        public var pixelHeight: Int

        public init(
            identity: SourceIdentity,
            format: ExportFormat,
            pixelWidth: Int,
            pixelHeight: Int
        ) {
            self.identity = identity
            self.format = format
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }
    }
}
