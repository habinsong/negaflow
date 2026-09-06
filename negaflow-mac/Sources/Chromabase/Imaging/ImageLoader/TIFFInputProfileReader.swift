import Foundation

/// 첫 영상의 ICC 태그를 읽습니다. ImageIO가 만든 기본 색공간과 내장 ICC를 구분합니다.
enum TIFFInputProfileReader {
    struct Metadata {
        let profile: Data?
        let supportsPower: Bool
    }

    static func read(_ url: URL) throws -> Metadata {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let fileSize = try file.seekToEnd()
        func bytes(at offset: UInt64, count: Int) throws -> Data {
            guard count >= 0, offset <= fileSize, UInt64(count) <= fileSize - offset else {
                throw InputGammaDecodeError.invalidProfile
            }
            try file.seek(toOffset: offset)
            guard let data = try file.read(upToCount: count), data.count == count else {
                throw InputGammaDecodeError.decodeFailed
            }
            return data
        }
        let header = try bytes(at: 0, count: 8)
        let little: Bool
        if header[0] == 0x49, header[1] == 0x49 { little = true }
        else if header[0] == 0x4d, header[1] == 0x4d { little = false }
        else { throw InputGammaDecodeError.unsupportedSource }
        func number(_ data: Data, _ offset: Int, _ width: Int) -> UInt64 {
            let indices = little ? Array((offset..<(offset + width)).reversed()) : Array(offset..<(offset + width))
            return indices.reduce(0) { ($0 << 8) | UInt64(data[$1]) }
        }
        let magic = number(header, 2, 2)
        let big = magic == 43
        guard magic == 42 || (big && number(header, 4, 2) == 8 && number(header, 6, 2) == 0) else {
            throw InputGammaDecodeError.unsupportedSource
        }
        let ifdOffset: UInt64
        if big { ifdOffset = number(try bytes(at: 8, count: 8), 0, 8) }
        else { ifdOffset = number(header, 4, 4) }
        let countWidth = big ? 8 : 2
        let count = number(try bytes(at: ifdOffset, count: countWidth), 0, countWidth)
        let entryWidth = big ? 20 : 12
        guard count <= 65536, ifdOffset <= fileSize - UInt64(countWidth) else {
            throw InputGammaDecodeError.invalidProfile
        }
        let entries = try bytes(at: ifdOffset + UInt64(countWidth), count: Int(count) * entryWidth)
        var result: Data?
        var fields: [UInt64: [UInt64]] = [:]
        let layoutTags: Set<UInt64> = [258, 262, 277, 338, 339]
        for index in 0..<Int(count) {
            let start = index * entryWidth
            let tag = number(entries, start, 2)
            if layoutTags.contains(tag) {
                let length = number(entries, start + 4, big ? 8 : 4)
                guard fields[tag] == nil, number(entries, start + 2, 2) == 3, length <= 16 else {
                    throw InputGammaDecodeError.unsupportedPixels
                }
                let valueOffset = start + (big ? 12 : 8)
                let data: Data
                if length * 2 <= (big ? 8 : 4) {
                    data = entries.subdata(in: valueOffset..<(valueOffset + Int(length) * 2))
                } else {
                    data = try bytes(at: number(entries, valueOffset, big ? 8 : 4), count: Int(length) * 2)
                }
                fields[tag] = (0..<Int(length)).map { number(data, $0 * 2, 2) }
                continue
            }
            guard tag == 34675 else { continue }
            guard result == nil, number(entries, start + 2, 2) == 7 else {
                throw InputGammaDecodeError.invalidProfile
            }
            let length = number(entries, start + 4, big ? 8 : 4)
            let offset = number(entries, start + (big ? 12 : 8), big ? 8 : 4)
            guard length >= 132, length <= 16 * 1024 * 1024 else {
                throw InputGammaDecodeError.invalidProfile
            }
            result = try bytes(at: offset, count: Int(length))
        }
        let bits = fields[258] ?? [1]
        let format = fields[339] ?? [1]
        let supported = fields[262] == [2] && fields[277] == [3] && (fields[338] ?? []).isEmpty
            && [1, 3].contains(bits.count) && bits.allSatisfy { $0 == bits.first && [8, 16].contains($0) }
            && [1, 3].contains(format.count) && format.allSatisfy { $0 == 1 }
        return Metadata(profile: result, supportsPower: supported)
    }
}
