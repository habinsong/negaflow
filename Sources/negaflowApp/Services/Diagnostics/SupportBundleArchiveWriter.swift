import Foundation

enum SupportBundleArchiveError: Error, Equatable {
    case encodingFailed
    case archiveFailed(Int32)
    case publicationFailed
}

enum SupportBundleArchiveWriter {
    static func encodedDocument(_ document: SupportBundleDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(document)
        } catch {
            throw SupportBundleArchiveError.encodingFailed
        }
    }

    static func write(
        _ document: SupportBundleDocument,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "negaflow-support-build-\(UUID().uuidString)",
            isDirectory: true
        )
        let package = root.appendingPathComponent("negaflow-support", isDirectory: true)
        let stagedArchive = root.appendingPathComponent("support.zip")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        try encodedDocument(document).write(
            to: package.appendingPathComponent("support.json"),
            options: .atomic
        )
        try Self.readme.write(
            to: package.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c", "-k", "--sequesterRsrc", "--keepParent",
            package.path,
            stagedArchive.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SupportBundleArchiveError.archiveFailed(process.terminationStatus)
        }
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: stagedArchive)
            } else {
                try fileManager.moveItem(at: stagedArchive, to: destination)
            }
        } catch {
            throw SupportBundleArchiveError.publicationFailed
        }
    }

    private static let readme = """
    negaflow Support Bundle

    Paths, file names, source identifiers, and personal image metadata are omitted.
    Location and plugin identifiers are represented only by per-bundle salted hashes.
    """
}
