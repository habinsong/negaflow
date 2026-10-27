import Foundation

// MARK: - TIFFStructure
//
// DNG 는 TIFF 6.0 구조(8바이트 머리말 + IFD 목록)에 태그를 더한 형식이다. 이 파일은 그 구조를
// 리틀엔디언으로 쌓는 작은 기록기다. TIFF 6.0 규격의 레이아웃(IFD = 항목 수 + 12바이트 항목들 +
// 다음 IFD 오프셋, 4바이트를 넘는 값은 짝수 오프셋의 바깥 영역)만 따르며, 이미지 데이터는 다루지 않는다.
// 이미지 줄 데이터는 호출하는 쪽이 머리말 블록 뒤에 이어서 쓴다.

/// IFD 항목 하나. 값은 이미 리틀엔디언 바이트로 인코딩해 가진다.
struct TIFFEntry {
    /// TIFF 6.0 필드 타입 코드(DNG·EXIF 가 같은 코드를 쓴다).
    enum Kind: UInt16 {
        case byte = 1
        case ascii = 2
        case short = 3
        case long = 4
        case rational = 5
        case undefined = 7
        case srational = 10
        case float = 11

        var unitSize: Int {
            switch self {
            case .byte, .ascii, .undefined: 1
            case .short: 2
            case .long, .float: 4
            case .rational, .srational: 8
            }
        }
    }

    let tag: UInt16
    let kind: Kind
    let count: UInt32
    let payload: [UInt8]

    private init(tag: UInt16, kind: Kind, payload: [UInt8]) {
        self.tag = tag
        self.kind = kind
        self.payload = payload
        self.count = UInt32(payload.count / kind.unitSize)
    }

    // MARK: 생성

    static func bytes(_ tag: UInt16, _ values: [UInt8]) -> TIFFEntry {
        TIFFEntry(tag: tag, kind: .byte, payload: values)
    }

    static func undefined(_ tag: UInt16, _ values: [UInt8]) -> TIFFEntry {
        TIFFEntry(tag: tag, kind: .undefined, payload: values)
    }

    static func shorts(_ tag: UInt16, _ values: [UInt16]) -> TIFFEntry {
        var payload: [UInt8] = []
        payload.reserveCapacity(values.count * 2)
        for value in values { payload.appendLE(value) }
        return TIFFEntry(tag: tag, kind: .short, payload: payload)
    }

    static func longs(_ tag: UInt16, _ values: [UInt32]) -> TIFFEntry {
        var payload: [UInt8] = []
        payload.reserveCapacity(values.count * 4)
        for value in values { payload.appendLE(value) }
        return TIFFEntry(tag: tag, kind: .long, payload: payload)
    }

    static func floats(_ tag: UInt16, _ values: [Float]) -> TIFFEntry {
        var payload: [UInt8] = []
        payload.reserveCapacity(values.count * 4)
        for value in values { payload.appendLE(value.bitPattern) }
        return TIFFEntry(tag: tag, kind: .float, payload: payload)
    }

    static func rationals(_ tag: UInt16, _ values: [(numerator: UInt32, denominator: UInt32)]) -> TIFFEntry {
        var payload: [UInt8] = []
        payload.reserveCapacity(values.count * 8)
        for value in values {
            payload.appendLE(value.numerator)
            payload.appendLE(value.denominator)
        }
        return TIFFEntry(tag: tag, kind: .rational, payload: payload)
    }

    static func signedRationals(_ tag: UInt16, _ values: [(numerator: Int32, denominator: Int32)]) -> TIFFEntry {
        var payload: [UInt8] = []
        payload.reserveCapacity(values.count * 8)
        for value in values {
            payload.appendLE(UInt32(bitPattern: value.numerator))
            payload.appendLE(UInt32(bitPattern: value.denominator))
        }
        return TIFFEntry(tag: tag, kind: .srational, payload: payload)
    }

    /// 널로 끝나는 ASCII 문자열. 7비트 밖의 글자는 '?' 로 바꾼다(TIFF ASCII 는 7비트 규격이다).
    static func ascii(_ tag: UInt16, _ text: String) -> TIFFEntry {
        var payload = TIFFEntry.asciiBytes(text)
        payload.append(0)
        return TIFFEntry(tag: tag, kind: .ascii, payload: payload)
    }

