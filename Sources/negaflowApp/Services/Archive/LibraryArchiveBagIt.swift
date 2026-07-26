import Foundation

enum LibraryArchiveBagIt {
    static let bagItText = "BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n"

    static func manifestText(_ records: [String: String]) -> String {
        records.keys.sorted().map { "\(records[$0]!)  \($0)\n" }.joined()
    }

    static func parseManifest(_ data: Data) throws -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw LibraryArchiveError.invalidPackage("manifest is not UTF-8")
        }
        var records: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.count > 65 else {
                throw LibraryArchiveError.invalidPackage("malformed checksum line")
            }
            let digest = String(line.prefix(64))
            let separatorAndPath = line.dropFirst(64)
            guard separatorAndPath.first == " " || separatorAndPath.first == "\t" else {
                throw LibraryArchiveError.invalidPackage("malformed checksum separator")
            }
            let path = String(separatorAndPath.drop(while: { $0 == " " || $0 == "\t" }))
            guard digest.count == 64,
                  digest.allSatisfy({ $0.isHexDigit }),
                  LibraryArchiveFileIO.isSafeRelativePath(path),
                  records.updateValue(digest.lowercased(), forKey: path) == nil else {
                throw LibraryArchiveError.invalidPackage("invalid checksum record")
            }
        }
        return records
    }

    static func bagInfo(createdAt: Date, payloads: [LibraryArchivePayload]) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let bytes = payloads.reduce(Int64(0)) { $0 + $1.byteCount }
        let text = """
        Bagging-Date: \(formatter.string(from: createdAt))
        Bag-Software-Agent: negaflow
        Payload-Oxum: \(bytes).\(payloads.count)

        """
        return Data(text.utf8)
    }

    static func encodeArchiveManifest(_ manifest: LibraryArchiveManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    static func decodeArchiveManifest(_ data: Data) throws -> LibraryArchiveManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryArchiveManifest.self, from: data)
    }
}
