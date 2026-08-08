import SwiftUI
import AppKit
import Chromabase
import ImageIO
import UniformTypeIdentifiers

extension AppModel {
    // MARK: - 이미지 가져오기 (파일 선택 · 드래그앤드롭)
    //
    // 스캐너 없이 RAW/DNG/TIFF/PNG/JPG/JPEG 등 원본 이미지를 가져와 현상한다. 가져온 파일은
    // in-place 참조(비파괴) — 대용량 RAW를 복제하지 않는다. 현상/익스포트는 프레임의
    // sourceKind(.importedFile)를 보고 올바른 로더로 파일을 읽는다.

    /// 가져오기 지원 확장자(소문자). 카메라 RAW 전 제조사 + 표준 이미지. 단일 출처 = Chromabase.ImageLoader.
    nonisolated static var supportedImportExtensions: Set<String> { ImageLoader.importExtensions }

    /// 가져오기 가능한 파일인가. 명시 확장자 목록 + 시스템이 이미지/카메라 RAW로 인식하는 타입을 허용한다
    /// (목록에 없는 신형 RAW라도 macOS가 인식하면 받는다).
    nonisolated static func isSupportedImport(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedImportExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        if type.conforms(to: .image) { return true }
        if let raw = UTType("public.camera-raw-image"), type.conforms(to: raw) { return true }
        return false
    }

