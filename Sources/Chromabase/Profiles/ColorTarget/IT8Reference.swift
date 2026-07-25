import Foundation

public struct IT8ReferencePatch: Codable, Sendable, Equatable {
    public let id: String
    public let lab: ColorTargetLab
    public let density: Double?

    public init(id: String, lab: ColorTargetLab, density: Double? = nil) {
        self.id = id
        self.lab = lab
        self.density = density
    }

    public var normalizedID: String {
        IT8ReferenceParser.normalizedPatchID(id)
    }
}

public struct IT8ReferenceDocument: Sendable, Equatable {
    public let metadata: [String: String]
    public let patches: [IT8ReferencePatch]

    public init(metadata: [String: String], patches: [IT8ReferencePatch]) {
        self.metadata = metadata
        self.patches = patches
    }
}

public enum IT8ReferenceParserError: Error, Sendable, Equatable {
    case unsupportedEncoding
    case missingDataFormat
    case missingData
    case emptyData
    case malformedLine(line: Int)
    case unterminatedQuote(line: Int)
    case unterminatedSection(String)
    case duplicateSection(String)
    case duplicateDeclaration(String)
    case invalidDeclaration(name: String, value: String)
    case missingField(String)
    case emptyFieldName(index: Int)
    case duplicateField(String)
    case fieldCountMismatch(line: Int, expected: Int, actual: Int)
    case declaredFieldCountMismatch(expected: Int, actual: Int)
    case declaredSetCountMismatch(expected: Int, actual: Int)
    case emptyPatchIdentifier(line: Int)
    case duplicatePatchIdentifier(String)
    case invalidNumber(field: String, value: String, line: Int)
    case lightnessOutOfRange(id: String, value: Double, line: Int)
}

public enum IT8ReferenceParser {
    public static func parse(_ data: Data) throws -> IT8ReferenceDocument {
        guard var source = String(data: data, encoding: .utf8) else {
            throw IT8ReferenceParserError.unsupportedEncoding
        }
        if source.first == "\u{FEFF}" {
            source.removeFirst()
        }
        source = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = source.components(separatedBy: "\n").enumerated().map {
            SourceLine(number: $0.offset + 1, text: $0.element)
        }

        let hasCGATSSections = lines.contains { line in
            let head = line.text.trimmingCharacters(in: .whitespaces)
                .uppercased()
            return head.hasPrefix("BEGIN_DATA_FORMAT") || head.hasPrefix("BEGIN_DATA")
        }
        return try hasCGATSSections ? parseCGATS(lines) : parseTabTable(lines)
    }

    public static func normalizedPatchID(_ id: String) -> String {
        let raw = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercased = raw.uppercased()
        guard raw.unicodeScalars.allSatisfy({ $0.value < 128 }) else { return uppercased }

        let characters = Array(uppercased.utf8)
        var prefixEnd = 0
        while prefixEnd < characters.count, (65...90).contains(characters[prefixEnd]) {
            prefixEnd += 1
        }
        guard prefixEnd > 0, prefixEnd < characters.count else { return uppercased }
        let suffix = characters[prefixEnd...]
        guard suffix.allSatisfy({ (48...57).contains($0) }) else { return uppercased }

        let prefix = String(decoding: characters[..<prefixEnd], as: UTF8.self)
        let withoutLeadingZeros = suffix.drop(while: { $0 == 48 })
        let digits = withoutLeadingZeros.isEmpty
            ? "0"
            : String(decoding: withoutLeadingZeros, as: UTF8.self)
        return prefix + digits
    }

