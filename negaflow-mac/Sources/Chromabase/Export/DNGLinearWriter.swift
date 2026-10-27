import Foundation
import CoreImage
import CoreGraphics
import simd

// MARK: - DNGLinearWriter
//
// 현상한 화상을 16비트 선형 RGB DNG(PhotometricInterpretation = LinearRaw)로 쓴다.
//
// 이 파일은 Adobe DNG 규격 1.6 에 적힌 태그 번호·의미만 보고 새로 작성했다. Adobe DNG SDK, LibRaw,
// 다른 DNG 기록기의 코드는 보거나 옮기지 않았다. DNG 는 Adobe 의 등록 상표이며 이 앱은 규격이 공개한
// 파일 형식을 쓸 뿐이다(docs/legal/PROVENANCE.md).
//
// This product includes DNG technology under license by Adobe.
//
// 담는 것
// - 화소: 사용자가 고른 출력 색공간(sRGB · Display P3 · Adobe RGB)의 **선형** 값 16비트 3채널.
//   현상 파이프라인의 출력이므로 톤·색은 이미 구워져 있다(장면 기준이 아니라 출력 기준 데이터).
// - 색 해석: ColorMatrix1(XYZ → 그 공간의 RGB)과 AsShotNeutral(1,1,1), CalibrationIlluminant1(D65).
//   DNG 의 색 모델은 카메라 중립점을 XYZ 백색으로 옮긴 뒤 D50 으로 적응하므로, 이 값이면 읽는
//   쪽이 원래 색공간의 색을 그대로 복원한다.
// - ColorimetricReference = 1(출력 기준)과 항등 톤 곡선, 검정 렌더 없음: 읽는 쪽이 장면 기준 기본
//   톤 곡선을 한 번 더 얹지 않도록 하는 힌트다. 앱마다 해석이 다를 수 있어 외관은 실제 변환기로
//   확인해야 한다(여기서는 구조와 화소값만 시험으로 확인한다).
//
// 담지 않는 것
// - 압축: 16비트 정수 LinearRaw 에 쓸 수 있는 DNG 압축은 무손실 JPEG 뿐이라 무압축으로 쓴다.
// - 원본 카메라 EXIF·IPTC·GPS 전체: 저작권(Artist·Copyright), 촬영일, 스캐너 정보, 필름 기록만 담는다.
// - 미리보기 이미지: 읽는 쪽이 화소에서 직접 그린다.
enum DNGLinearWriter {
    /// 한 줄 묶음(strip)의 목표 크기(RGB 16비트 기준). 렌더·복사·쓰기 단위이자 메모리 상한이다.
    static let targetStripBytes = 4 << 20
    /// 32비트 오프셋으로 표현할 수 있는 파일 크기의 안전 한도.
    static let maximumFileBytes: UInt64 = 4_000_000_000

    // DNG·TIFF 태그 번호(규격 표기).
    private enum Tag {
        static let newSubfileType: UInt16 = 254
        static let imageWidth: UInt16 = 256
        static let imageLength: UInt16 = 257
        static let bitsPerSample: UInt16 = 258
        static let compression: UInt16 = 259
        static let photometric: UInt16 = 262
        static let make: UInt16 = 271
        static let model: UInt16 = 272
        static let stripOffsets: UInt16 = 273
        static let orientation: UInt16 = 274
        static let samplesPerPixel: UInt16 = 277
        static let rowsPerStrip: UInt16 = 278
        static let stripByteCounts: UInt16 = 279
        static let xResolution: UInt16 = 282
        static let yResolution: UInt16 = 283
        static let planarConfiguration: UInt16 = 284
        static let resolutionUnit: UInt16 = 296
        static let software: UInt16 = 305
        static let dateTime: UInt16 = 306
        static let artist: UInt16 = 315
        static let copyright: UInt16 = 33432
        // EXIF IFD 안
        static let exifVersion: UInt16 = 36864
        static let dateTimeOriginal: UInt16 = 36867
        static let dateTimeDigitized: UInt16 = 36868
        static let offsetTime: UInt16 = 36880
        static let offsetTimeOriginal: UInt16 = 36881
        static let offsetTimeDigitized: UInt16 = 36882
        static let userComment: UInt16 = 37510
        // DNG
        static let dngVersion: UInt16 = 50706
        static let dngBackwardVersion: UInt16 = 50707
        static let uniqueCameraModel: UInt16 = 50708
        static let whiteLevel: UInt16 = 50717
        static let colorMatrix1: UInt16 = 50721
        static let asShotNeutral: UInt16 = 50728
        static let calibrationIlluminant1: UInt16 = 50778
        static let colorimetricReference: UInt16 = 50879
        static let profileName: UInt16 = 50936
        static let profileToneCurve: UInt16 = 50940
        static let profileEmbedPolicy: UInt16 = 50941
        static let defaultBlackRender: UInt16 = 51110
    }

