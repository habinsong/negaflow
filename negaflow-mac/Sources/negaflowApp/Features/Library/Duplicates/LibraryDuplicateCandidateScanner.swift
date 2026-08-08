import CryptoKit
import Foundation

struct LibraryDuplicateCandidateInput: Sendable, Equatable {
    let frameID: UUID
    let sourceURL: URL
}

struct LibraryDuplicateCandidateMember: Sendable, Equatable, Identifiable {
    var id: UUID { frameID }
    let frameID: UUID
    let sourceURL: URL
}

struct LibraryDuplicateCandidateGroup: Sendable, Equatable, Identifiable {
    var id: String { sha256 }
    let sha256: String
    let fileSizeBytes: Int
    let members: [LibraryDuplicateCandidateMember]
}

struct LibraryDuplicateCandidateReport: Sendable, Equatable {
    let groups: [LibraryDuplicateCandidateGroup]
    let skippedUnavailableCount: Int
    let inspectedFileCount: Int
}

enum LibraryDuplicateCandidateScanner {
    static func scan(
        _ inputs: [LibraryDuplicateCandidateInput]
    ) async throws -> LibraryDuplicateCandidateReport {
        try await Task.detached(priority: .utility) {
            try scanSynchronously(inputs)
        }.value
    }

    private struct AvailableInput {
        let input: LibraryDuplicateCandidateInput
        let fileSizeBytes: Int
    }

    private static func scanSynchronously(
        _ inputs: [LibraryDuplicateCandidateInput]
    ) throws -> LibraryDuplicateCandidateReport {
        var seenFrameIDs = Set<UUID>()
        var available: [AvailableInput] = []
        var skippedCount = 0

        for input in inputs where seenFrameIDs.insert(input.frameID).inserted {
            try Task.checkCancellation()
            let url = input.sourceURL.standardizedFileURL
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let fileSize = values.fileSize,
            fileSize >= 0 else {
                skippedCount += 1
                continue
            }
            available.append(.init(
                input: .init(frameID: input.frameID, sourceURL: url),
                fileSizeBytes: fileSize
            ))
        }

        let sizeCandidates = Dictionary(grouping: available, by: \.fileSizeBytes)
            .filter { $0.value.count >= 2 }
        var hashByPath: [String: String] = [:]
        var hashed: [(AvailableInput, String)] = []

        for size in sizeCandidates.keys.sorted() {
            for candidate in sizeCandidates[size, default: []] {
                try Task.checkCancellation()
                let path = candidate.input.sourceURL.path
                let digest: String
                if let cached = hashByPath[path] {
                    digest = cached
                } else {
                    digest = try sha256(candidate.input.sourceURL)
                    hashByPath[path] = digest
                }
                hashed.append((candidate, digest))
            }
        }

        let groups = Dictionary(grouping: hashed, by: { $0.1 })
            .values
            .filter { $0.count >= 2 }
            .map { matches in
                let ordered = matches.sorted {
                    if $0.0.input.sourceURL.path != $1.0.input.sourceURL.path {
                        return $0.0.input.sourceURL.path < $1.0.input.sourceURL.path
                    }
                    return $0.0.input.frameID.uuidString < $1.0.input.frameID.uuidString
                }
                return LibraryDuplicateCandidateGroup(
                    sha256: ordered[0].1,
                    fileSizeBytes: ordered[0].0.fileSizeBytes,
                    members: ordered.map {
                        LibraryDuplicateCandidateMember(
                            frameID: $0.0.input.frameID,
                            sourceURL: $0.0.input.sourceURL
                        )
                    }
                )
            }
            .sorted { $0.sha256 < $1.sha256 }

        return LibraryDuplicateCandidateReport(
            groups: groups,
            skippedUnavailableCount: skippedCount,
            inspectedFileCount: available.count
        )
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
