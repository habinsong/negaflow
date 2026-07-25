import Compression
import Foundation

enum DefectBoundedDecompressionError: Error, Equatable {
    case invalidPayload
    case outputLimitExceeded
}

struct DefectCompressedData: Codable, Equatable, Sendable {
    var zlib: Bool
    var data: Data

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