    static func asciiBytes(_ text: String) -> [UInt8] {
        text.unicodeScalars.map { $0.isASCII ? UInt8($0.value) : UInt8(ascii: "?") }
    }
}

extension Array where Element == UInt8 {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

// MARK: - 머리말 블록

enum TIFFHeaderBlock {
    /// 이미지 줄 데이터 앞에 오는 블록: 머리말 + IFD0 + 바깥 값 영역 + (있으면) EXIF IFD.
    ///
    /// - `exif` 가 비어 있지 않으면 IFD0 에 EXIF IFD 포인터(태그 34665)를 자동으로 넣는다.
    /// - 항목은 태그 번호 오름차순으로 정렬된다(TIFF 요구사항).
    /// - 블록 크기는 값 내용이 아니라 항목의 개수·타입·개수에만 달려 있다. 호출하는 쪽은
    ///   줄 오프셋 자리에 임시 값을 넣어 한 번 만들어 크기를 잰 뒤 진짜 값으로 다시 만들면 된다.
    static func make(ifd0: [TIFFEntry], exif: [TIFFEntry] = []) -> [UInt8] {
        var main = ifd0
        // 포인터 값은 EXIF IFD 위치를 안 뒤에 고쳐 쓴다. 자리만 먼저 잡는다.
        let exifPointerTag: UInt16 = 34665
        if !exif.isEmpty { main.append(.longs(exifPointerTag, [0])) }
        main.sort { $0.tag < $1.tag }

        var block: [UInt8] = [0x49, 0x49, 42, 0]   // "II" + 42, 리틀엔디언
        block.appendLE(UInt32(8))                  // IFD0 오프셋

        var exifPointerFieldOffset: Int?
        writeDirectory(main, into: &block, patchTag: exif.isEmpty ? nil : exifPointerTag,
                       patchOffset: &exifPointerFieldOffset)
        if !exif.isEmpty {
            // 바깥 값 영역이 끝난 자리가 EXIF IFD 위치다(짝수로 맞춘다).
            alignEven(&block)
            let exifOffset = UInt32(block.count)
            if let field = exifPointerFieldOffset { patch(&block, at: field, with: exifOffset) }
            var unused: Int?
            writeDirectory(exif.sorted { $0.tag < $1.tag }, into: &block, patchTag: nil, patchOffset: &unused)
        }
        return block
    }

    /// 디렉터리 하나(IFD + 자기 바깥 값 영역)를 `block` 끝에 쓴다. 반환값은 쓴 바깥 영역 바이트 수.
    @discardableResult
    private static func writeDirectory(
        _ entries: [TIFFEntry], into block: inout [UInt8],
        patchTag: UInt16?, patchOffset: inout Int?
    ) -> Int {
        alignEven(&block)
        let directoryStart = block.count
        let directorySize = 2 + entries.count * 12 + 4
        var outOfLineCursor = directoryStart + directorySize
        var outOfLine: [UInt8] = []

        block.appendLE(UInt16(entries.count))
        for entry in entries {
            block.appendLE(entry.tag)
            block.appendLE(entry.kind.rawValue)
            block.appendLE(entry.count)
            if entry.payload.count <= 4 {
                if entry.tag == patchTag { patchOffset = block.count }
                block.append(contentsOf: entry.payload)
                block.append(contentsOf: [UInt8](repeating: 0, count: 4 - entry.payload.count))
            } else {
                if outOfLineCursor % 2 != 0 {
                    outOfLine.append(0)
                    outOfLineCursor += 1
                }
                block.appendLE(UInt32(outOfLineCursor))
                outOfLine.append(contentsOf: entry.payload)
                outOfLineCursor += entry.payload.count
            }
        }
        block.appendLE(UInt32(0))   // 다음 IFD 없음
        block.append(contentsOf: outOfLine)
        return outOfLine.count
    }

    private static func alignEven(_ block: inout [UInt8]) {
        if block.count % 2 != 0 { block.append(0) }
    }

    private static func patch(_ block: inout [UInt8], at offset: Int, with value: UInt32) {
        block[offset] = UInt8(truncatingIfNeeded: value)
        block[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        block[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        block[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}
