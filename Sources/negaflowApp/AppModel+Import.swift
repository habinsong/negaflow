import SwiftUI
import AppKit
import Chromabase
import ImageIO
import UniformTypeIdentifiers

extension AppModel {
    // MARK: - 이미지 가져오기 (파일 선택 · 드래그앤드롭)
    //
    // 스캐너 없이 RAW/DNG/TIFF/PNG/JPG/JPEG 등 원본 이미지를 가져와 현상한다. 가져온 파일은
    // in-place 참조(Lightroom식) — 대용량 RAW를 복제하지 않는다. 현상/익스포트는 프레임의
    // sourceKind(.importedFile)를 보고 올바른 로더로 파일을 읽는다.

    /// 가져오기 지원 확장자(소문자). 카메라 RAW 전 제조사 + 표준 이미지. 단일 출처 = Chromabase.ImageLoader.
    static var supportedImportExtensions: Set<String> { ImageLoader.importExtensions }

    /// 가져오기 가능한 파일인가. 명시 확장자 목록 + 시스템이 이미지/카메라 RAW로 인식하는 타입을 허용한다
    /// (목록에 없는 신형 RAW라도 macOS가 인식하면 받는다).
    static func isSupportedImport(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedImportExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        if type.conforms(to: .image) { return true }
        if let raw = UTType("public.camera-raw-image"), type.conforms(to: raw) { return true }
        return false
    }

    /// 파일 선택 패널(다중 선택). 선택한 이미지를 프레임으로 가져온다.
    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.prompt = "가져오기"
        panel.message = "현상할 이미지를 선택하세요 (RAW/DNG/TIFF/PNG/JPG)"
        panel.allowedContentTypes = Self.importContentTypes
        guard panel.runModal() == .OK else { return }
        importImages(urls: panel.urls)
    }

    /// 파일 선택 패널 허용 UTType. 지원 확장자에서 파생 + 이미지/카메라 RAW 상위 타입.
    static var importContentTypes: [UTType] {
        var types: [UTType] = [.image]
        if let raw = UTType("public.camera-raw-image") { types.append(raw) }
        for ext in supportedImportExtensions {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    /// URL 목록을 프레임으로 가져온다(다중·연속 지원). 각 프레임은 백그라운드로 현상한다.
    func importImages(urls: [URL]) {
        let supported = urls.filter { Self.isSupportedImport($0) }
        guard !supported.isEmpty else {
            statusMessage = "가져올 수 있는 이미지가 없습니다 (지원: RAW/DNG/TIFF/PNG/JPG)"
            return
        }
        var lastID: UUID?
        for url in supported {
            let metadata = Self.importedImageMetadata(for: url)
            let frame = ScanFrame(
                scanIndex: frames.count + 1,
                rawScanURL: url,
                filmType: filmType,
                sourceKind: .importedFile,
                sourcePixelWidth: metadata.width,
                sourcePixelHeight: metadata.height,
                sourceResolutionDPI: metadata.dpi,
                sourceBitDepth: metadata.bitDepth,
                initialTransform: nextScanOrientation
            )
            frame.preset = presets.first(where: { $0.id == "neutral" })
            frame.updateParams {
                $0.filmType = filmType
                $0.developTarget = developTarget
                $0.scannerProfileID = scannerProfileID
            }
            frames.append(frame)
            lastID = frame.id
            // 스캔 배치와 동일하게 현상을 await하지 않고 백그라운드로 띄운다(연속 가져오기 처리량↑).
            Task { await developFrame(frame) }
        }
        if let lastID { selectedFrameID = lastID }
        scanPhase = .complete
        statusMessage = supported.count == urls.count
            ? "\(supported.count)장 가져오기 완료"
            : "\(supported.count)장 가져오기 완료 (\(urls.count - supported.count)장 미지원 형식 제외)"
    }

    /// SwiftUI onDrop 진입점. 드롭된 파일 URL(다중)을 모아 가져온다.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileType = UTType.fileURL.identifier
        let relevant = providers.filter { $0.hasItemConformingToTypeIdentifier(fileType) }
        guard !relevant.isEmpty else { return false }

        let collector = DropURLCollector(expected: relevant.count) { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            self.importImages(urls: urls)
        }
        for provider in relevant {
            provider.loadItem(forTypeIdentifier: fileType, options: nil) { item, _ in
                let url: URL?
                switch item {
                case let data as Data:
                    url = URL(dataRepresentation: data, relativeTo: nil)
                case let u as URL:
                    url = u
                default:
                    url = nil
                }
                collector.add(url)
            }
        }
        return true
    }

    private static func importedImageMetadata(for url: URL) -> (width: Int?, height: Int?, dpi: Int?, bitDepth: Int?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (nil, nil, nil, nil)
        }
        let width = positiveRoundedInt(props[kCGImagePropertyPixelWidth])
        let height = positiveRoundedInt(props[kCGImagePropertyPixelHeight])
        let bitDepth = positiveRoundedInt(props[kCGImagePropertyDepth])
        let dpiX = positiveRoundedInt(props[kCGImagePropertyDPIWidth])
            ?? nestedPositiveInt(props, dictionary: kCGImagePropertyTIFFDictionary, key: "XResolution")
            ?? nestedPositiveInt(props, dictionary: kCGImagePropertyExifDictionary, key: "XResolution")
        let dpiY = positiveRoundedInt(props[kCGImagePropertyDPIHeight])
            ?? nestedPositiveInt(props, dictionary: kCGImagePropertyTIFFDictionary, key: "YResolution")
            ?? nestedPositiveInt(props, dictionary: kCGImagePropertyExifDictionary, key: "YResolution")
        let dpi = normalizedDPI(x: dpiX, y: dpiY)
        return (width, height, dpi, bitDepth)
    }

    private static func nestedPositiveInt(_ props: [CFString: Any], dictionary: CFString, key: String) -> Int? {
        if let nested = props[dictionary] as? [String: Any] {
            return positiveRoundedInt(nested[key])
        }
        if let nested = props[dictionary] as? [CFString: Any] {
            return positiveRoundedInt(nested[key as CFString])
        }
        return nil
    }

    private static func normalizedDPI(x: Int?, y: Int?) -> Int? {
        switch (x, y) {
        case let (.some(x), .some(y)):
            return max(1, Int((Double(x + y) / 2.0).rounded()))
        case let (.some(x), nil):
            return x
        case let (nil, .some(y)):
            return y
        case (nil, nil):
            return nil
        }
    }

    private static func positiveRoundedInt(_ value: Any?) -> Int? {
        let doubleValue: Double?
        switch value {
        case let number as NSNumber:
            doubleValue = number.doubleValue
        case let string as String:
            doubleValue = Double(string)
        default:
            doubleValue = nil
        }
        guard let doubleValue, doubleValue.isFinite, doubleValue > 0 else { return nil }
        return Int(doubleValue.rounded())
    }
}

/// 여러 NSItemProvider의 비동기 로드를 모아 메인 액터에서 한 번에 가져오기로 넘긴다.
private final class DropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var remaining: Int
    private let completion: ([URL]) -> Void

    init(expected: Int, completion: @escaping ([URL]) -> Void) {
        self.remaining = expected
        self.completion = completion
    }

    func add(_ url: URL?) {
        lock.lock()
        if let url { urls.append(url) }
        remaining -= 1
        let done = remaining <= 0
        let snapshot = urls
        lock.unlock()
        if done {
            DispatchQueue.main.async { [completion] in completion(snapshot) }
        }
    }
}
