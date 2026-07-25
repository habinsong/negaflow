import Foundation

struct SourceMovePlan: Equatable {
    struct FileMove: Equatable, Sendable {
        let sourceURL: URL
        let destinationURL: URL
    }

    let fileMoves: [FileMove]
    let relinkPlan: SourceRelinkPlan
    let sourceCount: Int

    var inverseRelinkPlan: SourceRelinkPlan {
        SourceRelinkPlan(
            mappings: relinkPlan.mappings.map {
                .init(oldSourceURL: $0.newSourceURL, newSourceURL: $0.oldSourceURL)
            },
            companionMappings: relinkPlan.companionMappings.map {
                .init(oldSourceURL: $0.newSourceURL, newSourceURL: $0.oldSourceURL)
            },
            oldFolderURL: relinkPlan.newFolderURL,
            newFolderURL: relinkPlan.oldFolderURL
        )
    }
}

enum SourceMovePlanError: Error, Equatable {
    case invalidDestination
    case collision
    case nothingToMove
}

enum SourceMovePlanner {
    struct SourcePair {
        let rawURL: URL
        let infraredURL: URL?
    }

    static func files(
        _ sources: [SourcePair],
        to destinationFolder: URL,
        fileManager: FileManager = .default
    ) -> Result<SourceMovePlan, SourceMovePlanError> {
        guard isDirectory(destinationFolder, fileManager: fileManager) else {
            return .failure(.invalidDestination)
        }
        let unique = Dictionary(grouping: sources, by: { $0.rawURL.standardizedFileURL.path })
            .values.compactMap(\.first)
            .sorted { $0.rawURL.path.localizedStandardCompare($1.rawURL.path) == .orderedAscending }
        var moves: [SourceMovePlan.FileMove] = []
        var mappings: [SourceRelinkPlan.Mapping] = []
        var companionMappings: [SourceRelinkPlan.Mapping] = []
        for source in unique {
            let raw = source.rawURL.standardizedFileURL
            let destination = destinationFolder.standardizedFileURL
                .appendingPathComponent(raw.lastPathComponent, isDirectory: false)
            if raw != destination {
                moves.append(.init(sourceURL: raw, destinationURL: destination))
                mappings.append(.init(oldSourceURL: raw, newSourceURL: destination))
            }
            if let infrared = source.infraredURL?.standardizedFileURL {
                let infraredDestination = destinationFolder.standardizedFileURL
                    .appendingPathComponent(infrared.lastPathComponent, isDirectory: false)
                if infrared != infraredDestination {
                    moves.append(.init(sourceURL: infrared, destinationURL: infraredDestination))
                    companionMappings.append(.init(
                        oldSourceURL: infrared,
                        newSourceURL: infraredDestination
                    ))
                }
            }
        }
        guard !mappings.isEmpty else { return .failure(.nothingToMove) }
        guard destinationsAreAvailable(moves, fileManager: fileManager) else {
            return .failure(.collision)
        }
        return .success(SourceMovePlan(
            fileMoves: moves,
            relinkPlan: SourceRelinkPlan(
                mappings: mappings,
                companionMappings: companionMappings
            ),
            sourceCount: mappings.count
        ))
    }

    static func folder(
        from oldFolder: URL,
        to newFolder: URL,
        sources: [SourcePair],
        fileManager: FileManager = .default
    ) -> Result<SourceMovePlan, SourceMovePlanError> {
        let oldRoot = oldFolder.standardizedFileURL
        let newRoot = newFolder.standardizedFileURL
        guard oldRoot != newRoot,
              isDirectory(oldRoot, fileManager: fileManager),
              isDirectory(newRoot.deletingLastPathComponent(), fileManager: fileManager),
              !isDescendant(newRoot, of: oldRoot) else {
            return .failure(.invalidDestination)
        }
        guard !fileManager.fileExists(atPath: newRoot.path) else {
            return .failure(.collision)
        }
        var mappings: [SourceRelinkPlan.Mapping] = []
        for source in Dictionary(grouping: sources, by: {
            $0.rawURL.standardizedFileURL.path
        }).values.compactMap(\.first) {
            guard let relative = relativeComponents(of: source.rawURL, under: oldRoot) else {
                continue
            }
            mappings.append(.init(
                oldSourceURL: source.rawURL.standardizedFileURL,
                newSourceURL: relative.reduce(newRoot) {
                    $0.appendingPathComponent($1, isDirectory: false)
                }
            ))
        }
        guard !mappings.isEmpty else { return .failure(.nothingToMove) }
        return .success(SourceMovePlan(
            fileMoves: [.init(sourceURL: oldRoot, destinationURL: newRoot)],
            relinkPlan: SourceRelinkPlan(
                mappings: mappings,
                oldFolderURL: oldRoot,
                newFolderURL: newRoot
            ),
            sourceCount: mappings.count
        ))
    }

    private static func destinationsAreAvailable(
        _ moves: [SourceMovePlan.FileMove],
        fileManager: FileManager
    ) -> Bool {
        let destinations = moves.map { $0.destinationURL.standardizedFileURL.path }
        return Set(destinations).count == destinations.count
            && moves.allSatisfy { !fileManager.fileExists(atPath: $0.destinationURL.path) }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
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
