import SwiftUI
import Chromabase
import CoreImage
import AppKit

// 결함 제거(브러시 ICE + 반자동 Region ICE)를 원본 raw 스캔에 직접 적용하고, ICE된 raw(cleaned raw)를
// 현상·export 입력으로 쓴다. 그래서 Target/Profile/Film/Mode·인스펙터 전 항목을 바꿔도 결함 제거가
// 유지되고 재계산되지 않는다.
//
// 통합 편집 모델(핵심): cleaned raw = 원본 raw + frame.defectEdits 순차 적용. 브러시(스트로크 그룹)와
// 반자동(렌더된 마스크)이 같은 [DefectEdit] 리스트에 순서대로 쌓이므로, 한쪽을 rebuild(⌘Z/clear/증분
// 불가)해도 다른 쪽이 재적용돼 보존된다 — 서로 되살아나지 않는다.
//
// 캐시 정책(메모리 폭주 방지):
//  • cleanedRawImage(메모리, 16bit linear CGImage) = 활성 프레임 소수만 FIFO로 적재.
//  • 다른 프레임으로 이동하면(FIFO 초과) 메모리에서 내려놓되, cleanedRawDiskURL(LZW TIFF)에
//    백킹해 두어 재진입 시 ICE 재계산 없이 즉시 복원한다.
//  • 디스크 백킹은 앱 시작 시 청소되어 공간을 남기지 않는다(negaflowApp.init).

private let defectICEParameters = SoftwareICEParameters(
    strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6
)

// raw 도메인(16bit linear)에서 cleaned raw를 평탄화/디코딩하는 컨텍스트.
private let cleanedRawContext = CIContext(options: [
    .useSoftwareRenderer: false,
    .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
    .outputColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
])

private func decodeCleanedRaw(_ url: URL) -> CGImage? {
    autoreleasepool {
        guard let ci = ImageLoader.loadScannerTIFF(url) else { return nil }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        return cleanedRawContext.createCGImage(ci, from: ci.extent, format: .RGBA16, colorSpace: linear)
    }
}

/// 하나의 결함 편집을 16bit linear raw CGImage에 적용한다(brush=스트로크 복원, region=마스크 복원).
/// 입력/출력 도메인이 같아(RGBA16 linear) edits를 순차로 합성할 수 있다. 실패하면 nil(호출측이 스킵).
private func applyDefectEdit(_ edit: DefectEdit, to cg: CGImage,
                            shouldCancel: @escaping @Sendable () -> Bool) -> CGImage? {
    switch edit {
    case .brush(let strokes):
        guard !strokes.isEmpty else { return cg }
        return DefectBrush.removeDefects(in: cg, strokes: strokes, parameters: defectICEParameters,
                                         linear16: true, shouldCancel: shouldCancel)
    case .region(let mask, let roi, let w, let h):
        guard !mask.isEmpty, w > 0, h > 0 else { return cg }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let img = CIImage(cgImage: cg, options: [.colorSpace: linear])
        let maskCI = CIImage(bitmapData: mask, bytesPerRow: w * 4,
                             size: CGSize(width: w, height: h),
                             format: .RGBA8, colorSpace: linear)
            .transformed(by: CGAffineTransform(translationX: roi.minX, y: roi.minY))
        let repaired = SoftwareICE.repair(image: img, roi: roi, mask: maskCI)
        return cleanedRawContext.createCGImage(repaired, from: img.extent, format: .RGBA16, colorSpace: linear)
    }
}

extension AppModel {
    /// 사용자가 칠한 스트로크(표시 좌표)를 변형 전 raw 정규좌표로 변환해 브러시 편집으로 누적한다.
    func applyDefectStrokes(_ displayStrokes: [DefectStroke], to frame: ScanFrame) {
        guard !displayStrokes.isEmpty else { return }
        let transform = frame.imageTransform
        let mapped = displayStrokes.map { stroke in
            DefectStroke(points: stroke.points.map { transform.displayUnitToBase($0) },
                         thickness: stroke.thickness)
        }
        appendDefectEdit(.brush(mapped), to: frame)
    }

