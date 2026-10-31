import CoreGraphics
import Foundation
import ImageIO

/// LZW 스트립 TIFF 를 모든 코어로 푼다.
///
/// Image I/O 는 LZW 를 한 코어로 처음부터 끝까지 순서대로 푼다. 앱이 저장하는 스캔 TIFF
/// (16bit RGBA, 3줄 스트립 1134개, 4960×3401)는 그 한 번에 400ms(처음 읽을 때 560ms)가 들었고,
/// 같은 크기의 무압축본은 9ms 였다 — 병목은 해제뿐이다. 스트립은 서로 독립이라 나눠 풀 수 있다.
///
/// 결과는 Image I/O 디코드 + `renderReadyImage` 와 **같은 비트**여야 한다. 그래서 Image I/O 가
/// 머리만 읽고 보고한 출력 형식(비트 깊이·화소 크기·알파·바이트 순서·색공간)을 그대로 따르고,
/// 저장값을 바이트 순서만 바꿔 옮기면 같은 결과가 나오는 파일만 맡는다. 연관 알파(ExtraSamples 1)는
/// 저장값이 곧 premultiplied 값이다. 그 밖의 형식이거나 스트립 하나라도 크기가 어긋나면 nil 이고,
/// 호출자는 원래 Image I/O 경로로 간다.
enum TIFFStripDecoder {
    static func decode(_ url: URL, source: CGImageSource) -> CGImage? {
        guard url.isFileURL,
              let layout = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              let data = try? Data(contentsOf: url, options: .alwaysMapped),
              let header = Header(data) else { return nil }
        let bytesPerSample = header.bitsPerSample / 8
        let expectedInfo: UInt32 = (header.samplesPerPixel == 4 ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.none.rawValue) | (bytesPerSample == 2 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
        let rowBytes = header.width * header.samplesPerPixel * bytesPerSample
        guard layout.width == header.width, layout.height == header.height,
              layout.bitsPerComponent == header.bitsPerSample,
              layout.bitsPerPixel == header.bitsPerSample * header.samplesPerPixel,
              layout.bytesPerRow == rowBytes,
              layout.bitmapInfo.rawValue == expectedInfo,
              let space = layout.colorSpace, space.model == .rgb else { return nil }
        let total = rowBytes * header.height
        // 모든 바이트를 스트립이 채우므로 0 으로 미리 채우지 않는다(135MB 면 그것만 수십 ms).
        guard total > 0, let raw = malloc(total) else { return nil }
        let base = raw.assumingMemoryBound(to: UInt8.self)
        let failed = Failure()
        data.withUnsafeBytes { (file: UnsafeRawBufferPointer) in
            guard let fileBase = file.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                failed.set(); return
            }
            let strips = header.stripOffsets.count
            let chunks = min(strips, ProcessInfo.processInfo.activeProcessorCount * 4)
            // Swift 동시성의 협력 스레드에서 바로 부르면 그 풀(코어 수 폭)의 바쁜 스레드를 나눠 쓴다.
            // GCD 전역 큐 문맥에서 돌려 일반 작업 스레드로 퍼지게 한다. 우선순위는 부른 쪽을 따른다 —
            // 이웃 미리 준비(utility)가 지금 보는 사진의 디코드와 같은 우선순위로 코어를 나눠 갖지 않게.
            DispatchQueue.global(qos: DispatchQoS.QoSClass(rawValue: qos_class_self()) ?? .userInitiated).sync {
            DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                var table = LZWTable()
                for strip in (chunk * strips / chunks)..<((chunk + 1) * strips / chunks) {
                    if failed.isSet { return }
                    let firstRow = strip * header.rowsPerStrip
                    let rows = min(header.rowsPerStrip, header.height - firstRow)
                    let offset = header.stripOffsets[strip], count = header.stripByteCounts[strip]
                    guard rows > 0, offset >= 0, count > 0, offset <= file.count - count else { failed.set(); return }
                    let destination = base + firstRow * rowBytes
                    let expected = rows * rowBytes
                    guard table.decode(fileBase + offset, count: count, into: destination, expected: expected) else {
                        failed.set(); return
                    }
                    finish(destination, rows: rows, header: header, rowBytes: rowBytes)
                }
            }
            }
        }
        guard !failed.isSet,
              let provider = CGDataProvider(dataInfo: nil, data: raw, size: total, releaseData: { _, data, _ in
                  free(UnsafeMutableRawPointer(mutating: data))
              }) else { free(raw); return nil }
        return CGImage(width: header.width, height: header.height, bitsPerComponent: header.bitsPerSample,
                       bitsPerPixel: header.bitsPerSample * header.samplesPerPixel, bytesPerRow: rowBytes,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: expectedInfo), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// 바이트 순서를 호스트(리틀엔디언)로 바꾸고 수평 예측기를 되돌린다.
    private static func finish(_ rows: UnsafeMutablePointer<UInt8>, rows count: Int, header: Header, rowBytes: Int) {
        let channels = header.samplesPerPixel
        if header.bitsPerSample == 16 {
            let samples = UnsafeMutableRawPointer(rows).assumingMemoryBound(to: UInt16.self)
            let perRow = rowBytes / 2
            if header.bigEndian {
                for index in 0..<(perRow * count) { samples[index] = samples[index].byteSwapped }
            }
            if header.predictor == 2 {
                for row in 0..<count {
                    let line = samples + row * perRow
                    for index in channels..<perRow { line[index] &+= line[index - channels] }
                }
            }
        } else if header.predictor == 2 {
            for row in 0..<count {
                let line = rows + row * rowBytes
                for index in channels..<rowBytes { line[index] &+= line[index - channels] }
            }
        }
    }