    private static func parseCGATS(_ lines: [SourceLine]) throws -> IT8ReferenceDocument {
        var metadata: [String: String] = [:]
        var format: [String] = []
        var dataRows: [(line: Int, fields: [String])] = []
        var declaredFieldCount: Int?
        var declaredSetCount: Int?
        var section: CGATSSection?
        var sawFormat = false
        var sawData = false
        var finishedData = false

        for line in lines {
            let tokens = try tokenizeWhitespace(line.text, line: line.number)
            guard !tokens.isEmpty else { continue }
            let keyword = canonical(tokens[0])

            switch section {
            case .dataFormat:
                if keyword == "END_DATA_FORMAT" {
                    guard tokens.count == 1 else {
                        throw IT8ReferenceParserError.malformedLine(line: line.number)
                    }
                    section = nil
                } else if isStructuralKeyword(keyword) {
                    throw IT8ReferenceParserError.malformedLine(line: line.number)
                } else {
                    format.append(contentsOf: tokens)
                }
                continue
            case .data:
                if keyword == "END_DATA" {
                    guard tokens.count == 1 else {
                        throw IT8ReferenceParserError.malformedLine(line: line.number)
                    }
                    section = nil
                    finishedData = true
                } else if isStructuralKeyword(keyword) {
                    throw IT8ReferenceParserError.malformedLine(line: line.number)
                } else {
                    dataRows.append((line.number, tokens))
                }
                continue
            case nil:
                break
            }

            guard !finishedData else {
                throw IT8ReferenceParserError.malformedLine(line: line.number)
            }

            switch keyword {
            case "BEGIN_DATA_FORMAT":
                guard tokens.count == 1 else {
                    throw IT8ReferenceParserError.malformedLine(line: line.number)
                }
                guard !sawFormat else {
                    throw IT8ReferenceParserError.duplicateSection("DATA_FORMAT")
                }
                sawFormat = true
                section = .dataFormat
            case "BEGIN_DATA":
                guard tokens.count == 1 else {
                    throw IT8ReferenceParserError.malformedLine(line: line.number)
                }
                guard !sawData else {
                    throw IT8ReferenceParserError.duplicateSection("DATA")
                }
                guard sawFormat else {
                    throw IT8ReferenceParserError.malformedLine(line: line.number)
                }
                sawData = true
                section = .data
            case "END_DATA_FORMAT", "END_DATA":
                throw IT8ReferenceParserError.malformedLine(line: line.number)
            case "NUMBER_OF_FIELDS":
                guard declaredFieldCount == nil else {
                    throw IT8ReferenceParserError.duplicateDeclaration("NUMBER_OF_FIELDS")
                }
                declaredFieldCount = try parseDeclaration(
                    tokens,
                    name: "NUMBER_OF_FIELDS",
                    line: line.number
                )
            case "NUMBER_OF_SETS":
                guard declaredSetCount == nil else {
                    throw IT8ReferenceParserError.duplicateDeclaration("NUMBER_OF_SETS")
                }
                declaredSetCount = try parseDeclaration(
                    tokens,
                    name: "NUMBER_OF_SETS",
                    line: line.number
                )
            default:
                if tokens.count == 1, metadata["FILE_SIGNATURE"] == nil {
                    metadata["FILE_SIGNATURE"] = tokens[0]
                } else if tokens.count >= 2 {
                    metadata[keyword] = tokens.dropFirst().joined(separator: " ")
                }
            }
        }

        if let section {
            throw IT8ReferenceParserError.unterminatedSection(section.name)
        }
        guard sawFormat else { throw IT8ReferenceParserError.missingDataFormat }
        guard sawData else { throw IT8ReferenceParserError.missingData }
        guard !format.isEmpty else { throw IT8ReferenceParserError.missingDataFormat }
        if let declaredFieldCount, declaredFieldCount != format.count {
            throw IT8ReferenceParserError.declaredFieldCountMismatch(
                expected: declaredFieldCount,
                actual: format.count
            )
        }
        if let declaredSetCount, declaredSetCount != dataRows.count {
            throw IT8ReferenceParserError.declaredSetCountMismatch(
                expected: declaredSetCount,
                actual: dataRows.count
            )
        }

        return try makeDocument(
            metadata: metadata,
            format: format,
            rows: dataRows
        )
    }

    private static func parseTabTable(_ lines: [SourceLine]) throws -> IT8ReferenceDocument {
        var metadata: [String: String] = [:]
        var format: [String]?
        var rows: [(line: Int, fields: [String])] = []
        var declaredFieldCount: Int?
        var declaredSetCount: Int?

        for line in lines {
            guard !line.text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let fields = try tokenizeTabs(line.text, line: line.number)

            if format == nil, let detected = tabFormat(from: fields) {
                format = detected
                continue
            }

            if format != nil {
                rows.append((line.number, fields))
                continue
            }

            guard fields.count >= 2 else { continue }
            let key = canonical(fields[0])
            let value = fields.dropFirst().joined(separator: "\t")
                .trimmingCharacters(in: .whitespaces)
            switch key {
            case "NUMBER_OF_FIELDS":
                guard declaredFieldCount == nil else {
                    throw IT8ReferenceParserError.duplicateDeclaration("NUMBER_OF_FIELDS")
                }
                declaredFieldCount = try parseDeclaration(
                    [key, value],
                    name: key,
                    line: line.number
                )
            case "NUMBER_OF_SETS":
                guard declaredSetCount == nil else {
                    throw IT8ReferenceParserError.duplicateDeclaration("NUMBER_OF_SETS")
                }
                declaredSetCount = try parseDeclaration(
                    [key, value],
                    name: key,
                    line: line.number
                )
            default:
                metadata[key] = value
            }
        }

        guard let format else { throw IT8ReferenceParserError.missingDataFormat }
        if let declaredFieldCount, declaredFieldCount != format.count {
            throw IT8ReferenceParserError.declaredFieldCountMismatch(
                expected: declaredFieldCount,
                actual: format.count
            )
        }
        if let declaredSetCount, declaredSetCount != rows.count {
            throw IT8ReferenceParserError.declaredSetCountMismatch(
                expected: declaredSetCount,
                actual: rows.count
            )
        }
        return try makeDocument(metadata: metadata, format: format, rows: rows)
    }