    /// 새 편집(브러시/반자동)을 히스토리에 추가하고 cleaned raw를 갱신한다 — 두 ICE의 공통 진입점.
    func appendDefectEdit(_ edit: DefectEdit, to frame: ScanFrame) {
        frame.defectEditUndoStack.append(frame.defectEdits)   // 적용 직전 상태 → ⌘Z 복구
        frame.defectEdits.append(edit)

        // 증분 적용: 진행 중 작업이 없고 현재 cleaned raw가 직전까지의 편집을 모두 담고 있으면, 원본부터
        // 전부 다시 합성하는 대신 신규 편집만 현재 cleaned raw 위에 적용한다(비용이 신규 편집에만 비례).
        // brush/region 모두 칠한/지정한 영역 밖을 건드리지 않으므로 결과가 전체 재빌드와 동일하다.
        let canIncrement = frame.cleanRawTask == nil
            && frame.cleanedRawEditCount == frame.defectEdits.count - 1
            && (frame.cleanedRawImage != nil || frame.cleanedRawDiskURL != nil)
        if canIncrement {
            runCleanedRawBuild(frame, editsToApply: [edit], totalEditCount: frame.defectEdits.count,
                               preloadedBase: frame.cleanedRawImage, baseDiskURL: frame.cleanedRawDiskURL,
                               fromOriginal: false)
        } else {
            rebuildCleanedRaw(frame)
        }
    }

    /// 적용된 결함 제거를 전부 초기화한다(브러시·반자동 모두). undo 스택에 직전 상태를 남긴다.
    func clearAllDefects(_ frame: ScanFrame) {
        guard !frame.defectEdits.isEmpty else { return }
        frame.defectEditUndoStack.append(frame.defectEdits)
        frame.defectEdits = []
        rebuildCleanedRaw(frame)   // edits가 비면 cleaned raw 폐기 후 원본으로 재현상
        statusMessage = "결함 제거 초기화"
    }

    /// ⌘Z: 마지막 "결함 제거" 적용을 취소(다단계). 브러시·반자동 어느 것이든 마지막 편집을 되돌린다.
    func undoDefects(_ frame: ScanFrame) {
        guard let previous = frame.defectEditUndoStack.popLast() else { return }
        frame.defectEdits = previous
        rebuildCleanedRaw(frame)
    }

    /// defectEdits를 원본 raw에 순차 적용 → cleaned raw(메모리 + 디스크 백킹) 갱신 → 재현상.
    /// edits가 비면 cleaned raw를 버리고 원본 raw로 재현상한다. (undo/clear/레이스 시 안전 경로)
    func rebuildCleanedRaw(_ frame: ScanFrame) {
        let edits = frame.defectEdits
        if edits.isEmpty {
            frame.cleanRawRevision += 1
            frame.cleanRawTask?.cancel()
            discardCleanedRaw(frame)
            Task { await developFrame(frame) }
            return
        }
        runCleanedRawBuild(frame, editsToApply: edits, totalEditCount: edits.count,
                           preloadedBase: nil, baseDiskURL: nil, fromOriginal: true)
    }