    /// 파일 선택 패널(다중 선택). 선택한 이미지를 프레임으로 가져온다.
    func presentImportPanel() {
        guard allowsLibraryMutation else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.prompt = text(AppLocalizedPhrase.importPanelPrompt)
        panel.message = text(AppLocalizedPhrase.importPanelMessage)
        panel.allowedContentTypes = Self.importContentTypes
        guard panel.runModal() == .OK else { return }
        Task { [weak self] in
            await self?.importImagesWithProgress(urls: panel.urls)
        }
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

    /// URL 목록을 프레임으로 가져온다(다중·연속 지원). 현상은 사용자 기본값이 켜져 있을 때만
    /// 백그라운드로 시작하며, 기본값은 원본 썸네일만 만드는 OFF다.
    /// groupName = 디스크 저장 폴더 규칙의 출처 폴더명(개별 파일 가져오기는 default,
    /// 폴더 가져오기는 폴더명).
    func importImages(
        urls: [URL],
        groupName: String = FrameStorageNaming.defaultImportGroup,
        preloadedImports: [String: PreloadedImageImport] = [:]
    ) {
        guard allowsLibraryMutation else { return }
        let trace = AppDiagnostics.start(.importFiles, category: .import)
        defer { trace.finish() }
        let supported = urls.filter { Self.isSupportedImport($0) }
        guard !supported.isEmpty else {
            statusMessage = text(AppLocalizedPhrase.noImportableImages)
            return
        }
        let filtered = Self.filterDuplicateImports(
            supported,
            existingSourceURLs: frames.map(\.rawScanURL)
        )
        let importURLs = filtered.urls
        let unsupportedCount = urls.count - supported.count
        guard !importURLs.isEmpty else {
            scanPhase = .complete
            updateImportCompletionStatus(
                importedCount: 0,
                unsupportedCount: unsupportedCount,
                duplicateCount: filtered.duplicateCount
            )
            return
        }
        // 파일 단위 가져오기는 원본 폴더를 등록 폴더로 만들지 않는다. 등록 폴더는 새로고침
        // 대상이라, 한 장만 가져와도 그 폴더의 나머지 사진이 전부 딸려 오게 된다.
        // 폴더 트리에는 원본 경로에서 파생된 행으로 그대로 보인다.
        let firstScanIndex = nextScanIndex
        // 메타데이터(헤더/XMP/사이드카) 읽기는 파일별 독립이라 병렬로 미리 읽는다 — 큰 폴더
        // 가져오기에서 파일 수 × 수 ms 의 순차 파싱이 메인 스레드를 잡던 시간을 코어 수로 나눈다.
        let identities = importURLs.map(Self.importIdentity)
        let metadataByIndex: [SourceMetadataSnapshot?]
        if preloadedImports.isEmpty {
            metadataByIndex = Self.readImportMetadata(importURLs)
        } else {
            // 미리 읽어 둔 결과만 쓴다. 여기서 다시 읽으면 아직 로컬에 없는 iCloud 원본에서
            // MainActor 가 커널 대기에 걸려 앱 전체가 멈춘다. 읽기에 실패한 파일은 메타데이터
            // 없는 프레임으로 들어오고, 크기는 썸네일 시드가 채운다.
            metadataByIndex = identities.map { preloadedImports[$0]?.metadata }
        }
        let importedFrames = importURLs.enumerated().map { offset, url in
            let metadata = metadataByIndex[offset]
            let storageGroupName = preloadedImports[identities[offset]]?.groupName
                ?? groupName
            let frame = ScanFrame(
                scanIndex: firstScanIndex + offset,
                rawScanURL: url,
                filmType: filmType,
                sourceKind: .importedFile,
                sourcePixelWidth: metadata?.pixelWidth,
                sourcePixelHeight: metadata?.pixelHeight,
                sourceResolutionDPI: metadata?.resolutionDPI,
                sourceBitDepth: metadata?.bitsPerColorSample,
                sourceMetadata: metadata,
                // ImageLoader가 EXIF orientation을 픽셀에 이미 적용한다. 스캐너 홀더 방향
                // 템플릿은 스캔 경로 전용이며 가져온 파일에 다시 적용하지 않는다.
                initialTransform: .identity,
                storageGroupName: storageGroupName
            )
            seedInitialThumbnail(for: frame, from: url)
            frame.preset = presets.first(where: { $0.id == "neutral" })
            frame.updateParams {
                $0.filmType = filmType
                $0.developTarget = developTarget
                $0.scannerProfileID = scannerProfileID
            }
            frame.establishLibraryWorkflowBaselineIfNeeded()
            return frame
        }
        frames.append(contentsOf: importedFrames)
        guard assignNewPersistentFrames(importedFrames) else {
            let failedIDs = Set(importedFrames.map(\.id))
            frames.removeAll { failedIDs.contains($0.id) }
            for frame in importedFrames {
                removeThumbnailFile(for: frame)
                frameCacheManager.removeDevelopedResident(frame)
            }
            statusMessage = text(AppLocalizedPhrase.importLibraryRegistrationFailedStatus)
            trace.fail(code: "catalog_registration_failed")
            return
        }
        if developsImportsAutomatically {
            developImportedFramesSequentially(importedFrames)
        }
        selectedFrameID = importedFrames.last?.id
        scanPhase = .complete
        updateImportCompletionStatus(
            importedCount: importURLs.count,
            unsupportedCount: unsupportedCount,
            duplicateCount: filtered.duplicateCount
        )
    }

    /// 사용자 진입점에서 메타데이터 준비를 백그라운드로 옮기고 파일 단위 진행률을 발행한다.
    /// 실제 프레임 등록은 기존 `importImages` 한 번으로 묶어 대형 카탈로그의 재색인 비용을
    /// 늘리지 않는다.
    func importImagesWithProgress(
        urls: [URL],
        groupName: String = FrameStorageNaming.defaultImportGroup,
        groupNamesByIdentity: [String: String] = [:]
    ) async {
        guard allowsLibraryMutation else { return }
        // 중복 판정은 URL 마다 심볼릭 링크를 푸는(파일 시스템을 만지는) 일이라 라이브러리가
        // 커질수록 무겁다. MainActor 에서 돌리지 않는다.
        let existingSourceURLs = frames.map(\.rawScanURL)
        let importURLs = await Task.detached(priority: .userInitiated) {
            Self.filterDuplicateImports(
                urls.filter { Self.isSupportedImport($0) },
                existingSourceURLs: existingSourceURLs
            ).urls
        }.value
        guard allowsLibraryMutation, !importURLs.isEmpty else {
            importImages(urls: urls, groupName: groupName)
            return
        }

        let progressID = libraryImportProgressStore.begin(totalCount: importURLs.count)
        let progressStore = libraryImportProgressStore
        await materializeEvictedImportSources(importURLs, progressID: progressID)
        guard allowsLibraryMutation, !Task.isCancelled else {
            libraryImportProgressStore.finish(id: progressID)
            return
        }
        libraryImportProgressStore.update(
            id: progressID,
            completedCount: 0,
            totalCount: importURLs.count,
            phase: .reading
        )
        let metadata = await Task.detached(priority: .userInitiated) {
            Self.readImportMetadata(importURLs) { completedCount in
                Task { @MainActor [weak progressStore] in
                    progressStore?.update(
                        id: progressID,
                        completedCount: completedCount,
                        phase: .reading
                    )
                }
            }
        }.value
        guard allowsLibraryMutation, !Task.isCancelled else {
            libraryImportProgressStore.finish(id: progressID)
            return
        }

        var preloadedImports: [String: PreloadedImageImport] = [:]
        preloadedImports.reserveCapacity(importURLs.count)
        for (url, snapshot) in zip(importURLs, metadata) {
            let identity = Self.importIdentity(url)
            preloadedImports[identity] = PreloadedImageImport(
                metadata: snapshot,
                groupName: groupNamesByIdentity[identity] ?? groupName
            )
        }
        importImages(
            urls: urls,
            groupName: groupName,
            preloadedImports: preloadedImports
        )
        libraryImportProgressStore.finish(id: progressID)
    }

    /// iCloud(데스크탑·사진 등 동기화 폴더)가 로컬 사본을 내린 원본을 **읽기 전에** 한 번에
    /// 받아둔다. 이런 파일은 여는 순간 커널이 다운로드가 끝날 때까지 그 스레드를 막는데,
    /// 메타데이터 읽기는 파일 수만큼 병렬로 도는 탓에 여러 장을 가져오면 워커 스레드가 전부
    /// 잠겨 앱이 멈춘 것처럼 보였다. 여기서 기다림을 한 구간으로 모으고 진행률로 보여준다.
    ///
    /// 축출 판정·다운로드 요청은 전부 materialize 안에서 백그라운드로 돈다. 여기서 미리
    /// 확인하면 그 파일 시스템 왕복이 MainActor 에서 일어나 UI 가 그대로 멈춘다.
    private func materializeEvictedImportSources(
        _ urls: [URL],
        progressID: UUID
    ) async {
        let progressStore = libraryImportProgressStore
        _ = await ExportSourceMaterialization.materialize(urls) { progress in
            Task { @MainActor [weak progressStore] in
                progressStore?.update(
                    id: progressID,
                    completedCount: progress.ready,
                    totalCount: progress.total,
                    phase: .downloading
                )
            }
        }
    }

    private func updateImportCompletionStatus(
        importedCount: Int,
        unsupportedCount: Int,
        duplicateCount: Int
    ) {
        switch (unsupportedCount, duplicateCount) {
        case (0, 0):
            statusMessage = text(AppLocalizedPhrase.importCompleteFormat, importedCount)
        case (let unsupported, 0):
            statusMessage = text(AppLocalizedPhrase.importCompleteUnsupportedFormat, importedCount, unsupported)
        case (0, let duplicates):
            statusMessage = text(AppLocalizedPhrase.importCompleteDuplicatesFormat, importedCount, duplicates)
        case (let unsupported, let duplicates):
            statusMessage = text(
                AppLocalizedPhrase.importCompleteUnsupportedDuplicatesFormat,
                importedCount,
                unsupported,
                duplicates
            )
        }
    }

    /// 가져오기 대상 파일들의 메타데이터를 병렬로 읽는다(파일별 독립 — ImageIO/정규식 모두
    /// 스레드 안전). 결과 순서는 입력 순서와 같다.
    nonisolated static func readImportMetadata(
        _ urls: [URL],
        progress: (@Sendable (Int) -> Void)? = nil
    ) -> [SourceMetadataSnapshot?] {
        guard urls.count > 1 else {
            let results = urls.map { SourceMetadataReader.read(from: $0) }
            if !urls.isEmpty { progress?(urls.count) }
            return results
        }
        final class Store: @unchecked Sendable {
            let lock = NSLock()
            var results: [SourceMetadataSnapshot?]
            var completedCount = 0
            init(count: Int) {
                results = [SourceMetadataSnapshot?](repeating: nil, count: count)
            }
        }
        let store = Store(count: urls.count)
        let progressStep = max(1, urls.count / 200)
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            let snapshot = SourceMetadataReader.read(from: urls[index])
            store.lock.lock()
            store.results[index] = snapshot
            store.completedCount += 1
            let completedCount = store.completedCount
            if completedCount == urls.count || completedCount.isMultiple(of: progressStep) {
                progress?(completedCount)
            }
            store.lock.unlock()
        }
        return store.results
    }