    private static func tabFormat(from fields: [String]) -> [String]? {
        let canonicalFields = fields.map(canonical)
        let hasL = canonicalFields.contains(where: isLabLField)
        let hasA = canonicalFields.contains(where: isLabAField)
        let hasB = canonicalFields.contains(where: isLabBField)
        guard hasL, hasA, hasB else { return nil }

        if canonicalFields.first.map(isLabLField) == true {
            return ["SAMPLE_ID"] + fields
        }
        if canonicalFields.first?.isEmpty == true {
            var result = fields
            result[0] = "SAMPLE_ID"
            return result
        }
        if canonicalFields.first.map(isTabIdentifierField) == true {
            var result = fields
            result[0] = "SAMPLE_ID"
            return result
        }
        return fields
    }

    private static func makeDocument(
        metadata: [String: String],
        format: [String],
        rows: [(line: Int, fields: [String])]
    ) throws -> IT8ReferenceDocument {
        guard !rows.isEmpty else { throw IT8ReferenceParserError.emptyData }
        let canonicalFormat = format.map(canonical)
        if let emptyIndex = canonicalFormat.indices.dropFirst().first(where: {
            canonicalFormat[$0].isEmpty
        }) {
            throw IT8ReferenceParserError.emptyFieldName(index: emptyIndex)
        }
        var seenFields = Set<String>()
        for field in canonicalFormat where !field.isEmpty {
            guard seenFields.insert(field).inserted else {
                throw IT8ReferenceParserError.duplicateField(field)
            }
        }

        let idIndex = try requiredIndex(
            in: canonicalFormat,
            matching: { $0 == "SAMPLE_ID" },
            name: "SAMPLE_ID"
        )
        let lIndex = try requiredIndex(in: canonicalFormat, matching: isLabLField, name: "LAB_L")
        let aIndex = try requiredIndex(in: canonicalFormat, matching: isLabAField, name: "LAB_A")
        let bIndex = try requiredIndex(in: canonicalFormat, matching: isLabBField, name: "LAB_B")
        let densityIndices = canonicalFormat.indices.filter { isDensityField(canonicalFormat[$0]) }
        guard densityIndices.count <= 1 else {
            throw IT8ReferenceParserError.duplicateField("DENSITY")
        }
        let densityIndex = densityIndices.first

        var patches: [IT8ReferencePatch] = []
        patches.reserveCapacity(rows.count)
        var identifiers = Set<String>()

        for row in rows {
            guard row.fields.count == canonicalFormat.count else {
                throw IT8ReferenceParserError.fieldCountMismatch(
                    line: row.line,
                    expected: canonicalFormat.count,
                    actual: row.fields.count
                )
            }
            let id = row.fields[idIndex].trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty else {
                throw IT8ReferenceParserError.emptyPatchIdentifier(line: row.line)
            }
            let normalizedID = normalizedPatchID(id)
            guard identifiers.insert(normalizedID).inserted else {
                throw IT8ReferenceParserError.duplicatePatchIdentifier(normalizedID)
            }

            let l = try parseNumber(row.fields[lIndex], field: "LAB_L", line: row.line)
            let a = try parseNumber(row.fields[aIndex], field: "LAB_A", line: row.line)
            let b = try parseNumber(row.fields[bIndex], field: "LAB_B", line: row.line)
            guard (0.0...100.0).contains(l) else {
                throw IT8ReferenceParserError.lightnessOutOfRange(id: id, value: l, line: row.line)
            }
            let density: Double?
            if let densityIndex {
                let rawDensity = row.fields[densityIndex].trimmingCharacters(in: .whitespaces)
                density = rawDensity.isEmpty
                    ? nil
                    : try parseNumber(rawDensity, field: "DENSITY", line: row.line)
            } else {
                density = nil
            }
            patches.append(IT8ReferencePatch(
                id: id,
                lab: ColorTargetLab(l: l, a: a, b: b),
                density: density
            ))
        }

        return IT8ReferenceDocument(metadata: metadata, patches: patches)
    }

