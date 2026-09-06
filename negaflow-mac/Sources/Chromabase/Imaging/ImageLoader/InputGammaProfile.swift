import Foundation
import CoreGraphics

public enum InputGammaDecodeError: Error, Equatable, Sendable {
    case unsupportedSource
    case unsupportedPixels
    case unsupportedProfile
    case invalidProfile
    case decodeFailed
}

/// 원색·백색점·색순응 태그는 보존하고 입력 TRC만 정확한 선형 곡선으로 바꿉니다.
/// 감마는 이 프로파일에 넣기 전에 원본 코드 값에 적용합니다.
enum InputGammaProfile {
    private struct Tag {
        let signature: UInt32
        let payload: Data
    }

    static func linearized(_ data: Data) throws -> CGColorSpace {
        let profile = try linearizedData(data)
        guard let space = CGColorSpace(iccData: profile as CFData), space.model == .rgb else {
            throw InputGammaDecodeError.invalidProfile
        }
        return space
    }

    static func linearizedData(_ data: Data) throws -> Data {
        guard data.count >= 132, data.count <= 16 * 1024 * 1024,
              u32(data, 36) == signature("acsp") else {
            throw InputGammaDecodeError.invalidProfile
        }
        let size = Int(u32(data, 0))
        let count = Int(u32(data, 128))
        guard size >= 132, size <= data.count, count <= 4096, count <= (size - 132) / 12 else {
            throw InputGammaDecodeError.invalidProfile
        }
        guard [2, 4].contains(data[8]),
              [signature("scnr"), signature("mntr")].contains(u32(data, 12)),
              u32(data, 16) == signature("RGB "), u32(data, 20) == signature("XYZ ") else {
            throw InputGammaDecodeError.unsupportedProfile
        }
        let tableEnd = 132 + count * 12
        let curves = Set([signature("rTRC"), signature("gTRC"), signature("bTRC")])
        let required = curves.union([signature("rXYZ"), signature("gXYZ"), signature("bXYZ"), signature("wtpt")])
        var seen = Set<UInt32>()
        var ranges: [Range<Int>] = []
        var tags: [Tag] = []
        var rebuiltSize = tableEnd
        for i in 0..<count {
            let entry = 132 + i * 12
            let name = u32(data, entry)
            let offset = Int(u32(data, entry + 4))
            let length = Int(u32(data, entry + 8))
            guard seen.insert(name).inserted, offset >= tableEnd, offset.isMultiple(of: 4),
                  length >= 8, offset <= size, length <= size - offset else {
                throw InputGammaDecodeError.invalidProfile
            }
            let range = offset..<(offset + length)
            guard !ranges.contains(where: { $0.overlaps(range) && $0 != range }) else {
                throw InputGammaDecodeError.invalidProfile
            }
            ranges.append(range)
            let prefix = name >> 8
            guard ![signature("A2B0") >> 8, signature("B2A0") >> 8,
                    signature("D2B0") >> 8, signature("B2D0") >> 8].contains(prefix) else {
                throw InputGammaDecodeError.unsupportedProfile
            }
            let rebuiltLength = curves.contains(name) ? 12 : (length + 3) / 4 * 4
            guard rebuiltLength <= 16 * 1024 * 1024 - rebuiltSize else {
                throw InputGammaDecodeError.invalidProfile
            }
            rebuiltSize += rebuiltLength
            let payload = data.subdata(in: range)
            if curves.contains(name) {
                try validateCurve(payload)
                var identity = Data()
                append(signature("curv"), to: &identity)
                append(0, to: &identity)
                append(0, to: &identity)
                tags.append(Tag(signature: name, payload: identity))
            } else {
                if required.contains(name) {
                    guard payload.count >= 20, u32(payload, 0) == signature("XYZ ") else {
                        throw InputGammaDecodeError.invalidProfile
                    }
                }
                tags.append(Tag(signature: name, payload: payload))
            }
        }
        guard required.isSubset(of: seen) else { throw InputGammaDecodeError.unsupportedProfile }
        var result = Data(data.prefix(128))
        result.replaceSubrange(84..<100, with: repeatElement(UInt8(0), count: 16))
        append(UInt32(tags.count), to: &result)
        var payloads = Data()
        for tag in tags {
            append(tag.signature, to: &result)
            append(UInt32(tableEnd + payloads.count), to: &result)
            append(UInt32(tag.payload.count), to: &result)
            payloads.append(tag.payload)
            while !payloads.count.isMultiple(of: 4) { payloads.append(0) }
        }
        result.append(payloads)
        var length = Data()
        append(UInt32(result.count), to: &length)
        result.replaceSubrange(0..<4, with: length)
        return result
    }

    private static func validateCurve(_ data: Data) throws {
        guard data.count >= 12 else { throw InputGammaDecodeError.invalidProfile }
        switch u32(data, 0) {
        case signature("curv"):
            guard Int(u32(data, 8)) <= (data.count - 12) / 2 else {
                throw InputGammaDecodeError.invalidProfile
            }
        case signature("para"):
            let function = Int(data[8]) * 256 + Int(data[9])
            let counts = [1, 3, 4, 5, 7]
            guard counts.indices.contains(function), data.count >= 12 + counts[function] * 4 else {
                throw InputGammaDecodeError.invalidProfile
            }
        default:
            throw InputGammaDecodeError.unsupportedProfile
        }
    }

    private static func signature(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { ($0 << 8) | UInt32(data[offset + $1]) }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
