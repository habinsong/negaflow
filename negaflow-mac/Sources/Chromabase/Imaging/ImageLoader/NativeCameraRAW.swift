import CoreImage
import Darwin
import Foundation

/// Camera RGB is kept as numeric linear data until the negative has been inverted.
/// The RGB packing uses a linear tag; this matrix defines its actual color basis.
public struct CameraToWorkingMatrix: Codable, Equatable, Sendable {
    public let values: [Double]

    public init?(_ values: [Double]) {
        guard values.count == 9, values.allSatisfy(\.isFinite) else { return nil }
        let m = values
        let determinant = m[0] * (m[4] * m[8] - m[5] * m[7])
            - m[1] * (m[3] * m[8] - m[5] * m[6])
            + m[2] * (m[3] * m[7] - m[4] * m[6])
        guard determinant.isFinite, abs(determinant) > 1e-8 else { return nil }
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values = try container.decode([Double].self, forKey: .values)
        guard let matrix = CameraToWorkingMatrix(values) else {
            throw DecodingError.dataCorruptedError(forKey: .values, in: container, debugDescription: "invalid camera matrix")
        }
        self = matrix
    }

    public func apply(to image: CIImage) -> CIImage {
        let m = values
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: m[0], y: m[1], z: m[2], w: 0),
            "inputGVector": CIVector(x: m[3], y: m[4], z: m[5], w: 0),
            "inputBVector": CIVector(x: m[6], y: m[7], z: m[8], w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }
}

