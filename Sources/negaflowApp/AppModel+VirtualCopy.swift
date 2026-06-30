import Foundation

extension ScanFrame {
    func makeVirtualCopy(copyNumber: Int) -> ScanFrame {
        let copy = ScanFrame(
            scanIndex: scanIndex,
            rawScanURL: rawScanURL,
            filmType: filmType,
            initialTransform: imageTransform,
            scannedAt: scannedAt,
            sourceFrameID: rootFrameID,
            sourceFrameDisplayName: rootFrameDisplayName,
            virtualCopyNumber: copyNumber
        )
        copy.preset = preset
        copy.params = params
        copy.imageTransform = imageTransform
        copy.baseRGB = baseRGB
        copy.developHistory = developHistory
        copy.developSnapshots = developSnapshots
        copy.rawPreviewImage = rawPreviewImage
        copy.developedImage = developedImage
        copy.thumbnailImage = thumbnailImage
        copy.hasDevelopedOnce = hasDevelopedOnce
        copy.showDeveloped = showDeveloped
        copy.rawPreviewTransform = rawPreviewTransform
        copy.developRevision = developRevision
        copy.cachedBaseKey = cachedBaseKey
        copy.cachedBase = cachedBase
        copy.cachedDevelopedBase = cachedDevelopedBase
        copy.cachedRawBase = cachedRawBase
        // defectEdits는 복사하되 cleaned raw 임시 파일은 공유하지 않는다(각 프레임이 자기 파일을
        // 새로 생성해야 한 쪽 삭제가 다른 쪽을 깨뜨리지 않는다).
        copy.defectEdits = defectEdits
        copy.defectEditUndoStack = defectEditUndoStack
        return copy
    }
}

extension AppModel {
    func createVirtualCopy(from frame: ScanFrame) {
        let copyNumber = nextVirtualCopyNumber(for: frame)
        let copy = frame.makeVirtualCopy(copyNumber: copyNumber)
        if let index = frames.firstIndex(where: { $0.id == frame.id }) {
            frames.insert(copy, at: frames.index(after: index))
        } else {
            frames.append(copy)
        }
        selectedFrameID = copy.id
        // 결함 제거가 있으면 복사본 전용 cleaned raw를 새로 만든다.
        if !copy.defectEdits.isEmpty { rebuildCleanedRaw(copy) }
        statusMessage = "Virtual Copy 생성됨: \(copy.displayName)"
    }

    private func nextVirtualCopyNumber(for frame: ScanFrame) -> Int {
        let rootID = frame.rootFrameID
        let existingNumbers = frames.compactMap { candidate -> Int? in
            guard candidate.rootFrameID == rootID else { return nil }
            return candidate.virtualCopyNumber
        }
        return (existingNumbers.max() ?? 0) + 1
    }
}