    /// cleaned raw 빌드 코어. fromOriginal=true면 원본 raw에 editsToApply(=전체) 순차 적용,
    /// false면 현재 cleaned(메모리 preloadedBase → 없으면 디스크 baseDiskURL)에 editsToApply(=신규)만 적용.
    /// 산출물은 고유 파일로 저장하고 커밋 시에만 백킹으로 승격(이전 백킹 삭제) → 경로 클로버 레이스 제거.
    private func runCleanedRawBuild(_ frame: ScanFrame, editsToApply: [DefectEdit],
                                    totalEditCount: Int, preloadedBase: CGImage?,
                                    baseDiskURL: URL?, fromOriginal: Bool) {
        frame.cleanRawRevision += 1
        let revision = frame.cleanRawRevision
        frame.cleanRawTask?.cancel()

        let rawURL = frame.rawScanURL
        let newURL = AppModel.makeCleanedRawURL(for: frame)
        frame.isRemovingDefects = true
        statusMessage = "결함 제거 중"
        let task = Task.detached(priority: .userInitiated) {
            // 풀해상도 디코딩·중간 비트맵은 autoreleasepool 안에서 처리해 cleaned 외에는 즉시 해제한다
            // (메모리 급증 방지 — Apple 권장 패턴).
            let cleaned: CGImage? = autoreleasepool {
                let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
                let inputCG: CGImage?
                if !fromOriginal, let pre = preloadedBase {
                    inputCG = pre                                   // 증분: 메모리 cleaned 재사용
                } else if !fromOriginal, let url = baseDiskURL {
                    inputCG = decodeCleanedRaw(url)                 // 증분: 디스크 백킹에서 복원
                } else {
                    let engine = ChromabaseEngine()                // 전체: 원본 raw 디코드
                    if let rawCI = engine.loadScannerImage(rawURL), !Task.isCancelled {
                        inputCG = cleanedRawContext.createCGImage(rawCI, from: rawCI.extent,
                                                                  format: .RGBA16, colorSpace: linear)
                    } else { inputCG = nil }
                }
                guard var working = inputCG, !Task.isCancelled else { return nil }
                // 편집을 순서대로 합성. 각 편집은 직전 결과 위에 적용된다 → 브러시·반자동이 누적되고
                // 서로 덮어쓰지 않는다. 한 편집이 실패하면 건너뛰고 나머지를 계속 적용한다.
                for edit in editsToApply {
                    if Task.isCancelled { return nil }
                    if let next = applyDefectEdit(edit, to: working, shouldCancel: { Task.isCancelled }) {
                        working = next
                    }
                }
                return Task.isCancelled ? nil : working
            }
            guard !Task.isCancelled, let cleaned else {
                await MainActor.run {
                    guard frame.cleanRawRevision == revision else { return }
                    frame.isRemovingDefects = false
                    frame.cleanRawTask = nil
                    if !Task.isCancelled { self.statusMessage = "결함 제거 실패" }
                }
                return
            }
            ImageLoader.saveScannerTIFF(cleaned, to: newURL)
            let committed: Bool = await MainActor.run {
                // 더 새 작업이 떴으면 이 산출물만 버린다(기존 백킹은 보존).
                guard frame.cleanRawRevision == revision else {
                    try? FileManager.default.removeItem(at: newURL)
                    return false
                }
                let previous = frame.cleanedRawDiskURL
                frame.cleanedRawImage = cleaned
                frame.cleanedRawDiskURL = newURL
                frame.cleanedRawEditCount = totalEditCount
                frame.cleanRawTask = nil
                self.cleanedRawResidentInsert(frame)
                if let previous, previous != newURL { try? FileManager.default.removeItem(at: previous) }
                return true
            }
            // 결함 제거가 화면에 실제로 반영될 때까지 스피너를 유지한다(ICE 단계만 덮지 않도록).
            if committed { await self.developFrame(frame) }
            await MainActor.run {
                guard frame.cleanRawRevision == revision else { return }
                frame.isRemovingDefects = false
                if self.statusMessage == "결함 제거 중" { self.statusMessage = "" }   // 끝나면 바로 지운다
            }
        }
        frame.cleanRawTask = task
    }

    /// 선택된 프레임의 cleaned raw를 메모리에 적재한다(없으면 디스크 백킹에서 로드). FIFO를 갱신한다.
    func ensureCleanedRawResident(_ frame: ScanFrame) {
        if frame.cleanedRawImage != nil {
            cleanedRawResidentInsert(frame)   // 이미 메모리에 있음 — FIFO 순서만 갱신
            return
        }
        guard let url = frame.cleanedRawDiskURL else { return }   // 결함 제거 없는 프레임
        let revision = frame.cleanRawRevision
        Task.detached(priority: .userInitiated) {
            let cg = decodeCleanedRaw(url)
            await MainActor.run {
                guard frame.cleanRawRevision == revision, let cg else { return }
                frame.cleanedRawImage = cg
                self.cleanedRawResidentInsert(frame)
            }
        }
    }