public enum NativeCameraRAW {
    private static let propertyKey = "negaflow.cameraToWorking.v1"
    private final class API: @unchecked Sendable {
        typealias Init = @convention(c) (UInt32) -> OpaquePointer?
        typealias Open = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
        typealias Process = @convention(c) (OpaquePointer?) -> Int32
        typealias Close = @convention(c) (OpaquePointer?) -> Void
        typealias SetInt = @convention(c) (OpaquePointer?, Int32) -> Void
        typealias SetFloat = @convention(c) (OpaquePointer?, Float) -> Void
        typealias SetIndexed = @convention(c) (OpaquePointer?, Int32, Float) -> Void
        typealias Matrix = @convention(c) (OpaquePointer?, Int32, Int32) -> Float
        typealias Make = @convention(c) (OpaquePointer?, UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer?
        typealias Clear = @convention(c) (UnsafeMutableRawPointer?) -> Void
        typealias Version = @convention(c) () -> UnsafePointer<CChar>?
        let library: UnsafeMutableRawPointer
        let initialize: Init; let open: Open; let unpack: Process; let process: Process; let close: Close
        let outputColor: SetInt; let outputBits: SetInt; let autoBright: SetInt; let highlight: SetInt
        let maximumThreshold: SetFloat; let gamma: SetIndexed; let userMultiplier: SetIndexed
        let matrix: Matrix; let make: Make; let clear: Clear; let version: Version

        init?(path: String) {
            guard path.hasPrefix("/"), let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { return nil }
            func symbol<T>(_ name: String, _: T.Type) -> T? {
                dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
            }
            guard let initialize = symbol("libraw_init", Init.self),
                  let open = symbol("libraw_open_file", Open.self),
                  let unpack = symbol("libraw_unpack", Process.self),
                  let process = symbol("libraw_dcraw_process", Process.self),
                  let close = symbol("libraw_close", Close.self),
                  let outputColor = symbol("libraw_set_output_color", SetInt.self),
                  let outputBits = symbol("libraw_set_output_bps", SetInt.self),
                  let autoBright = symbol("libraw_set_no_auto_bright", SetInt.self),
                  let highlight = symbol("libraw_set_highlight", SetInt.self),
                  let maximumThreshold = symbol("libraw_set_adjust_maximum_thr", SetFloat.self),
                  let gamma = symbol("libraw_set_gamma", SetIndexed.self),
                  let userMultiplier = symbol("libraw_set_user_mul", SetIndexed.self),
                  let matrix = symbol("libraw_get_rgb_cam", Matrix.self),
                  let make = symbol("libraw_dcraw_make_mem_image", Make.self),
                  let clear = symbol("libraw_dcraw_clear_mem", Clear.self),
                  let version = symbol("libraw_version", Version.self) else { dlclose(library); return nil }
            self.library = library
            self.initialize = initialize; self.open = open; self.unpack = unpack; self.process = process
            self.close = close; self.outputColor = outputColor; self.outputBits = outputBits
            self.autoBright = autoBright; self.highlight = highlight; self.maximumThreshold = maximumThreshold
            self.gamma = gamma; self.userMultiplier = userMultiplier; self.matrix = matrix
            self.make = make; self.clear = clear; self.version = version
        }
    }
    private static let api: API? = {
        let path = ProcessInfo.processInfo.environment["NEGAFLOW_LIBRAW_LIBRARY"]
            ?? Bundle.main.privateFrameworksURL?.appendingPathComponent("libraw.dylib").path
        return path.flatMap(API.init)
    }()
    private struct Key: Hashable { let url: URL; let observation: InputGammaFileObservation }
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var matrices: [Key: CameraToWorkingMatrix] = [:]
        /// 프리뷰 마스터(정착 크기) 최근 사용 순. 마지막이 가장 최근이다.
        var previews: [(key: Key, preview: PreviewMaster)] = []
    }
    /// 정착 크기로 줄인 프리뷰 RGBA16. 인터랙티브·정착처럼 크기가 다른 요청이 LibRaw 를 다시 돌리지 않고
    /// 여기서 파생한다. 크기를 못 맞추는 요청은 캐시하지 않는다.
    private struct PreviewMaster {
        let data: Data
        let width: Int
        let height: Int
        /// LibRaw 가 돌려준 원본 크기. 요청 배율의 기준이다.
        let sourceWidth: Int
        let sourceHeight: Int
        let matrix: CameraToWorkingMatrix
        let libRawVersion: String?
    }
    /// 캐시에 둘 프리뷰 마스터 수와 바이트 상한. 3600px 급 RGBA16 한 장이 약 69MB 다.
    private static let previewCacheEntries = 2
    private static let previewCacheBytes = 160 * 1024 * 1024
    /// 정착 프리뷰 상한(`DevelopFrameRenderer.fullMaxDimension`)과 같아야 한다.
    public static let previewMasterLongSide: CGFloat = 3600
    /// 마스터는 정착 상한보다 이만큼 여유를 둔다. 요청 배율은 ImageIO 가 보고한 원본 크기로 정해지는데
    /// LibRaw 가 돌려주는 크기와 몇 화소 다르다(S5IIX 6000 대 6008). 그 차이로 정착 요청이 상한을 살짝
    /// 넘어 캐시를 못 쓰는 일을 막는다.
    private static let previewMasterHeadroom: CGFloat = 1.02
    private static let cache = Cache()
    public static var isAvailable: Bool { api != nil }

    private static func cachedPreview(for key: Key) -> PreviewMaster? {
        cache.lock.withLock {
            guard let index = cache.previews.firstIndex(where: { $0.key == key }) else { return nil }
            let entry = cache.previews.remove(at: index)
            cache.previews.append(entry)
            return entry.preview
        }
    }

    private static func storePreview(_ preview: PreviewMaster, for key: Key) {
        cache.lock.withLock {
            cache.previews.removeAll { $0.key == key }
            cache.previews.append((key, preview))
            while cache.previews.count > previewCacheEntries
                    || cache.previews.reduce(0, { $0 + $1.preview.data.count }) > previewCacheBytes,
                  cache.previews.count > 1 {
                cache.previews.removeFirst()
            }
        }
    }

    /// 목표 크기. 긴 변 비율을 따르고 원본보다 커지지 않는다.
    static func reducedSize(width: Int, height: Int, scale: CGFloat) -> (width: Int, height: Int) {
        (max(1, min(width, Int((CGFloat(width) * scale).rounded()))),
         max(1, min(height, Int((CGFloat(height) * scale).rounded()))))
    }

