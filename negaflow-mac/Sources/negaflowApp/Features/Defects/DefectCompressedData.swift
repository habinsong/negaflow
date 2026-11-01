import Compression
import Foundation

enum DefectBoundedDecompressionError: Error, Equatable {
    case invalidPayload
    case outputLimitExceeded
}

struct DefectCompressedData: Codable, Equatable, Sendable {
    var zlib: Bool
    var data: Data
    /// v3 기록 파일 안에서만 쓰인다. 메모리에서 비압축이던 값을 저장 때 압축했다는 표시로, 읽을 때
    /// 다시 비압축으로 되돌린다 — recipe 지문은 메모리 표현 기준이라 그대로 맞는다.
    var storagePacked: Bool? = nil

    static func raw(_ data: Data) -> DefectCompressedData {
        DefectCompressedData(zlib: false, data: data)
    }

    var rawBytes: Data {
        guard zlib else { return data }
        return (try? validatedRawBytes(maximumOutputBytes: Int.max)) ?? Data()
    }

    func validatedRawBytes(maximumOutputBytes: Int) throws -> Data {
        guard maximumOutputBytes >= 0 else {
            throw DefectBoundedDecompressionError.outputLimitExceeded
        }
        guard zlib else {
            guard data.count <= maximumOutputBytes else {
                throw DefectBoundedDecompressionError.outputLimitExceeded
            }
            return data
        }
        return try BoundedZlibDecoder.decode(
            data,
            maximumOutputBytes: maximumOutputBytes
        )
    }

    func compressed() -> DefectCompressedData {
        guard !zlib, !data.isEmpty,
              let packed = try? (data as NSData).compressed(using: .zlib) as Data else { return self }
        return DefectCompressedData(zlib: true, data: packed)
    }

    /// 비압축 값을 v3 기록 파일용으로 압축한다. 이미 압축됐거나 줄지 않으면 그대로 둔다.
    func packedForStorage() -> DefectCompressedData {
        let packed = compressed()
        guard !zlib, packed.zlib, packed.data.count < data.count else { return self }
        return DefectCompressedData(zlib: true, data: packed.data, storagePacked: true)
    }

    /// `packedForStorage()`의 역. 표시가 없으면 그대로 두고, 있으면 정확히 `rawByteCount` 바이트로
    /// 푼다. 길이가 다르거나 스트림이 깨졌으면 기록 전체를 거부한다.
    func unpackedFromStorage(rawByteCount: Int) throws -> DefectCompressedData {
        guard let storagePacked else { return self }
        guard storagePacked, zlib, rawByteCount > 0,
              let raw = try? validatedRawBytes(maximumOutputBytes: rawByteCount),
              raw.count == rawByteCount else {
            throw DefectRecipeValidationError.invalidMask
        }
        return .raw(raw)
    }

    func decompressed(maximumOutputBytes: Int = Int.max) -> DefectCompressedData {
        guard zlib else { return self }
        return DefectCompressedData(
            zlib: false,
            data: (try? validatedRawBytes(maximumOutputBytes: maximumOutputBytes)) ?? Data()
        )
    }
}

enum BoundedZlibDecoder {
    private static let outputChunkSize = 64 * 1_024

    static func decode(
        _ source: Data,
        maximumOutputBytes: Int
    ) throws -> Data {
        guard maximumOutputBytes >= 0, !source.isEmpty else {
            throw DefectBoundedDecompressionError.invalidPayload
        }
        let placeholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { placeholder.deallocate() }
        var stream = compression_stream(
            dst_ptr: placeholder,
            dst_size: 0,
            src_ptr: UnsafePointer(placeholder),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(
            &stream,
            COMPRESSION_STREAM_DECODE,
            COMPRESSION_ZLIB
        ) != COMPRESSION_STATUS_ERROR else {
            throw DefectBoundedDecompressionError.invalidPayload
        }
        defer { compression_stream_destroy(&stream) }

        return try source.withUnsafeBytes { sourceBytes in
            guard let sourceAddress = sourceBytes.bindMemory(to: UInt8.self).baseAddress else {
                throw DefectBoundedDecompressionError.invalidPayload
            }
            stream.src_ptr = sourceAddress
            stream.src_size = source.count
            var decoded = Data()
            let chunkSize = maximumOutputBytes == Int.max
                ? outputChunkSize
                : min(outputChunkSize, max(1, maximumOutputBytes + 1))
            var output = [UInt8](
                repeating: 0,
                count: chunkSize
            )

            while true {
                let sourceBytesBefore = stream.src_size
                let outputCapacity = output.count
                let status = output.withUnsafeMutableBytes { outputBytes in
                    stream.dst_ptr = outputBytes.bindMemory(to: UInt8.self).baseAddress!
                    stream.dst_size = outputCapacity
                    return compression_stream_process(
                        &stream,
                        Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                    )
                }
                let produced = outputCapacity - stream.dst_size
                guard produced <= maximumOutputBytes - decoded.count else {
                    throw DefectBoundedDecompressionError.outputLimitExceeded
                }
                decoded.append(contentsOf: output.prefix(produced))

                switch status {
                case COMPRESSION_STATUS_END:
                    return decoded
                case COMPRESSION_STATUS_OK:
                    guard produced > 0 || stream.src_size < sourceBytesBefore else {
                        throw DefectBoundedDecompressionError.invalidPayload
                    }
                default:
                    throw DefectBoundedDecompressionError.invalidPayload
                }
            }
        }
    }
}
