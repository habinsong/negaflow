import Chromabase
import Combine
import Foundation

struct PrintLayoutTemplateSettings: Codable, Equatable, Sendable {
    var paperSize: PrintPaperSize
    var orientation: PrintPaperOrientation
    var marginMM: Double
    var perforationStyle: PrintPerforationStyle
    var layoutMode: PrintWorkspaceLayoutMode
    var packageSettings: PrintPackageSettings

    var isValid: Bool {
        packageSettings.isValid
            && PrintCompositionSettings(
                paperSize: paperSize,
                orientation: orientation,
                marginMM: marginMM,
                dpi: 300,
                perforationStyle: perforationStyle
            ).isValid
    }
}

struct PrintLayoutTemplate: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var settings: PrintLayoutTemplateSettings

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        settings: PrintLayoutTemplateSettings
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.createdAt = Date(timeIntervalSince1970: floor(createdAt.timeIntervalSince1970))
        self.settings = settings
    }

    var isValid: Bool {
        !name.isEmpty
            && name.count <= 80
            && name == Self.normalizedName(name)
            && createdAt.timeIntervalSinceReferenceDate.isFinite
            && settings.isValid
    }

    static func normalizedName(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }
}

@MainActor
final class PrintLayoutTemplateStore: ObservableObject {
    private struct Envelope: Codable {
        static let currentVersion = 1
        let version: Int
        let templates: [PrintLayoutTemplate]
    }

    static let maximumTemplateCount = 100

    @Published private(set) var templates: [PrintLayoutTemplate]
    @Published private(set) var canModify: Bool
    let url: URL

    init(url: URL = PrintLayoutTemplateStore.defaultURL()) {
        self.url = url
        let loaded = Self.load(from: url)
        templates = loaded.templates
        canModify = loaded.isValid
    }

    @discardableResult
    func add(name: String, settings: PrintLayoutTemplateSettings) -> PrintLayoutTemplate? {
        let name = PrintLayoutTemplate.normalizedName(name)
        guard canModify,
              templates.count < Self.maximumTemplateCount,
              !name.isEmpty,
              settings.isValid,
              !templates.contains(where: {
                  $0.name.caseInsensitiveCompare(name) == .orderedSame
              }) else { return nil }
        let template = PrintLayoutTemplate(name: name, settings: settings)
        let updated = templates + [template]
        guard persist(updated) else { return nil }
        templates = updated
        return template
    }

    func rename(id: UUID, to name: String) -> Bool {
        let name = PrintLayoutTemplate.normalizedName(name)
        guard canModify,
              !name.isEmpty,
              let index = templates.firstIndex(where: { $0.id == id }),
              !templates.contains(where: {
                  $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame
              }) else { return false }
        var updated = templates
        updated[index].name = name
        guard persist(updated) else { return false }
        templates = updated
        return true
    }

    func delete(id: UUID) {
        guard canModify else { return }
        let updated = templates.filter { $0.id != id }
        guard persist(updated) else { return }
        templates = updated
    }

    nonisolated static func defaultURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent("negaflow", isDirectory: true)
            .appendingPathComponent("print-layout-templates.json")
    }

    private static func load(from url: URL) -> (templates: [PrintLayoutTemplate], isValid: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], true) }
        guard let data = try? Data(contentsOf: url) else { return ([], false) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.version == Envelope.currentVersion,
              envelope.templates.count <= maximumTemplateCount,
              Set(envelope.templates.map(\.id)).count == envelope.templates.count,
              Set(envelope.templates.map { $0.name.lowercased() }).count == envelope.templates.count,
              envelope.templates.allSatisfy(\.isValid) else {
            return ([], false)
        }
        return (envelope.templates, true)
    }

    private func persist(_ templates: [PrintLayoutTemplate]) -> Bool {
        let envelope = Envelope(version: Envelope.currentVersion, templates: templates)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(envelope) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
