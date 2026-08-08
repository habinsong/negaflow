import Combine
import Foundation

@MainActor
final class ExportRecipeStore: ObservableObject {
    private struct Envelope: Codable {
        static let currentVersion = 1
        var version: Int
        var recipes: [ExportRecipe]
    }

    static let maximumRecipeCount = 100

    @Published private(set) var recipes: [ExportRecipe]
    @Published private(set) var canModify: Bool
    let url: URL

    init(url: URL = ExportRecipeStore.defaultURL()) {
        self.url = url
        let loaded = Self.load(from: url)
        recipes = loaded.recipes
        canModify = loaded.isValid
    }

    @discardableResult
    func add(name: String, settings: ExportRecipeSettings) -> ExportRecipe? {
        let normalizedName = ExportRecipe.normalizedName(name)
        guard canModify,
              recipes.count < Self.maximumRecipeCount,
              !normalizedName.isEmpty,
              !recipes.contains(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) else {
            return nil
        }
        let recipe = ExportRecipe(name: normalizedName, settings: settings)
        guard recipe.isValid else { return nil }
        let updated = recipes + [recipe]
        guard persist(updated) else { return nil }
        recipes = updated
        return recipe
    }

    func rename(id: UUID, to name: String) -> Bool {
        let normalizedName = ExportRecipe.normalizedName(name)
        guard canModify,
              !normalizedName.isEmpty,
              !recipes.contains(where: {
                $0.id != id && $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
              }), let index = recipes.firstIndex(where: { $0.id == id }) else {
            return false
        }
        var updated = recipes
        updated[index].name = normalizedName
        guard persist(updated) else { return false }
        recipes = updated
        return true
    }

    func delete(id: UUID) {
        guard canModify else { return }
        let updated = recipes.filter { $0.id != id }
        guard persist(updated) else { return }
        recipes = updated
    }

    nonisolated static func defaultURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent("negaflow", isDirectory: true)
            .appendingPathComponent("export-recipes.json")
    }

    private static func load(from url: URL) -> (recipes: [ExportRecipe], isValid: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], true) }
        guard let data = try? Data(contentsOf: url) else { return ([], false) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.version == Envelope.currentVersion,
              envelope.recipes.count <= maximumRecipeCount,
              Set(envelope.recipes.map(\.id)).count == envelope.recipes.count,
              Set(envelope.recipes.map { $0.name.lowercased() }).count == envelope.recipes.count,
              envelope.recipes.allSatisfy(\.isValid) else {
            return ([], false)
        }
        return (envelope.recipes, true)
    }

    private func persist(_ recipes: [ExportRecipe]) -> Bool {
        let envelope = Envelope(version: Envelope.currentVersion, recipes: recipes)
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
