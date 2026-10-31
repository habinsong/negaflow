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
        typealias FunctionName = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
        typealias PreviewMode = @convention(c) (OpaquePointer?, Int32) -> Int32
        typealias PreviewSize = @convention(c) (OpaquePointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Int32
        typealias MakePreview = @convention(c) (OpaquePointer?, Int32, Int32) -> UnsafeMutableRawPointer?
        let library: UnsafeMutableRawPointer
        let initialize: Init; let open: Open; let unpack: Process; let process: Process; let close: Close
        let outputColor: SetInt; let outputBits: SetInt; let autoBright: SetInt; let highlight: SetInt
        let maximumThreshold: SetFloat; let gamma: SetIndexed; let userMultiplier: SetIndexed
        let matrix: Matrix; let make: Make; let clear: Clear; let version: Version
        let unpackFunctionName: FunctionName?
        let previewMode: PreviewMode?
        let freeImage: Close?
        let cancel: Close?
        let previewSize: PreviewSize?
        let makePreview: MakePreview?

        init?(path: String) {
            guard path.hasPrefix("/"), let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { return nil }
            func symbol<T>(_ name: String, _: T.Type) -> T? {
                dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
            }
            // negaflow_libraw_init 은 LibRaw 의 화소 루프 셋을 모든 코어로 도는 하위 클래스를 만든다
            // (native-preview-bridge.cpp). 같은 결과이고, 없는 빌드면 기본 생성자를 쓴다.
            guard let initialize = symbol("negaflow_libraw_init", Init.self) ?? symbol("libraw_init", Init.self),
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
            unpackFunctionName = symbol("libraw_unpack_function_name", FunctionName.self)
            previewMode = symbol("negaflow_libraw_preview_mode", PreviewMode.self)
            freeImage = symbol("libraw_free_image", Close.self)
            cancel = symbol("negaflow_libraw_cancel", Close.self)
            previewSize = symbol("negaflow_libraw_preview_size", PreviewSize.self)
            makePreview = symbol("negaflow_libraw_make_preview", MakePreview.self)
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
        var previewEntries = 2
        var previewBytes = 160 * 1024 * 1024
        var generation: UInt64 = 0
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
    /// 정착 프리뷰 상한(`DevelopFrameRenderer.fullMaxDimension`)과 같아야 한다.
    public static let previewMasterLongSide: CGFloat = 3600
    /// ImageIO와 LibRaw의 원본 치수가 달라도 마스터가 이 상한보다 커지지 않게 한다.
    private static let previewMasterHeadroom: CGFloat = 1.02
    private static let cache = Cache()
    /// 같은 파일을 동시에 요청하면 한 번만 디코드하고 마스터를 나눠 쓴다. 키로 나눈 잠금이라 다른
    /// 파일은 대부분 따로 돈다(LibRaw 는 OpenMP 로 이미 모든 코어를 쓰므로 겹쳐도 처리량은 같다).
    private static let decodeGates = (0..<16).map { _ in NSLock() }
    public static var isAvailable: Bool { api != nil }

    /// 앱이 메모리 압박을 받을 때 프리뷰 마스터를 내려놓는다. 다음 요청은 원본에서 다시 만든다.
    public static func purgePreviewCache() {
        cache.lock.withLock {
            cache.generation &+= 1
            cache.previews.removeAll()
        }
    }

    public static func discardPreview(for url: URL) {
        cache.lock.withLock {
            cache.previews.removeAll { $0.key.url == url.standardizedFileURL }
        }
    }

    /// 앱의 자동/수동 상주 한도 중 여유 프레임 안에서만 다음 사진을 보관한다.
    public static func setPreviewCacheResidencyLimit(_ residentFrames: Int) {
        cache.lock.withLock {
            let entries = min(2, max(0, residentFrames - 1))
            if entries != cache.previewEntries { cache.generation &+= 1 }
            cache.previewEntries = entries
            cache.previewBytes = entries * 80 * 1024 * 1024
            trimPreviews()
        }
    }

    static var previewCacheUsage: (entries: Int, bytes: Int, limit: Int) {
        cache.lock.withLock {
            (cache.previews.count, cache.previews.reduce(0) { $0 + $1.preview.data.count }, cache.previewEntries)
        }
    }

    public enum ProgressivePhase: @unchecked Sendable {
        case first(CGImage)
        case ready(CGImage)
    }

    public final class ProgressivePreview: @unchecked Sendable {
        public let updates: AsyncThrowingStream<ProgressivePhase, Error>
        private let cancelWork: @Sendable () -> Void
        private let worker: Task<Void, Never>

        fileprivate init(updates: AsyncThrowingStream<ProgressivePhase, Error>,
                         worker: Task<Void, Never>,
                         cancelWork: @escaping @Sendable () -> Void) {
            self.updates = updates
            self.worker = worker
            self.cancelWork = cancelWork
        }

        public func cancel() { cancelWork() }
        public func cancelAndWait() async {
            cancelWork()
            await worker.value
        }
        deinit { cancelWork() }
    }

    /// 취소와 핸들 해제를 같은 잠금으로 직렬화한다.
    private final class ProgressiveControl: @unchecked Sendable {
        let api: API
        private let lock = NSLock()
        private var handle: OpaquePointer?
        private var cancelled = false

        init(api: API) { self.api = api }
        func attach(_ handle: OpaquePointer) {
            lock.withLock {
                self.handle = handle
                if cancelled { api.cancel?(handle) }
            }
        }
        func detach() { lock.withLock { handle = nil } }
        func cancel() {
            lock.withLock {
                guard !cancelled else { return }
                cancelled = true
                if let handle { api.cancel?(handle) }
            }
        }
    }

    public static var supportsProgressivePreview: Bool {
        api?.previewMode != nil && api?.freeImage != nil && api?.cancel != nil
    }

    /// 원본은 한 번만 읽는다. 첫 입력은 임시 표시용이며 정착 마스터 캐시에는 넣지 않는다.
    public static func beginProgressivePreview(_ url: URL, firstMaxDimension: CGFloat) -> ProgressivePreview? {
        guard supportsProgressivePreview, let api,
              firstMaxDimension.isFinite, firstMaxDimension >= 1,
              firstMaxDimension <= previewMasterLongSide,
              let observation = try? InputGammaFileObservation.read(url) else { return nil }
        let key = Key(url: url.standardizedFileURL, observation: observation)
        guard cache.lock.withLock({ !cache.previews.contains(where: { $0.key == key }) }) else { return nil }
        let (updates, continuation) = AsyncThrowingStream<ProgressivePhase, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(2))
        let control = ProgressiveControl(api: api)
        let worker = Task.detached(priority: .userInitiated) {
            do {
                try produceProgressivePreview(url, firstMaxDimension: firstMaxDimension,
                    control: control, continuation: continuation)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let cancel: @Sendable () -> Void = { control.cancel(); worker.cancel() }
        continuation.onTermination = { termination in
            if case .cancelled = termination { cancel() }
        }
        return ProgressivePreview(updates: updates, worker: worker, cancelWork: cancel)
    }

    private static func produceProgressivePreview(
        _ url: URL, firstMaxDimension: CGFloat, control: ProgressiveControl,
        continuation: AsyncThrowingStream<ProgressivePhase, Error>.Continuation
    ) throws {
        try Task.checkCancellation()
        guard let observation = try? InputGammaFileObservation.read(url) else {
            throw ChromabaseError.loadFailed("camera-native RAW source unavailable")
        }
        let key = Key(url: url.standardizedFileURL, observation: observation)
        let gate = decodeGates[Int(UInt(bitPattern: key.hashValue) % UInt(decodeGates.count))]
        gate.lock()
        defer { gate.unlock() }
        try Task.checkCancellation()
        if let master = cachedPreview(for: key),
           let image = previewImage(master.data, width: master.width, height: master.height) {
            continuation.yield(.ready(image))
            return
        }
        let api = control.api
        let generation = cache.lock.withLock { cache.generation }
        guard let handle = api.initialize(0) else {
            throw ChromabaseError.loadFailed("camera-native RAW decoder unavailable")
        }
        control.attach(handle)
        defer { control.detach(); api.close(handle) }
        guard url.path.withCString({ api.open(handle, $0) }) == 0 else {
            throw ChromabaseError.loadFailed("camera-native RAW open failed")
        }
        try Task.checkCancellation()
        configure(api, handle)
        guard api.unpack(handle) == 0 else {
            throw ChromabaseError.loadFailed("camera-native RAW unpack failed")
        }
        try Task.checkCancellation()
        if api.previewMode?(handle, Int32(firstMaxDimension.rounded(.up))) == 1 {
            guard api.process(handle) == 0,
                  let first = captureOutput(api, handle, key: key, request: .first(firstMaxDimension)),
                  let raster = first.rasterImage else {
                throw ChromabaseError.loadFailed("camera-native RAW first preview failed")
            }
            try Task.checkCancellation()
            continuation.yield(.first(raster))
            api.freeImage?(handle)
            _ = api.previewMode?(handle, 0)
        }
        try Task.checkCancellation()
        guard api.process(handle) == 0,
              let settled = captureOutput(api, handle, key: key, request: .master, generation: generation)?.rasterImage else {
            throw ChromabaseError.loadFailed("camera-native RAW settled preview failed")
        }
        try Task.checkCancellation()
        continuation.yield(.ready(settled))
    }

    /// 다음 사진의 정착 프리뷰 마스터를 준비한다. 화면·필름 베이스·현상 설정은 바꾸지 않는다.
    public static func prefetchPreviewMaster(_ url: URL) {
        guard !Task.isCancelled, cache.lock.withLock({ cache.previewEntries > 0 }) else { return }
        _ = decode(url, scaleFactor: 0.05)
    }

    public static func prefetchPreviewMasterUntilCancelled(_ url: URL) async {
        guard !Task.isCancelled, let api,
              cache.lock.withLock({ cache.previewEntries > 0 }) else { return }
        let control = ProgressiveControl(api: api)
        await withTaskCancellationHandler {
            _ = decode(url, scaleFactor: 0.05, control: control)
        } onCancel: {
            control.cancel()
        }
    }

    /// `NEGAFLOW_RAW_TRACE=1` 이면 디코드 단계별 소요를 표준 오류에 남긴다(앱 실측용).
    private static let traceEnabled = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TRACE"] == "1"
    private static func trace(_ url: URL, _ message: @autoclosure () -> String) {
        guard traceEnabled else { return }
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e6
        FileHandle.standardError.write(Data(String(format: "[raw] t=%.0f %@ %@\n", now, url.lastPathComponent, message()).utf8))
    }
    private static func milliseconds(since start: UInt64) -> String {
        milliseconds(DispatchTime.now().uptimeNanoseconds - start)
    }
    private static func milliseconds(_ nanoseconds: UInt64) -> String {
        String(format: "%.0f", Double(nanoseconds) / 1e6)
    }

    private static func cachedPreview(for key: Key) -> PreviewMaster? {
        cache.lock.withLock {
            guard let index = cache.previews.firstIndex(where: { $0.key == key }) else { return nil }
            let entry = cache.previews.remove(at: index)
            cache.previews.append(entry)
            return entry.preview
        }
    }

    private static func storePreview(_ preview: PreviewMaster, for key: Key, generation: UInt64) {
        cache.lock.withLock {
            guard generation == cache.generation, cache.previewEntries > 0,
                  preview.data.count <= cache.previewBytes else { return }
            cache.previews.removeAll { $0.key == key }
            cache.previews.append((key, preview))
            trimPreviews()
        }
    }

    /// cache.lock을 잡은 상태에서 호출한다.
    private static func trimPreviews() {
        while cache.previews.count > cache.previewEntries
                || cache.previews.reduce(0, { $0 + $1.preview.data.count }) > cache.previewBytes {
            cache.previews.removeFirst()
        }
    }

    /// 목표 크기. 긴 변 비율을 따르고 원본보다 커지지 않는다.
    static func reducedSize(width: Int, height: Int, scale: CGFloat) -> (width: Int, height: Int) {
        (max(1, min(width, Int((CGFloat(width) * scale).rounded()))),
         max(1, min(height, Int((CGFloat(height) * scale).rounded()))))
    }

    static func decode(_ url: URL, scaleFactor: CGFloat?) -> ImageLoader.DecodedImage? {
        decode(url, scaleFactor: scaleFactor, control: nil)
    }

    private static func decode(_ url: URL, scaleFactor: CGFloat?, control: ProgressiveControl?) -> ImageLoader.DecodedImage? {
        if let scaleFactor { guard scaleFactor.isFinite, scaleFactor > 0, scaleFactor <= 1 else { return nil } }
        guard let api, let observation = try? InputGammaFileObservation.read(url) else { return nil }
        let key = Key(url: url.standardizedFileURL, observation: observation)
        let scale = scaleFactor ?? 1
        let started = DispatchTime.now().uptimeNanoseconds
        // 원본 크기 요청(scale 1)은 마스터가 줄이지 않은 원본일 때만 여기서 나간다.
        func cached() -> ImageLoader.DecodedImage? {
            guard let master = cachedPreview(for: key),
                  let image = previewImage(derivedFrom: master, scale: scale) else { return nil }
            trace(url, "scale \(scale) master hit \(milliseconds(since: started)) ms")
            return decoded(image, matrix: master.matrix,
                           version: master.libRawVersion, scale: scale)
        }
        if let hit = cached() { return hit }
        let gate = decodeGates[Int(UInt(bitPattern: key.hashValue) % UInt(decodeGates.count))]
        gate.lock()
        defer { gate.unlock() }
        guard !Task.isCancelled else { return nil }
        let generation = cache.lock.withLock { cache.generation }
        // 기다리는 동안 같은 파일의 디코드가 끝났으면 그 마스터를 쓴다.
        if let hit = cached() { return hit }
        guard let handle = api.initialize(0) else { return nil }
        control?.attach(handle)
        defer { control?.detach(); api.close(handle) }
        guard url.path.withCString({ api.open(handle, $0) }) == 0 else { return nil }
        configure(api, handle)
        guard api.unpack(handle) == 0, !Task.isCancelled else { return nil }
        let unpacked = DispatchTime.now().uptimeNanoseconds
        guard api.process(handle) == 0, !Task.isCancelled else { return nil }
        trace(url, "unpack \(milliseconds(unpacked - started)) process \(milliseconds(since: unpacked)) ms")
        return captureOutput(api, handle, key: key, request: .image(scale), generation: generation)
    }

    private static func configure(_ api: API, _ handle: OpaquePointer) {
        api.outputBits(handle, 16)
        api.outputColor(handle, 0) // Documented camera RGB; no camera-to-sRGB matrix.
        api.gamma(handle, 0, 1); api.gamma(handle, 1, 1)
        api.autoBright(handle, 1); api.maximumThreshold(handle, 0)
        api.highlight(handle, 1)
        for channel in 0..<4 { api.userMultiplier(handle, Int32(channel), 1) }
    }

    private enum OutputRequest {
        case image(CGFloat)
        case first(CGFloat)
        case master
    }

    private static func captureOutput(
        _ api: API, _ handle: OpaquePointer, key: Key, request: OutputRequest, generation: UInt64? = nil
    ) -> ImageLoader.DecodedImage? {
        if let direct = captureDirectPreview(api, handle, key: key, request: request, generation: generation) {
            return direct
        }
        let url = key.url
        let started = DispatchTime.now().uptimeNanoseconds
        guard let matrix = rgbCam(api, handle) else { return nil }
        var error: Int32 = 0
        guard let bitmap = api.make(handle, &error) else { return nil }
        defer { api.clear(bitmap) }
        guard error == 0 else { return nil }
        // Public libraw_processed_image_t ABI. No libraw_data_t layout is copied.
        let type = bitmap.load(as: Int32.self)
        let height = Int(bitmap.load(fromByteOffset: 4, as: UInt16.self))
        let width = Int(bitmap.load(fromByteOffset: 6, as: UInt16.self))
        let colors = bitmap.load(fromByteOffset: 8, as: UInt16.self)
        let bits = bitmap.load(fromByteOffset: 10, as: UInt16.self)
        let byteCount = Int(bitmap.load(fromByteOffset: 12, as: UInt32.self))
        guard type == 2, width > 0, height > 0, colors == 3, bits == 16,
              byteCount == width * height * 6 else { return nil }
        let source = UnsafePointer(bitmap.advanced(by: 16).assumingMemoryBound(to: UInt16.self))
        let version = api.version().map(String.init(cString:))
        let made = DispatchTime.now().uptimeNanoseconds
        let maximumMasterScale = min(1,
            previewMasterLongSide * previewMasterHeadroom / CGFloat(max(width, height)))
        // 앱의 정착 요청과 같은 배율로 한 번만 줄인다. 여유 크기로 만든 뒤 다시 줄이지 않는다.
        let referenceSize = ImageLoader.imageSource(url).flatMap(ImageLoader.sourcePixelSize)
        let settledScale = referenceSize.map { previewMasterLongSide / max($0.width, $0.height) }
            ?? previewMasterLongSide / CGFloat(max(width, height))
        let masterScale = min(maximumMasterScale, settledScale)
        let masterSize = reducedSize(width: width, height: height, scale: masterScale)
        let scale: CGFloat
        switch request {
        case .image(let value): scale = value
        case .first(let dimension): scale = min(1, dimension / CGFloat(max(width, height)))
        case .master: scale = masterScale
        }
        let image: CGImage
        if case .first = request {
            let size = reducedSize(width: width, height: height, scale: scale)
            guard let pixels = RGB16AreaReduce.reduceToData(source, width: width, height: height, channels: 3,
                targetWidth: size.width, targetHeight: size.height),
                  let first = previewImage(pixels, width: size.width, height: size.height) else { return nil }
            image = first
        } else if scale < 1 || masterScale >= 1 {
            // 프리뷰 요청과, 마스터 크기 안에 드는 작은 원본은 마스터를 거쳐 캐시한다.
            guard let reduced = reducedPreview(
                source, width: width, height: height, scale: scale, masterSize: masterSize,
                matrix: matrix, version: version, key: key, generation: generation
            ) else { return nil }
            image = reduced
        } else {
            guard UInt64(width * height) * 8 <= ProcessInfo.processInfo.physicalMemory / 2,
                  let pixels = RGB16AreaReduce.reduceToData(source, width: width, height: height, channels: 3,
                      targetWidth: width, targetHeight: height),
                  let full = previewImage(pixels, width: width, height: height) else { return nil }
            image = full
        }
        guard (try? InputGammaFileObservation.read(url)) == key.observation, !Task.isCancelled else { return nil }
        trace(url, "scale \(scale) pack \(milliseconds(made - started)) "
            + "reduce \(milliseconds(since: made)) ms")
        cache.lock.withLock {
            if cache.matrices.count >= 64 { cache.matrices.removeAll(keepingCapacity: true) }
            cache.matrices[key] = matrix
        }
        return decoded(image, matrix: matrix, version: version, scale: scale)
    }

    /// 출력 버퍼 소유권만 공유한다. LibRaw 핸들과 센서 원본은 보유하지 않는다.
    private final class PreviewBitmapOwner: @unchecked Sendable {
        let pointer: UnsafeMutableRawPointer
        let api: API
        init(_ pointer: UnsafeMutableRawPointer, api: API) { self.pointer = pointer; self.api = api }
        deinit { api.clear(pointer) }
    }

    /// 전체 크기 RGB 복사 없이 처리된 센서 버퍼에서 같은 면적 평균을 직접 만든다.
    private static func captureDirectPreview(
        _ api: API, _ handle: OpaquePointer, key: Key, request: OutputRequest, generation: UInt64?
    ) -> ImageLoader.DecodedImage? {
        if case .image(let scale) = request, scale >= 1 { return nil }
        var w: Int32 = 0, h: Int32 = 0
        guard api.previewSize?(handle, &w, &h) == 1, let make = api.makePreview,
              let matrix = rgbCam(api, handle) else { return nil }
        let width = Int(w), height = Int(h)
        let referenceSize = ImageLoader.imageSource(key.url).flatMap(ImageLoader.sourcePixelSize)
        let masterScale = min(1, previewMasterLongSide * previewMasterHeadroom / CGFloat(max(width, height)),
            referenceSize.map { previewMasterLongSide / max($0.width, $0.height) }
                ?? previewMasterLongSide / CGFloat(max(width, height)))
        let masterSize = reducedSize(width: width, height: height, scale: masterScale)
        let scale: CGFloat
        let size: (width: Int, height: Int)
        let keepsMaster: Bool
        switch request {
        case .first(let dimension):
            scale = min(1, dimension / CGFloat(max(width, height)))
            size = reducedSize(width: width, height: height, scale: scale)
            keepsMaster = false
        case .master:
            scale = masterScale; size = masterSize; keepsMaster = true
        case .image(let value):
            scale = value
            let target = reducedSize(width: width, height: height, scale: scale)
            keepsMaster = target.width <= masterSize.width && target.height <= masterSize.height
            size = keepsMaster ? masterSize : target
        }
        let started = DispatchTime.now().uptimeNanoseconds
        guard let bitmap = make(handle, Int32(size.width), Int32(size.height)) else { return nil }
        let owner = PreviewBitmapOwner(bitmap, api: api)
        guard bitmap.load(as: Int32.self) == 2,
              Int(bitmap.load(fromByteOffset: 4, as: UInt16.self)) == size.height,
              Int(bitmap.load(fromByteOffset: 6, as: UInt16.self)) == size.width,
              bitmap.load(fromByteOffset: 8, as: UInt16.self) == 4,
              bitmap.load(fromByteOffset: 10, as: UInt16.self) == 16,
              Int(bitmap.load(fromByteOffset: 12, as: UInt32.self)) == size.width * size.height * 8 else { return nil }
        let pixels = Data(bytesNoCopy: bitmap.advanced(by: 16), count: size.width * size.height * 8,
            deallocator: .custom { [owner] _, _ in withExtendedLifetime(owner) {} })
        guard (try? InputGammaFileObservation.read(key.url)) == key.observation, !Task.isCancelled else { return nil }
        let version = api.version().map(String.init(cString:))
        let image: CGImage?
        if keepsMaster {
            let master = PreviewMaster(data: pixels, width: size.width, height: size.height,
                sourceWidth: width, sourceHeight: height, matrix: matrix, libRawVersion: version)
            if let generation { storePreview(master, for: key, generation: generation) }
            image = previewImage(derivedFrom: master, scale: scale)
        } else {
            image = previewImage(pixels, width: size.width, height: size.height)
        }
        guard let image else { return nil }
        cache.lock.withLock {
            if cache.matrices.count >= 64 { cache.matrices.removeAll(keepingCapacity: true) }
            cache.matrices[key] = matrix
        }
        trace(key.url, "direct preview \(size.width)x\(size.height) \(milliseconds(since: started)) ms")
        return decoded(image, matrix: matrix, version: version, scale: scale)
    }

    private static func rgbCam(_ api: API, _ handle: OpaquePointer) -> CameraToWorkingMatrix? {
        CameraToWorkingMatrix((0..<9).map { Double(api.matrix(handle, Int32($0 / 3), Int32($0 % 3))) })
    }

    /// 행렬만 필요할 때. LibRaw 는 파일을 여는 단계에서 이미 rgb_cam 을 정한다(24장 실측: 처리 뒤 값과
    /// 같다). 예외는 Canon PowerShot 600 으로, 처리 중 raw2image 가 행렬을 다시 고른다.
    private static func openedMatrix(_ url: URL) -> CameraToWorkingMatrix? {
        guard let api, let handle = api.initialize(0) else { return nil }
        defer { api.close(handle) }
        guard url.path.withCString({ api.open(handle, $0) }) == 0,
              let name = api.unpackFunctionName?(handle).map(String.init(cString:)),
              !name.contains("canon_600") else { return nil }
        return rgbCam(api, handle)
    }

    private static func decoded(
        _ image: CGImage, matrix: CameraToWorkingMatrix, version: String?, scale: CGFloat
    ) -> ImageLoader.DecodedImage {
        let ci = CIImage(cgImage: image, options: [.colorSpace: image.colorSpace as Any])
        return ImageLoader.DecodedImage(image: tagged(ci, matrix: matrix), provenance: .init(decoder: .libRaw,
            rawDecoderVersion: version, rawScaleFactor: Double(scale), cameraToWorking: matrix), rasterImage: image)
    }

    /// LibRaw 결과를 `scale` 크기로 줄인다. 정착 크기 이하 요청은 정착 크기 마스터를 거쳐 캐시한다.
    private static func reducedPreview(
        _ source: UnsafePointer<UInt16>, width: Int, height: Int, scale: CGFloat,
        masterSize: (width: Int, height: Int),
        matrix: CameraToWorkingMatrix, version: String?, key: Key, generation: UInt64?
    ) -> CGImage? {
        let target = reducedSize(width: width, height: height, scale: scale)
        guard target.width <= masterSize.width, target.height <= masterSize.height else {
            guard let pixels = RGB16AreaReduce.reduceToData(source, width: width, height: height, channels: 3,
                targetWidth: target.width, targetHeight: target.height) else { return nil }
            return previewImage(pixels, width: target.width, height: target.height)
        }
        guard let masterPixels = RGB16AreaReduce.reduceToData(source, width: width, height: height, channels: 3,
            targetWidth: masterSize.width, targetHeight: masterSize.height) else { return nil }
        let master = PreviewMaster(
            data: masterPixels,
            width: masterSize.width, height: masterSize.height, sourceWidth: width, sourceHeight: height,
            matrix: matrix, libRawVersion: version)
        guard !Task.isCancelled else { return nil }
        if let generation { storePreview(master, for: key, generation: generation) }
        return previewImage(derivedFrom: master, scale: scale)
    }

    /// 마스터에서 `scale` 크기를 만든다. 마스터보다 큰 요청이면 nil.
    private static func previewImage(derivedFrom master: PreviewMaster, scale: CGFloat) -> CGImage? {
        let target = reducedSize(width: master.sourceWidth, height: master.sourceHeight, scale: scale)
        guard target.width <= master.width, target.height <= master.height else { return nil }
        if target.width == master.width, target.height == master.height {
            return previewImage(master.data, width: master.width, height: master.height)
        }
        let reduced: Data? = master.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt16.self) else { return nil }
            return RGB16AreaReduce.reduceToData(base, width: master.width, height: master.height, channels: 4,
                targetWidth: target.width, targetHeight: target.height)
        }
        guard let reduced else { return nil }
        return previewImage(reduced, width: target.width, height: target.height)
    }

    private static func previewImage(_ data: Data, width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 8, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder16Little),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
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
        } else if let matrix = openedMatrix(source) {
            cache.lock.withLock {
                if cache.matrices.count >= 64 { cache.matrices.removeAll(keepingCapacity: true) }
                cache.matrices[key] = matrix
            }
            measurements.cameraToWorking = matrix
        } else {
            guard let decoded = decode(source, scaleFactor: nil), let matrix = decoded.provenance.cameraToWorking else {
                throw ChromabaseError.loadFailed("camera-native RAW decoder unavailable or unsupported output")
            }
            measurements.cameraToWorking = matrix
        }
    }
}