    private final class Failure: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }

    /// 첫 IFD 의 기본 태그. 이 디코더가 맡는 형식이 아니면 nil.
    struct Header {
        let bigEndian: Bool
        let width: Int, height: Int
        let bitsPerSample: Int, samplesPerPixel: Int
        let rowsPerStrip: Int
        let predictor: Int
        let stripOffsets: [Int], stripByteCounts: [Int]

        init?(_ data: Data) {
            guard data.count >= 8 else { return nil }
            let big: Bool
            switch (data[0], data[1]) {
            case (0x49, 0x49): big = false
            case (0x4D, 0x4D): big = true
            default: return nil
            }
            func u16(_ at: Int) -> Int? {
                guard at >= 0, at + 2 <= data.count else { return nil }
                let a = Int(data[at]), b = Int(data[at + 1])
                return big ? a << 8 | b : b << 8 | a
            }
            func u32(_ at: Int) -> Int? {
                guard let high = u16(big ? at : at + 2), let low = u16(big ? at + 2 : at) else { return nil }
                return high << 16 | low
            }
            guard u16(2) == 42, let ifd = u32(4), let entries = u16(ifd), entries > 0 else { return nil }
            var tags: [Int: [Int]] = [:]
            for entry in 0..<entries {
                let at = ifd + 2 + entry * 12
                guard let tag = u16(at), let type = u16(at + 2), let count = u32(at + 4), count > 0 else { return nil }
                let size: Int
                switch type {
                case 3: size = 2
                case 4: size = 4
                default: continue
                }
                let inline = count * size <= 4
                guard let start = inline ? at + 8 : u32(at + 8),
                      count <= (data.count - start) / size else { return nil }
                var values: [Int] = []
                values.reserveCapacity(count)
                for index in 0..<count {
                    guard let value = size == 2 ? u16(start + index * 2) : u32(start + index * 4) else { return nil }
                    values.append(value)
                }
                tags[tag] = values
            }
            func one(_ tag: Int, default fallback: Int? = nil) -> Int? {
                guard let values = tags[tag] else { return fallback }
                return values.count == 1 ? values[0] : nil
            }
            guard let width = one(256), let height = one(257), width > 0, height > 0,
                  one(259) == 5, one(262) == 2, one(284, default: 1) == 1, one(266, default: 1) == 1,
                  tags[322] == nil, tags[324] == nil,
                  let channels = one(277), channels == 3 || channels == 4,
                  let bits = tags[258], bits.count == channels, Set(bits).count == 1,
                  bits[0] == 8 || bits[0] == 16,
                  (tags[339] ?? [1]).allSatisfy({ $0 == 1 }),
                  let predictor = one(317, default: 1), predictor == 1 || predictor == 2,
                  let offsets = tags[273], let counts = tags[279], offsets.count == counts.count else { return nil }
            // 4채널은 연관 알파일 때만 저장값이 곧 결과다.
            if channels == 4 { guard tags[338] == [1] else { return nil } } else { guard tags[338] == nil else { return nil } }
            let rowsPerStrip = min(one(278, default: height) ?? height, height)
            guard rowsPerStrip > 0, offsets.count == (height + rowsPerStrip - 1) / rowsPerStrip else { return nil }
            bigEndian = big
            self.width = width; self.height = height
            bitsPerSample = bits[0]; samplesPerPixel = channels
            self.rowsPerStrip = rowsPerStrip
            self.predictor = predictor
            stripOffsets = offsets; stripByteCounts = counts
        }
    }

    /// TIFF LZW(MSB 우선, 조기 코드 폭 증가). libtiff `LZWDecode` 와 같은 규칙이다.
    ///
    /// 표는 문자열을 담지 않고 **그 문자열이 이 스트립 출력의 어디에 이미 써졌는지**만 기억한다.
    /// 새 항목(직전 문자열 + 한 글자)은 직전 문자열이 써진 자리에서 시작해 한 바이트 길다 — 바로
    /// 뒤에 지금 문자열의 첫 글자가 이어 써지기 때문이다. 접두 사슬을 거꾸로 따라가지 않는다.
    struct LZWTable {
        private var offset = [Int32](repeating: 0, count: 4096)
        private var length = [Int32](repeating: 0, count: 4096)

        /// 스트립 하나를 정확히 `expected` 바이트로 푼다. 입력이 모자라거나 코드가 어긋나면 false.
        mutating func decode(_ input: UnsafePointer<UInt8>, count: Int, into output: UnsafeMutablePointer<UInt8>,
                             expected: Int) -> Bool {
            offset.withUnsafeMutableBufferPointer { offset in
            length.withUnsafeMutableBufferPointer { length in
                var bitBuffer: UInt64 = 0, bitCount = 0, position = 0
                var width = 9, next = 258, written = 0, widen = 511
                var previousOffset = -1, previousLength = 0
                // libtiff 처럼 출력이 찰 때까지 푼다. EOI 가 없거나 뒤에 남는 바이트가 있어도 같다.
                while written < expected {
                    if bitCount < width {
                        // 네 바이트를 한 번에 채운다. 스트립 끝 네 바이트 안쪽만 한 바이트씩 본다.
                        if position + 4 <= count {
                            let word = UnsafeRawPointer(input + position).loadUnaligned(as: UInt32.self).bigEndian
                            bitBuffer = bitBuffer << 32 | UInt64(word)
                            position += 4; bitCount += 32
                        } else {
                            while bitCount < width {
                                guard position < count else { return false }
                                bitBuffer = bitBuffer << 8 | UInt64(input[position])
                                position += 1; bitCount += 8
                            }
                        }
                    }
                    let code = Int(truncatingIfNeeded: bitBuffer >> UInt64(bitCount - width)) & ((1 << width) - 1)
                    bitCount -= width
                    if code < 256 {
                        guard written < expected else { return false }
                        if previousOffset >= 0, next < 4096 {
                            offset[next] = Int32(previousOffset); length[next] = Int32(previousLength + 1)
                            next += 1
                        }
                        output[written] = UInt8(code)
                        previousOffset = written; previousLength = 1
                        written += 1
                    } else if code == 256 {
                        width = 9; next = 258; widen = 511; previousOffset = -1
                        continue
                    } else if code == 257 {
                        break
                    } else if code < next || (code == next && previousOffset >= 0 && next < 4096) {
                        // 새 항목을 먼저 넣는다. code == next 이면 그 항목이 곧 지금 문자열이다.
                        if previousOffset >= 0, next < 4096 {
                            offset[next] = Int32(previousOffset); length[next] = Int32(previousLength + 1)
                            next += 1
                        } else if code >= next { return false }
                        let source = Int(offset[code]), size = Int(length[code])
                        guard size > 1, written + size <= expected else { return false }
                        // 짧은 문자열은 바로 쓴다(libtiff 와 같은 요령). 긴 것은 앞으로 한 바이트씩 —
                        // code == next 일 때 원본과 대상이 겹친다.
                        let from = output + source, to = output + written
                        if size == 2 {
                            to[0] = from[0]; to[1] = from[1]
                        } else if size == 3 {
                            to[0] = from[0]; to[1] = from[1]; to[2] = from[2]
                        } else if written - source >= size {
                            memcpy(to, from, size)
                        } else {
                            var index = 0
                            while index < size { to[index] = from[index]; index += 1 }
                        }
                        previousOffset = written; previousLength = size
                        written += size
                    } else {
                        return false
                    }
                    if next >= widen, width < 12 { width += 1; widen = (1 << width) - 1 }
                }
                return written == expected
            }}
        }
    }
}