    private static func requiredIndex(
        in fields: [String],
        matching predicate: (String) -> Bool,
        name: String
    ) throws -> Int {
        let indices = fields.indices.filter { predicate(fields[$0]) }
        guard let index = indices.first else { throw IT8ReferenceParserError.missingField(name) }
        guard indices.count == 1 else { throw IT8ReferenceParserError.duplicateField(name) }
        return index
    }

    private static func parseNumber(_ value: String, field: String, line: Int) throws -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let parsed = Double(trimmed), parsed.isFinite else {
            throw IT8ReferenceParserError.invalidNumber(field: field, value: value, line: line)
        }
        return parsed
    }

    private static func parseDeclaration(_ tokens: [String], name: String, line: Int) throws -> Int {
        guard tokens.count == 2,
              let value = Int(tokens[1]),
              value >= 0 else {
            throw IT8ReferenceParserError.invalidDeclaration(
                name: name,
                value: tokens.dropFirst().joined(separator: " ")
            )
        }
        return value
    }

    private static func tokenizeWhitespace(_ source: String, line: Int) throws -> [String] {
        try tokenize(source, line: line, separators: { $0.isWhitespace }, comments: true)
    }

    private static func tokenizeTabs(_ source: String, line: Int) throws -> [String] {
        try tokenize(source, line: line, separators: { $0 == "\t" }, comments: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func tokenize(
        _ source: String,
        line: Int,
        separators: (Character) -> Bool,
        comments: Bool
    ) throws -> [String] {
        let characters = Array(source)
        var tokens: [String] = []
        var current = ""
        var tokenStarted = false
        var quoted = false
        var quoteClosed = false
        var index = 0

        func appendToken() {
            tokens.append(current)
            current = ""
            tokenStarted = false
            quoteClosed = false
        }

        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\\", index + 1 < characters.count,
                   characters[index + 1] == "\"" || characters[index + 1] == "\\" {
                    current.append(characters[index + 1])
                    index += 2
                    continue
                }
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        current.append("\"")
                        index += 2
                        continue
                    }
                    quoted = false
                    quoteClosed = true
                    index += 1
                    continue
                }
                current.append(character)
                index += 1
                continue
            }

            if comments, character == "#" {
                break
            }
            if separators(character) {
                if tokenStarted || !comments {
                    appendToken()
                }
                index += 1
                continue
            }
            if !comments, character.isWhitespace, !tokenStarted || quoteClosed {
                index += 1
                continue
            }
            if character == "\"" {
                guard !tokenStarted else {
                    throw IT8ReferenceParserError.malformedLine(line: line)
                }
                quoted = true
                tokenStarted = true
                index += 1
                continue
            }
            guard !quoteClosed else {
                throw IT8ReferenceParserError.malformedLine(line: line)
            }
            current.append(character)
            tokenStarted = true
            index += 1
        }

        guard !quoted else { throw IT8ReferenceParserError.unterminatedQuote(line: line) }
        if tokenStarted || (!comments && source.last == "\t") {
            appendToken()
        }
        return tokens
    }

    private static func canonical(_ field: String) -> String {
        field.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func isLabLField(_ field: String) -> Bool {
        field == "LAB_L" || field == "L*"
    }

    private static func isLabAField(_ field: String) -> Bool {
        field == "LAB_A" || field == "A*"
    }

    private static func isLabBField(_ field: String) -> Bool {
        field == "LAB_B" || field == "B*"
    }

    private static func isDensityField(_ field: String) -> Bool {
        field == "DENSITY" || field == "D"
    }

    private static func isTabIdentifierField(_ field: String) -> Bool {
        field == "SAMPLE_ID" || field == "PATCH" || field == "PATCH_ID" || field == "ID"
    }

    private static func isStructuralKeyword(_ field: String) -> Bool {
        field == "BEGIN_DATA_FORMAT" || field == "END_DATA_FORMAT"
            || field == "BEGIN_DATA" || field == "END_DATA"
            || field == "NUMBER_OF_FIELDS" || field == "NUMBER_OF_SETS"
    }
}

private struct SourceLine {
    let number: Int
    let text: String
}

private enum CGATSSection {
    case dataFormat
    case data

    var name: String {
        switch self {
        case .dataFormat: "DATA_FORMAT"
        case .data: "DATA"
        }
    }
}
