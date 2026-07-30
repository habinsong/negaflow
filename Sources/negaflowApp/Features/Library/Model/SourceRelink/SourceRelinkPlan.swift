import AppKit
import Foundation
import ImageIO

struct SourceRelinkPlan: Equatable, Sendable {
    struct Mapping: Equatable, Sendable {
        let oldSourceURL: URL
        let newSourceURL: URL
    }

    let mappings: [Mapping]
    let companionMappings: [Mapping]
    let unresolvedSourceURLs: [URL]
    let oldFolderURL: URL?
    let newFolderURL: URL?

    init(
        mappings: [Mapping],
        companionMappings: [Mapping] = [],
        unresolvedSourceURLs: [URL] = [],
        oldFolderURL: URL? = nil,
        newFolderURL: URL? = nil
    ) {
        self.mappings = mappings
        self.companionMappings = companionMappings
        self.unresolvedSourceURLs = unresolvedSourceURLs
        self.oldFolderURL = oldFolderURL
        self.newFolderURL = newFolderURL
    }

    var isComplete: Bool { unresolvedSourceURLs.isEmpty }
}

enum SourceRelinkPlanner {
    static func filePlan(
        oldSourceURL: URL,
        newSourceURL: URL,
        isReadable: (URL) -> Bool
    ) -> SourceRelinkPlan? {
        let candidate = newSourceURL.standardizedFileURL
        guard isReadable(candidate) else { return nil }
        return SourceRelinkPlan(mappings: [
            .init(oldSourceURL: oldSourceURL.standardizedFileURL, newSourceURL: candidate)
        ])
    }

    static func folderPlan(
        oldFolderURL: URL,
        newFolderURL: URL,
        sourceURLs: [URL],
        isReadable: (URL) -> Bool
    ) -> SourceRelinkPlan {
        let oldRoot = oldFolderURL.standardizedFileURL
        let newRoot = newFolderURL.standardizedFileURL
        let uniqueSources = Dictionary(
            grouping: sourceURLs.map(\.standardizedFileURL),
            by: { $0.path }
        )
        .values
        .compactMap(\.first)
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        var mappings: [SourceRelinkPlan.Mapping] = []
        var unresolved: [URL] = []
        for source in uniqueSources {
            guard let relativeComponents = relativeComponents(of: source, under: oldRoot) else {
                continue
            }
            let candidate = relativeComponents.reduce(newRoot) {
                $0.appendingPathComponent($1, isDirectory: false)
            }
            if isReadable(candidate) {
                mappings.append(.init(oldSourceURL: source, newSourceURL: candidate))
            } else {
                unresolved.append(source)
            }
        }

        return SourceRelinkPlan(
            mappings: mappings,
            unresolvedSourceURLs: unresolved,
            oldFolderURL: oldRoot,
            newFolderURL: newRoot
        )
    }

    static func relocatedCompanionURL(
        _ url: URL?,
        using plan: SourceRelinkPlan,
        fileExists: (URL) -> Bool
    ) -> URL? {
        guard let url else { return nil }
        let standardized = url.standardizedFileURL
        if let direct = plan.companionMappings.first(where: {
            $0.oldSourceURL.standardizedFileURL == standardized
        }) {
            let candidate = direct.newSourceURL.standardizedFileURL
            return fileExists(candidate) ? candidate : url
        }
        guard
              let oldRoot = plan.oldFolderURL,
              let newRoot = plan.newFolderURL,
              let relativeComponents = relativeComponents(of: url, under: oldRoot) else {
            return url
        }
        let candidate = relativeComponents.reduce(newRoot) {
            $0.appendingPathComponent($1, isDirectory: false)
        }
        return fileExists(candidate) ? candidate : url
    }

    private static func relativeComponents(of url: URL, under root: URL) -> [String]? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let sourceComponents = url.standardizedFileURL.pathComponents
        guard sourceComponents.count > rootComponents.count,
              Array(sourceComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        return Array(sourceComponents.dropFirst(rootComponents.count))
    }
}
