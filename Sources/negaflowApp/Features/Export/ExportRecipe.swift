import CryptoKit
import Foundation
import Chromabase

struct ExportRecipeSettings: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    var format: ExportFormat
    var options: ExportOptions
    var writeSidecar: Bool
    var writeMainFlatMaster: Bool
    var writeOriginalRaw: Bool
    var filenameTemplate: String

    init(
        format: ExportFormat,
        options: ExportOptions,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool,
        filenameTemplate: String
    ) {
        self.format = format
        self.options = options
        self.writeSidecar = writeSidecar
        self.writeMainFlatMaster = writeMainFlatMaster
        self.writeOriginalRaw = writeOriginalRaw
        self.filenameTemplate = ExportNamingTemplate.normalized(filenameTemplate)
    }

    func configurationSHA256() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var isValid: Bool {
        version == Self.currentVersion
            && options.dpi >= 0
            && (options.longEdge.map { $0 > 0 } ?? true)
            && ExportNamingTemplate.isValid(filenameTemplate)
            && ((try? options.validate(for: format)) != nil)
            && ((try? configurationSHA256().utf8.count) == 64)
    }

    private enum CodingKeys: String, CodingKey {
        case version, format, options, writeSidecar, writeMainFlatMaster, writeOriginalRaw
        case filenameTemplate, filenamePrefix
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        format = try container.decode(ExportFormat.self, forKey: .format)
        options = try container.decode(ExportOptions.self, forKey: .options)
        writeSidecar = try container.decode(Bool.self, forKey: .writeSidecar)
        writeMainFlatMaster = try container.decode(Bool.self, forKey: .writeMainFlatMaster)
        writeOriginalRaw = try container.decode(Bool.self, forKey: .writeOriginalRaw)
        if let pattern = try container.decodeIfPresent(String.self, forKey: .filenameTemplate) {
            filenameTemplate = ExportNamingTemplate.normalized(pattern)
        } else {
            filenameTemplate = ExportNamingTemplate.migratedPattern(
                fromLegacyPrefix: try container.decodeIfPresent(String.self, forKey: .filenamePrefix) ?? ""
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(format, forKey: .format)
        try container.encode(options, forKey: .options)
        try container.encode(writeSidecar, forKey: .writeSidecar)
        try container.encode(writeMainFlatMaster, forKey: .writeMainFlatMaster)
        try container.encode(writeOriginalRaw, forKey: .writeOriginalRaw)
        try container.encode(filenameTemplate, forKey: .filenameTemplate)
    }
}

struct ExportRecipe: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var settings: ExportRecipeSettings

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        settings: ExportRecipeSettings
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.createdAt = createdAt
        self.settings = settings
    }

    var isValid: Bool {
        !name.isEmpty
            && name.utf8.count <= 80
            && name == Self.normalizedName(name)
            && createdAt.timeIntervalSinceReferenceDate.isFinite
            && settings.isValid
    }

    static func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(80))
    }
}

struct ExportRecipeIdentity: Codable, Equatable, Sendable {
    let presetID: UUID?
    let presetName: String?
    let configurationSHA256: String
}