    /// FIFO에 프레임을 (재)등록하고, 한도를 넘으면 가장 오래된 프레임의 메모리 적재본을 내려놓는다
    /// (디스크 백킹은 유지).
    func cleanedRawResidentInsert(_ frame: ScanFrame) {
        residentCleanedRawIDs.removeAll { $0 == frame.id }
        residentCleanedRawIDs.append(frame.id)
        while residentCleanedRawIDs.count > maxResidentCleanedRaw {
            let evictID = residentCleanedRawIDs.removeFirst()
            if evictID != frame.id, let evicted = frames.first(where: { $0.id == evictID }) {
                evicted.cleanedRawImage = nil
            }
        }
    }

    /// 발색 결과 FIFO에 프레임을 (재)등록하고, 한도를 넘으면 가장 오래된 비선택 프레임의 풀해상도
    /// 버퍼를 내려놓는다(썸네일은 유지). 선택 프레임은 절대 내려놓지 않는다.
    func markDevelopedResident(_ frame: ScanFrame) {
        residentDevelopedIDs.removeAll { $0 == frame.id }
        residentDevelopedIDs.append(frame.id)
        while residentDevelopedIDs.count > maxResidentDeveloped {
            guard let evictID = residentDevelopedIDs.first else { break }
            if evictID == selectedFrameID {
                // 선택 프레임이 가장 오래된 자리에 있으면 건너뛰고 그다음을 후보로(맨 뒤로 회전).
                residentDevelopedIDs.removeFirst()
                residentDevelopedIDs.append(evictID)
                // 회전만 반복되지 않도록: 선택 프레임 하나만 남으면 종료.
                if residentDevelopedIDs.allSatisfy({ $0 == selectedFrameID }) { break }
                continue
            }
            residentDevelopedIDs.removeFirst()
            if let evicted = frames.first(where: { $0.id == evictID }) {
                evictDevelopBuffers(evicted)
            }
        }
    }

    /// 비활성 프레임의 풀해상도 발색 버퍼를 해제한다(썸네일/현상완료 플래그/base는 유지).
    /// 재진입 시 raw(또는 cleaned raw)에서 재현상해 즉시 복원한다.
    func evictDevelopBuffers(_ frame: ScanFrame) {
        frame.developedImage = nil
        frame.rawPreviewImage = nil
        frame.neutralPreviewImage = nil
        frame.rawPreviewTransform = nil
        frame.neutralPreviewTransform = nil
        frame.neutralPreviewBaseKey = nil
        frame.cachedDevelopedBase = nil
        frame.cachedRawBase = nil
        frame.cachedNeutralBase = nil
        frame.clearPreviewRawCaches()
        if !frame.debugPreviewImages.isEmpty { frame.debugPreviewImages = [:] }
        if !frame.debugMetrics.isEmpty { frame.debugMetrics = [:] }
    }

    /// 프레임의 cleaned raw를 메모리·디스크 모두에서 제거한다(프레임 삭제/편집 초기화 시).
    func discardCleanedRaw(_ frame: ScanFrame) {
        frame.cleanRawTask?.cancel()
        frame.cleanedRawImage = nil
        if let url = frame.cleanedRawDiskURL { try? FileManager.default.removeItem(at: url) }
        frame.cleanedRawDiskURL = nil
        frame.cleanedRawEditCount = 0
        frame.clearPreviewRawCaches()
        residentCleanedRawIDs.removeAll { $0 == frame.id }
    }

    private static func makeCleanedRawURL(for frame: ScanFrame) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-ice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 빌드마다 고유 파일명 — 진행 중 빌드가 커밋된 백킹을 덮어쓰는 경로 클로버 레이스를 없앤다.
        // 디렉토리 전체가 앱 시작 시 청소되므로 잔재가 공간을 남기지 않는다.
        return dir.appendingPathComponent("\(frame.id.uuidString)-\(UUID().uuidString).tiff")
    }
}