    static func decode(_ url: URL, scaleFactor: CGFloat?) -> ImageLoader.DecodedImage? {
        if let scaleFactor { guard scaleFactor.isFinite, scaleFactor > 0, scaleFactor <= 1 else { return nil } }
        guard let api, let observation = try? InputGammaFileObservation.read(url) else { return nil }
        let key = Key(url: url.standardizedFileURL, observation: observation)
        let reduceScale = scaleFactor.flatMap { $0 < 1 ? $0 : nil }
        if let reduceScale, let master = cachedPreview(for: key),
           let image = previewImage(derivedFrom: master, scale: reduceScale) {
            return decoded(tagged(image, matrix: master.matrix), matrix: master.matrix,
                           version: master.libRawVersion, scale: reduceScale)
        }
        guard let handle = api.initialize(0) else { return nil }
        defer { api.close(handle) }
        guard url.path.withCString({ api.open(handle, $0) }) == 0 else { return nil }
        api.outputBits(handle, 16)
        api.outputColor(handle, 0) // Documented camera RGB; no camera-to-sRGB matrix.
        api.gamma(handle, 0, 1); api.gamma(handle, 1, 1)
        api.autoBright(handle, 1); api.maximumThreshold(handle, 0)
        api.highlight(handle, 1)
        for channel in 0..<4 { api.userMultiplier(handle, Int32(channel), 1) }
        guard api.unpack(handle) == 0, api.process(handle) == 0 else { return nil }
        let matrixValues = (0..<9).map { Double(api.matrix(handle, Int32($0 / 3), Int32($0 % 3))) }
        guard let matrix = CameraToWorkingMatrix(matrixValues) else { return nil }
        var error: Int32 = 0
        guard let bitmap = api.make(handle, &error), error == 0 else { return nil }
        defer { api.clear(bitmap) }
        // Public libraw_processed_image_t ABI. No libraw_data_t layout is copied.
        let type = bitmap.load(as: Int32.self)
        let height = Int(bitmap.load(fromByteOffset: 4, as: UInt16.self))
        let width = Int(bitmap.load(fromByteOffset: 6, as: UInt16.self))
        let colors = bitmap.load(fromByteOffset: 8, as: UInt16.self)
        let bits = bitmap.load(fromByteOffset: 10, as: UInt16.self)
        let byteCount = Int(bitmap.load(fromByteOffset: 12, as: UInt32.self))
        guard type == 2, width > 0, height > 0, colors == 3, bits == 16,
              byteCount == width * height * 6 else { return nil }
        let source = bitmap.advanced(by: 16).assumingMemoryBound(to: UInt16.self)
        let version = api.version().map(String.init(cString:))
        var image: CIImage
        if let reduceScale {
            guard let reduced = reducedPreview(
                source, width: width, height: height, scale: reduceScale,
                matrix: matrix, version: version, key: key
            ) else { return nil }
            image = reduced
        } else {
            guard UInt64(width * height) * 8 <= ProcessInfo.processInfo.physicalMemory / 2 else { return nil }
            var pixels = [UInt16](repeating: .max, count: width * height * 4)
            for p in 0..<(width * height) {
                pixels[p * 4] = source[p * 3]; pixels[p * 4 + 1] = source[p * 3 + 1]
                pixels[p * 4 + 2] = source[p * 3 + 2]
            }
            let space = CGColorSpace(name: CGColorSpace.linearSRGB)!
            image = CIImage(bitmapData: pixels.withUnsafeBufferPointer { Data(buffer: $0) },
                bytesPerRow: width * 8, size: CGSize(width: width, height: height), format: .RGBA16, colorSpace: space)
        }
        guard (try? InputGammaFileObservation.read(url)) == observation else { return nil }
        cache.lock.withLock {
            if cache.matrices.count >= 64 { cache.matrices.removeAll(keepingCapacity: true) }
            cache.matrices[key] = matrix
        }
        image = tagged(image, matrix: matrix)
        return decoded(image, matrix: matrix, version: version, scale: scaleFactor ?? 1)
    }

    private static func decoded(
        _ image: CIImage, matrix: CameraToWorkingMatrix, version: String?, scale: CGFloat
    ) -> ImageLoader.DecodedImage {
        ImageLoader.DecodedImage(image: image, provenance: .init(decoder: .libRaw,
            rawDecoderVersion: version, rawScaleFactor: Double(scale), cameraToWorking: matrix))
    }