    /// 카탈로그에 이미 있는 동일 원본과 한 가져오기 요청 안의 정확한 경로 중복만 제외한다.
    /// 파일명/촬영일 추정은 서로 다른 원본을 오탐할 수 있으므로 사용하지 않는다.
    nonisolated static func filterDuplicateImports(
        _ urls: [URL],
        existingSourceURLs: [URL]
    ) -> (urls: [URL], duplicateCount: Int) {
        var seen = Set(existingSourceURLs.map(importIdentity))
        var accepted: [URL] = []
        accepted.reserveCapacity(urls.count)
        var duplicateCount = 0
        for url in urls {
            if seen.insert(importIdentity(url)).inserted {
                accepted.append(url)
            } else {
                duplicateCount += 1
            }
        }
        return (accepted, duplicateCount)
    }

    nonisolated static func importIdentity(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// 원본 파일에서 경량 썸네일 CGImage 를 만든다. 임베디드 프리뷰 우선(Photo Mechanic/
    /// 임베디드 프리뷰 임포트 전략) — 카메라 RAW/JPEG 의 내장 프리뷰는 풀 디코드 없이
    /// 추출된다. 내장 프리뷰가 요청 크기보다 작아 화질이 떨어질 때만 기존 풀 디코드로 폴백해
    /// 화질은 이전과 동일하게 유지한다(스캐너 TIFF 는 내장이 없어 기존 경로 그대로).
    nonisolated static func rawThumbnailCGImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let target = max(1, maxPixelSize)
        let embeddedOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, embeddedOptions as CFDictionary) {
            let longSide = max(thumb.width, thumb.height)
            if longSide > target {
                // 일부 포맷은 내장 프리뷰를 원본 크기 그대로 돌려준다 — 요청 크기로 축소해 메모리 캡.
                return downscaledThumbnail(thumb, maxPixelSize: target) ?? thumb
            }
            if longSide >= target || longSide >= sourceLongSide(source) { return thumb }
        }
        let fullOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, fullOptions as CFDictionary)
    }

    /// 원본 픽셀 긴 변(헤더만 읽음). 알 수 없으면 .max — 호출측이 보수적으로 풀 디코드 폴백.
    nonisolated private static func sourceLongSide(_ source: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .max
        }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let longSide = max(width, height)
        return longSide > 0 ? longSide : .max
    }

    nonisolated private static func downscaledThumbnail(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        let longSide = max(image.width, image.height)
        guard longSide > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(longSide)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let space: CGColorSpace = {
            if let embedded = image.colorSpace, embedded.model == .rgb { return embedded }
            return CGColorSpace(name: CGColorSpace.sRGB)!
        }()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// SwiftUI onDrop 진입점. 드롭된 파일 URL(다중)을 모아 가져온다.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard allowsLibraryMutation else { return false }
        let fileType = UTType.fileURL.identifier
        let relevant = providers.filter { $0.hasItemConformingToTypeIdentifier(fileType) }
        guard !relevant.isEmpty else { return false }

        let collector = DropURLCollector(expected: relevant.count) { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            self.importURLs(urls)
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

}

struct PreloadedImageImport: Sendable {
    let metadata: SourceMetadataSnapshot?
    let groupName: String
}

struct LibraryTaskProgress: Equatable, Sendable {
    let completedCount: Int
    let totalCount: Int

    init(completedCount: Int, totalCount: Int) {
        self.totalCount = max(0, totalCount)
        self.completedCount = min(max(0, completedCount), self.totalCount)
    }

    var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var percent: Int {
        Int((fraction * 100).rounded())
    }
}

/// 가져오기 진행 단계. iCloud 원본은 읽기 전에 내려받아야 하므로 두 구간을 구분해 보여준다.
enum LibraryImportPhase: Sendable {
    case downloading
    case reading
}

@MainActor
final class LibraryImportProgressStore: ObservableObject {
    @Published private(set) var progress: LibraryTaskProgress?
    @Published private(set) var phase = LibraryImportPhase.reading

    private var activeID: UUID?
    private var clearTask: Task<Void, Never>?

    @discardableResult
    func begin(totalCount: Int) -> UUID {
        clearTask?.cancel()
        let id = UUID()
        activeID = id
        phase = .reading
        progress = LibraryTaskProgress(completedCount: 0, totalCount: totalCount)
        return id
    }

    func update(
        id: UUID,
        completedCount: Int,
        totalCount: Int? = nil,
        phase: LibraryImportPhase = .reading
    ) {
        guard id == activeID, let progress else { return }
        let total = totalCount ?? progress.totalCount
        // 단계가 바뀌거나 모수가 달라지면 카운트를 새로 센다. 같은 단계 안에서는 되돌아가지 않는다.
        let startsNewSegment = phase != self.phase || total != progress.totalCount
        self.phase = phase
        self.progress = LibraryTaskProgress(
            completedCount: startsNewSegment
                ? completedCount
                : max(progress.completedCount, completedCount),
            totalCount: total
        )
    }

    func finish(id: UUID) {
        guard id == activeID, let progress else { return }
        phase = .reading
        self.progress = LibraryTaskProgress(
            completedCount: progress.totalCount,
            totalCount: progress.totalCount
        )
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, self?.activeID == id else { return }
            self?.activeID = nil
            self?.progress = nil
        }
    }
}

/// 여러 NSItemProvider의 비동기 로드를 모아 메인 액터에서 한 번에 가져오기로 넘긴다.
private final class DropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var remaining: Int
    private let completion: @MainActor @Sendable ([URL]) -> Void

    init(
        expected: Int,
        completion: @escaping @MainActor @Sendable ([URL]) -> Void
    ) {
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
            Task { @MainActor [completion] in completion(snapshot) }
        }
    }
}