    /// PhotometricInterpretation 값: LinearRaw.
    private static let photometricLinearRaw: UInt16 = 34892

    static func write(
        _ image: CIImage,
        to url: URL,
        using context: CIContext,
        metadata: ExportMeta?,
        options: ExportOptions,
        stripBytes: Int = DNGLinearWriter.targetStripBytes
    ) throws {
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1,
              extent.width < 65_536 * 4, extent.height < 65_536 * 4 else {
            throw ChromabaseError.writeFailed("DNG: invalid image size")
        }
        let width = Int(extent.width)
        let height = Int(extent.height)
        let space = options.colorSpace.dngSpace
        guard isLinearSRGBWorkingSpace(context.workingColorSpace),
              let conversion = space.conversion(fromLinear: .sRGB) else {
            throw ChromabaseError.writeFailed("DNG: unsupported color management setup")
        }

        let rgbRowBytes = width * 6
        let (rowsPerStrip, stripCount) = stripLayout(width: width, height: height, stripBytes: stripBytes)
        let pixelBytes = UInt64(rgbRowBytes) * UInt64(height)
        let entries = headerEntries(
            width: width, height: height, rowsPerStrip: rowsPerStrip, stripCount: stripCount,
            rgbRowBytes: rgbRowBytes, space: space, metadata: metadata, options: options)
        // 블록 크기는 줄 오프셋 값이 아니라 항목 구성에만 달렸다. 임시 오프셋으로 한 번 만들어 크기를 잰다.
        let exif = exifEntries(metadata: metadata)
        let sizingBlock = TIFFHeaderBlock.make(
            ifd0: entries([UInt32](repeating: 0, count: stripCount)), exif: exif)
        let pixelStart = (sizingBlock.count + 15) & ~15
        guard UInt64(pixelStart) + pixelBytes < maximumFileBytes else {
            throw ChromabaseError.writeFailed("DNG: image too large for a 32-bit TIFF container")
        }
        var offsets: [UInt32] = []
        offsets.reserveCapacity(stripCount)
        for strip in 0..<stripCount {
            offsets.append(UInt32(pixelStart + strip * rowsPerStrip * rgbRowBytes))
        }
        var block = TIFFHeaderBlock.make(ifd0: entries(offsets), exif: exif)
        precondition(block.count == sizingBlock.count, "DNG header size must not depend on offset values")
        block.append(contentsOf: [UInt8](repeating: 0, count: pixelStart - block.count))

        // 색공간 변환 행렬(선형 sRGB 작업공간 → 출력 공간). sRGB 면 항등이라 건너뛴다.
        let converted = space == .sRGB ? image : applying(conversion, to: image)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle: FileHandle
        do { handle = try FileHandle(forWritingTo: url) } catch {
            throw ChromabaseError.writeFailed("DNG: cannot open \(url.path)")
        }
        var finished = false
        defer {
            try? handle.close()
            if !finished { try? FileManager.default.removeItem(at: url) }
        }
        try handle.write(contentsOf: Data(block))

        // 줄 묶음마다: 렌더(RGBA16) → RGB16 으로 복사 → 파일에 이어 쓰기. 쓰기는 다른 스레드가 하고,
        // 그 사이 이쪽은 다음 묶음을 렌더한다(RGB 버퍼 둘을 번갈아 쓴다). 메모리는 RGBA 하나와 RGB 둘뿐이다.
        let rgbaBytesPerStrip = rowsPerStrip * width * 8
        let rgbBytesPerStrip = rowsPerStrip * rgbRowBytes
        let rgba = UnsafeMutableRawPointer.allocate(byteCount: rgbaBytesPerStrip, alignment: 16)
        let rgbBuffers = (0..<2).map { _ in
            UnsafeMutableRawPointer.allocate(byteCount: rgbBytesPerStrip, alignment: 16)
        }
        let writer = StripWriter(handle: handle)
        defer {
            // 쓰기 스레드가 버퍼를 다 놓은 뒤에 해제한다. 오류로 빠져나올 때도 마찬가지다.
            writer.drain()
            rgba.deallocate()
            rgbBuffers.forEach { $0.deallocate() }
        }
        guard let linearSRGB = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            throw ChromabaseError.writeFailed("DNG: linear sRGB unavailable")
        }
        for strip in 0..<stripCount {
            let firstRow = strip * rowsPerStrip
            let rows = min(rowsPerStrip, height - firstRow)
            // 이 버퍼를 쓰던 앞의 쓰기가 끝날 때까지 기다린다. 쓰기가 실패했으면 더 렌더하지 않는다.
            try writer.waitForFreeBuffer()
            // CIImage 의 y 는 아래에서 위로 자란다. 파일의 첫 줄이 화상의 맨 위 줄이다.
            let bounds = CGRect(
                x: extent.minX, y: extent.maxY - CGFloat(firstRow + rows),
                width: extent.width, height: CGFloat(rows))
            context.render(
                converted, toBitmap: rgba, rowBytes: width * 8, bounds: bounds,
                format: .RGBA16, colorSpace: linearSRGB)
            let rgb = rgbBuffers[strip % 2]
            compactRGBA16(rgba, to: rgb, pixelCount: rows * width)
            writer.submit(rgb, byteCount: rows * rgbRowBytes)
        }
        try writer.finish()
        finished = true
    }

    // MARK: 구성 요소

    /// 줄 데이터를 다른 스레드에서 순서대로 쓴다. 한 번에 버퍼 둘까지만 걸려 있게 세마포어로 막는다.
    /// 쓰기 오류는 첫 것만 기억하고, 호출한 쪽이 다음 묶음 앞(`waitForFreeBuffer`)이나 끝(`finish`)에서 받는다.
    private final class StripWriter: @unchecked Sendable {
        private let handle: FileHandle
        private let queue = DispatchQueue(label: "negaflow.dng.write")
        private let freeBuffers = DispatchSemaphore(value: 2)
        private let lock = NSLock()
        private var firstError: Error?

        init(handle: FileHandle) { self.handle = handle }

        func waitForFreeBuffer() throws {
            freeBuffers.wait()
            if let error = recordedError() {
                freeBuffers.signal()
                throw error
            }
        }

        /// 세마포어가 한 번에 하나의 쓰기만 이 버퍼를 보게 하므로 스레드 사이로 넘겨도 안전하다.
        private struct Buffer: @unchecked Sendable { let pointer: UnsafeMutableRawPointer }

        func submit(_ buffer: UnsafeMutableRawPointer, byteCount: Int) {
            let pointer = Buffer(pointer: buffer)
            queue.async { [self] in
                defer { freeBuffers.signal() }
                guard recordedError() == nil else { return }
                do {
                    try handle.write(contentsOf: Data(bytesNoCopy: pointer.pointer, count: byteCount, deallocator: .none))
                } catch {
                    record(error)
                }
            }
        }

        /// 걸려 있는 쓰기를 모두 기다린다. 해제 전에 부른다.
        func drain() { queue.sync {} }

        func finish() throws {
            drain()
            if let error = recordedError() { throw error }
        }

        private func recordedError() -> Error? {
            lock.lock(); defer { lock.unlock() }
            return firstError
        }

        private func record(_ error: Error) {
            lock.lock(); defer { lock.unlock() }
            if firstError == nil { firstError = error }
        }
    }

    /// 한 묶음의 줄 수와 묶음 개수.
    static func stripLayout(width: Int, height: Int, stripBytes: Int) -> (rowsPerStrip: Int, stripCount: Int) {
        let rowBytes = max(1, width * 6)
        let rows = max(1, min(height, stripBytes / rowBytes))
        return (rows, (height + rows - 1) / rows)
    }

    /// 컨텍스트의 작업 색공간이 이 기록기의 전제(선형 sRGB 기준 값)와 맞는지.
    /// 색 관리를 끈 컨텍스트(nil)는 값을 그대로 쓰므로 같은 전제로 읽는다.
    static func isLinearSRGBWorkingSpace(_ space: CGColorSpace?) -> Bool {
        guard let space else { return true }
        let accepted = [CGColorSpace.linearSRGB, CGColorSpace.extendedLinearSRGB]
        return accepted.contains { name in
            CGColorSpace(name: name).map { CFEqual($0, space) } ?? false
        }
    }

    /// RGBA16(premultiplied, 알파 1)에서 RGB16 만 이어 붙인다. 알파는 항상 1 이라 값은 그대로다.
    static func compactRGBA16(_ rgba: UnsafeRawPointer, to rgb: UnsafeMutableRawPointer, pixelCount: Int) {
        let source = rgba.assumingMemoryBound(to: UInt16.self)
        let destination = rgb.assumingMemoryBound(to: UInt16.self)
        var read = 0
        var write = 0
        for _ in 0..<pixelCount {
            destination[write] = source[read]
            destination[write + 1] = source[read + 1]
            destination[write + 2] = source[read + 2]
            read += 4
            write += 3
        }
    }

    private static func applying(_ matrix: simd_double3x3, to image: CIImage) -> CIImage {
        // CIColorMatrix 의 inputRVector 는 출력 R 을 만드는 행(R'=r·x+g·y+b·z)이다.
        func row(_ index: Int) -> CIVector {
            CIVector(x: matrix[0][index], y: matrix[1][index], z: matrix[2][index], w: 0)
        }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": row(0),
            "inputGVector": row(1),
            "inputBVector": row(2),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }

    /// IFD0 항목을 만드는 함수. 줄 오프셋만 나중에 채운다.
    private static func headerEntries(
        width: Int, height: Int, rowsPerStrip: Int, stripCount: Int, rgbRowBytes: Int,
        space: DNGRGBSpace, metadata: ExportMeta?, options: ExportOptions
    ) -> (_ stripOffsets: [UInt32]) -> [TIFFEntry] {
        var byteCounts: [UInt32] = []
        byteCounts.reserveCapacity(stripCount)
        for strip in 0..<stripCount {
            let rows = min(rowsPerStrip, height - strip * rowsPerStrip)
            byteCounts.append(UInt32(rows * rgbRowBytes))
        }
        let matrix = space.xyzToRGB
        var colorMatrix: [(numerator: Int32, denominator: Int32)] = []
        for row in 0..<3 {
            for column in 0..<3 {
                colorMatrix.append((Int32((matrix[column][row] * 1_000_000).rounded()), 1_000_000))
            }
        }
        let base = baseEntries(metadata: metadata, options: options)
        return { stripOffsets in
            var entries: [TIFFEntry] = [
                .longs(Tag.newSubfileType, [0]),
                .longs(Tag.imageWidth, [UInt32(width)]),
                .longs(Tag.imageLength, [UInt32(height)]),
                .shorts(Tag.bitsPerSample, [16, 16, 16]),
                .shorts(Tag.compression, [1]),
                .shorts(Tag.photometric, [photometricLinearRaw]),
                .longs(Tag.stripOffsets, stripOffsets),
                .shorts(Tag.orientation, [1]),   // 변형은 화소에 구워져 있다
                .shorts(Tag.samplesPerPixel, [3]),
                .longs(Tag.rowsPerStrip, [UInt32(rowsPerStrip)]),
                .longs(Tag.stripByteCounts, byteCounts),
                .shorts(Tag.planarConfiguration, [1]),
                .bytes(Tag.dngVersion, [1, 4, 0, 0]),
                .bytes(Tag.dngBackwardVersion, [1, 1, 0, 0]),
                .ascii(Tag.uniqueCameraModel, "Negaflow Developed \(options.colorSpace.uiLabel)"),
                .shorts(Tag.whiteLevel, [65535, 65535, 65535]),
                .signedRationals(Tag.colorMatrix1, colorMatrix),
                .rationals(Tag.asShotNeutral, [(1, 1), (1, 1), (1, 1)]),
                .shorts(Tag.calibrationIlluminant1, [DNGRGBSpace.d65LightSourceCode]),
                .shorts(Tag.colorimetricReference, [1]),
                .ascii(Tag.profileName, "Negaflow Linear Output"),
                .floats(Tag.profileToneCurve, [0, 0, 1, 1]),
                .longs(Tag.profileEmbedPolicy, [3]),
                .longs(Tag.defaultBlackRender, [1]),
            ]
            entries.append(contentsOf: base)
            return entries
        }
    }

    /// 메타데이터 정책에 따라 싣는 TIFF 쪽 항목. TIFF 내보내기(`ExportEngine.metadataProperties`)와
    /// 같은 규칙이다: 저작권만 남기는 정책은 장비·소프트웨어·날짜·해상도를 적지 않는다.
    private static func baseEntries(metadata: ExportMeta?, options: ExportOptions) -> [TIFFEntry] {
        var entries: [TIFFEntry] = []
        guard let metadata else {
            entries.append(.ascii(Tag.software, "Negaflow"))
            return entries
        }
        if identifiesEquipment(metadata) {
            entries.append(.ascii(Tag.software, metadata.software ?? "Negaflow"))
            if let make = metadata.scannerMake { entries.append(.ascii(Tag.make, make)) }
            if let model = metadata.scannerModel { entries.append(.ascii(Tag.model, model)) }
            if let date = metadata.metadataDate {
                entries.append(.ascii(Tag.dateTime, ExportEngine.exifTimestamp(date)))
            }
            if let dpi = metadata.resolutionDPI, dpi > 0 {
                entries.append(.rationals(Tag.xResolution, [(UInt32(dpi), 1)]))
                entries.append(.rationals(Tag.yResolution, [(UInt32(dpi), 1)]))
                entries.append(.shorts(Tag.resolutionUnit, [2]))   // 인치
            }
        }
        // 저작권 정보는 원본 메타데이터를 읽을 수 있는 정책에서만 옮긴다(TIFF 내보내기와 같은 정책).
        if let source = metadata.sourceMetadata?.filtered(for: metadata.metadataPolicy) {
            if case let .string(artist)? = source.tiff["Artist"] { entries.append(.ascii(Tag.artist, artist)) }
            if case let .string(copyright)? = source.tiff["Copyright"] {
                entries.append(.ascii(Tag.copyright, copyright))
            }
        }
        return entries
    }

    private static func identifiesEquipment(_ metadata: ExportMeta) -> Bool {
        metadata.metadataPolicy != .copyrightOnly
    }

    /// EXIF IFD 항목: 촬영일과 필름 기록. 둘 다 없으면 비어 있어 IFD 를 만들지 않는다.
    private static func exifEntries(metadata: ExportMeta?) -> [TIFFEntry] {
        guard let metadata, identifiesEquipment(metadata) else { return [] }
        var entries: [TIFFEntry] = []
        if let sourceDate = metadata.sourceDate {
            let stamp = ExportEngine.exifTimestamp(sourceDate)
            entries.append(.ascii(Tag.dateTimeOriginal, stamp))
            entries.append(.ascii(Tag.dateTimeDigitized, stamp))
            // 시각은 UTC 로 적는다. 오프셋이 없으면 읽는 쪽이 제 시간대로 해석해 어긋난다.
            entries.append(.ascii(Tag.offsetTimeOriginal, "+00:00"))
            entries.append(.ascii(Tag.offsetTimeDigitized, "+00:00"))
        }
        if metadata.metadataDate != nil {
            entries.append(.ascii(Tag.offsetTime, "+00:00"))
        }
        // 필름 스톡은 사용자가 적은 촬영 기록이라 metadata 를 비우기로 한 정책에서는 싣지 않는다.
        let filmStock = metadata.metadataPolicy == .minimal ? nil : metadata.filmStock
        let comment = [
            metadata.filmType.map { "FilmType: \($0)" },
            filmStock.map { "FilmStock: \($0)" },
        ].compactMap { $0 }.joined(separator: "; ")
        if !comment.isEmpty {
            // EXIF UserComment: 앞 8바이트가 문자 코드 표시("ASCII" + 널 세 개)다.
            entries.append(.undefined(Tag.userComment, Array("ASCII\0\0\0".utf8) + TIFFEntry.asciiBytes(comment)))
        }
        if !entries.isEmpty {
            entries.append(.undefined(Tag.exifVersion, Array("0231".utf8)))
        }
        return entries
    }
}
