import Foundation
import AppKit
import Chromabase
import ScannerKit

struct FilmBaseCacheKey: Equatable, Sendable {
    let filmType: FilmType
    let mode: DevelopParameters.BaseMode
    let manualBaseRGB: SIMD3<Double>?
}

// MARK: - ScanFrame (배치/세션 스캔의 단위)
//
// 한 프레임 = 하나의 raw 스캔 + 그 프레임만의 현상 파라미터/transform/결과.
// AppModel.frames: [ScanFrame] 이 롤을 구성하고, selectedFrameID 가 현재 보는 프레임.
// 색감 엔진은 건드리지 않는다 — 프레임은 데이터 보관만 한다.
@MainActor
final class ScanFrame: ObservableObject, Identifiable {
    let id: UUID = UUID()
    let scanIndex: Int                    // 롤 내 순서 (1-based 표시용)
    let rawScanURL: URL
    let scannedAt: Date

    @Published var filmType: FilmType
    @Published var preset: LookPreset?
    @Published var params: DevelopParameters
    @Published var imageTransform: ImageTransform
    @Published var baseRGB: SIMD3<Double>?

    @Published var rawPreviewImage: NSImage?
    @Published var developedImage: NSImage?
    @Published var showDeveloped: Bool = true
    @Published var isDeveloping: Bool = false

    var rawPreviewTransform: ImageTransform?
    var developRevision: Int = 0
    var cachedBaseKey: FilmBaseCacheKey?
    var cachedBase: FilmBase?

    init(
        scanIndex: Int,
        rawScanURL: URL,
        filmType: FilmType,
        initialTransform: ImageTransform = .identity
    ) {
        self.scanIndex = scanIndex
        self.rawScanURL = rawScanURL
        self.scannedAt = Date()
        self.filmType = filmType
        self.params = DevelopParameters()
        self.imageTransform = initialTransform
    }

    /// 표시용 이름.
    var displayName: String { "Frame \(scanIndex)" }

    func updateParams(_ body: (inout DevelopParameters) -> Void) {
        var next = params
        body(&next)
        params = next
    }

    func updateTransform(_ body: (inout ImageTransform) -> Void) {
        var next = imageTransform
        body(&next)
        imageTransform = next
    }
}

extension ScanFrame: Hashable {
    nonisolated static func == (lhs: ScanFrame, rhs: ScanFrame) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
