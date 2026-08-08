import Foundation

// Builds the ICC v2 matrix/TRC RGB input profile used by the ColorSync/ICM parity
// fixture. The bytes are synthesised here so the repository never carries a vendor
// scanner profile. Every constant below is normative: the Windows side rebuilds the
// same byte sequence from negaflow-windows/docs/research/colorsync-icm-parity-profile.md.
enum SyntheticScannerICCProfile {
    static let descriptionText = "Negaflow Synthetic Scanner RGB v1"
    static let copyrightText = "Negaflow synthetic parity fixture. No rights asserted."

    /// u8Fixed8Number encoding of the TRC gamma. 563 / 256 == 2.19921875, which is the
    /// value the profile actually carries — not 2.2.
    static let gammaU8Fixed8: UInt16 = 563
    static var gamma: Double { Double(gammaU8Fixed8) / 256.0 }

    /// sRGB primaries (IEC 61966-2-1) Bradford-adapted from D65 to the ICC PCS D50,
    /// encoded as s15Fixed16Number. These match the columns of the standard sRGB profile.
    private static let redColumn: [Int32] = [0x0000_6FA0, 0x0000_38F5, 0x0000_0390]
    private static let greenColumn: [Int32] = [0x0000_6297, 0x0000_B787, 0x0000_18D9]
    private static let blueColumn: [Int32] = [0x0000_249F, 0x0000_0F84, 0x0000_B6C3]
    /// ICC PCS illuminant D50: X 0.9642, Y 1.0, Z 0.8249.
    private static let mediaWhitePoint: [Int32] = [0x0000_F6D6, 0x0001_0000, 0x0000_D32D]

    /// Fixed creation timestamp so the bytes are reproducible: 2026-01-01T00:00:00Z.
    private static let creationDateTime: [UInt16] = [2026, 1, 1, 0, 0, 0]

    static func data() -> Data {
        let tags: [(signature: String, payload: Data)] = [
            ("desc", textDescriptionTag(descriptionText)),
            ("wtpt", xyzTag(mediaWhitePoint)),
            ("rXYZ", xyzTag(redColumn)),
            ("gXYZ", xyzTag(greenColumn)),
            ("bXYZ", xyzTag(blueColumn)),
            ("rTRC", gammaCurveTag()),
            ("gTRC", gammaCurveTag()),
            ("bTRC", gammaCurveTag()),
            ("cprt", textTag(copyrightText)),
        ]

        // Tag data follows the tag table in table order, each block 4-byte aligned.
        // No two tags share a data block, so the layout is a pure function of the order.
        let tableSize = 4 + tags.count * 12
        var offset = align(128 + tableSize)
        var table = Data()
        var payloads = Data()
        for tag in tags {
            table.appendBigEndian(UInt32(fourCharCode(tag.signature)))
            table.appendBigEndian(UInt32(offset))
            table.appendBigEndian(UInt32(tag.payload.count))
            payloads.append(tag.payload)
            let padded = align(tag.payload.count)
            payloads.append(Data(repeating: 0, count: padded - tag.payload.count))
            offset += padded
        }

        var body = Data()
        body.appendBigEndian(UInt32(tags.count))
        body.append(table)
        body.append(Data(repeating: 0, count: align(128 + tableSize) - (128 + tableSize)))
        body.append(payloads)

        var profile = header(totalSize: 128 + body.count)
        profile.append(body)
        return profile
    }

    // MARK: - Header

    private static func header(totalSize: Int) -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(totalSize))          // profile size
        data.appendBigEndian(UInt32(0))                  // preferred CMM: none
        data.appendBigEndian(UInt32(0x0210_0000))        // profile version 2.1.0
        data.appendBigEndian(UInt32(fourCharCode("scnr")))  // device class: input
        data.appendBigEndian(UInt32(fourCharCode("RGB ")))  // data colour space
        data.appendBigEndian(UInt32(fourCharCode("XYZ ")))  // PCS
        for component in creationDateTime {
            data.appendBigEndian(component)
        }
        data.appendBigEndian(UInt32(fourCharCode("acsp")))  // file signature
        data.appendBigEndian(UInt32(0))                  // primary platform: none
        data.appendBigEndian(UInt32(0))                  // profile flags
        data.appendBigEndian(UInt32(0))                  // device manufacturer
        data.appendBigEndian(UInt32(0))                  // device model
        data.appendBigEndian(UInt32(0))                  // device attributes (high)
        data.appendBigEndian(UInt32(0))                  // device attributes (low)
        // Header rendering intent 1 = media-relative colorimetric. A CMS that falls back
        // to the header instead of an explicitly requested intent then lands on the same
        // intent Windows ICM asks for.
        data.appendBigEndian(UInt32(1))
        for component in mediaWhitePoint {               // PCS illuminant, always D50
            data.appendBigEndian(UInt32(bitPattern: component))
        }
        data.appendBigEndian(UInt32(0))                  // profile creator
        data.append(Data(repeating: 0, count: 16))       // profile ID: not computed
        data.append(Data(repeating: 0, count: 28))       // reserved
        return data
    }

    // MARK: - Tag payloads

    private static func xyzTag(_ values: [Int32]) -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(fourCharCode("XYZ ")))
        data.appendBigEndian(UInt32(0))
        for value in values {
            data.appendBigEndian(UInt32(bitPattern: value))
        }
        return data
    }

    private static func gammaCurveTag() -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(fourCharCode("curv")))
        data.appendBigEndian(UInt32(0))
        data.appendBigEndian(UInt32(1))                  // one entry means "gamma only"
        data.appendBigEndian(gammaU8Fixed8)
        return data
    }

    private static func textTag(_ text: String) -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(fourCharCode("text")))
        data.appendBigEndian(UInt32(0))
        data.append(asciiBytes(text))
        return data
    }

    /// ICC v2 textDescriptionType: ASCII block, then an empty Unicode block, then an
    /// empty ScriptCode block whose 67-byte Macintosh buffer is always present.
    private static func textDescriptionTag(_ text: String) -> Data {
        let ascii = asciiBytes(text)
        var data = Data()
        data.appendBigEndian(UInt32(fourCharCode("desc")))
        data.appendBigEndian(UInt32(0))
        data.appendBigEndian(UInt32(ascii.count))
        data.append(ascii)
        data.appendBigEndian(UInt32(0))                  // Unicode language code
        data.appendBigEndian(UInt32(0))                  // Unicode character count
        data.appendBigEndian(UInt16(0))                  // ScriptCode code
        data.append(0)                                   // ScriptCode count
        data.append(Data(repeating: 0, count: 67))       // ScriptCode buffer
        return data
    }

    // MARK: - Primitives

    private static func asciiBytes(_ text: String) -> Data {
        var data = Data(text.unicodeScalars.map { scalar in
            scalar.isASCII ? UInt8(scalar.value) : UInt8(ascii: "?")
        })
        data.append(0)                                   // NUL terminator
        return data
    }

    private static func align(_ value: Int) -> Int {
        (value + 3) & ~3
    }

    private static func fourCharCode(_ text: String) -> UInt32 {
        precondition(text.utf8.count == 4)
        return text.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ])
    }

    mutating func appendBigEndian(_ value: UInt16) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ])
    }
}