    /// LibRaw 결과를 `scale` 크기로 줄인다. 정착 크기 이하 요청은 정착 크기 마스터를 거쳐 캐시한다.
    private static func reducedPreview(
        _ source: UnsafePointer<UInt16>, width: Int, height: Int, scale: CGFloat,
        matrix: CameraToWorkingMatrix, version: String?, key: Key
    ) -> CIImage? {
        let target = reducedSize(width: width, height: height, scale: scale)
        let masterScale = min(1, previewMasterLongSide * previewMasterHeadroom / CGFloat(max(width, height)))
        let masterSize = reducedSize(width: width, height: height, scale: masterScale)
        guard target.width <= masterSize.width, target.height <= masterSize.height else {
            guard let pixels = RGB16AreaReduce.reduce(source, width: width, height: height, channels: 3,
                targetWidth: target.width, targetHeight: target.height) else { return nil }
            return previewImage(pixels.withUnsafeBufferPointer { Data(buffer: $0) },
                width: target.width, height: target.height)
        }
        guard let masterPixels = RGB16AreaReduce.reduce(source, width: width, height: height, channels: 3,
            targetWidth: masterSize.width, targetHeight: masterSize.height) else { return nil }
        let master = PreviewMaster(
            data: masterPixels.withUnsafeBufferPointer { Data(buffer: $0) },
            width: masterSize.width, height: masterSize.height, sourceWidth: width, sourceHeight: height,
            matrix: matrix, libRawVersion: version)
        storePreview(master, for: key)
        return previewImage(derivedFrom: master, scale: scale)
    }

    /// 마스터에서 `scale` 크기를 만든다. 마스터보다 큰 요청이면 nil.
    private static func previewImage(derivedFrom master: PreviewMaster, scale: CGFloat) -> CIImage? {
        let target = reducedSize(width: master.sourceWidth, height: master.sourceHeight, scale: scale)
        guard target.width <= master.width, target.height <= master.height else { return nil }
        if target.width == master.width, target.height == master.height {
            return previewImage(master.data, width: master.width, height: master.height)
        }
        let reduced: [UInt16]? = master.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt16.self) else { return nil }
            return RGB16AreaReduce.reduce(base, width: master.width, height: master.height, channels: 4,
                targetWidth: target.width, targetHeight: target.height)
        }
        guard let reduced else { return nil }
        return previewImage(reduced.withUnsafeBufferPointer { Data(buffer: $0) },
            width: target.width, height: target.height)
    }

    private static func previewImage(_ data: Data, width: Int, height: Int) -> CIImage {
        CIImage(bitmapData: data, bytesPerRow: width * 8, size: CGSize(width: width, height: height),
            format: .RGBA16, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
    }

    static func tagged(_ image: CIImage, matrix: CameraToWorkingMatrix) -> CIImage {
        image.settingProperties([propertyKey: matrix.values])
    }

    static func matrix(in image: CIImage) -> CameraToWorkingMatrix? {
        (image.properties[propertyKey] as? [Double]).flatMap(CameraToWorkingMatrix.init)
    }

    /// Raw TIFF is a rendered, uninverted working-RGB export, not a sensor RAW container.
    public static func workingTransmittance(_ image: CIImage) -> CIImage {
        guard let matrix = matrix(in: image) else { return image }
        return matrix.apply(to: image).settingProperties([propertyKey: NSNull()])
    }

    public static func prepare(source: URL, params: DevelopParameters,
                               measurements: inout DevelopSceneMeasurements) throws {
        guard ImageLoader.kind(of: source) == .rawDng, params.filmType.requiresInversion,
              params.isDigitalSource != true else { measurements.cameraToWorking = nil; return }
        let key = Key(url: source.standardizedFileURL, observation: try InputGammaFileObservation.read(source))
        if let matrix = cache.lock.withLock({ cache.matrices[key] }) {
            measurements.cameraToWorking = matrix
        } else {
            guard let decoded = decode(source, scaleFactor: nil), let matrix = decoded.provenance.cameraToWorking else {
                throw ChromabaseError.loadFailed("camera-native RAW decoder unavailable or unsupported output")
            }
            measurements.cameraToWorking = matrix
        }
    }
}
