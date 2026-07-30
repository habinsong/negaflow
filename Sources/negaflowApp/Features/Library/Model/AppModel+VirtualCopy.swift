import Foundation

extension ScanFrame {
    func makeVirtualCopy(copyNumber: Int) -> ScanFrame {
        let copy = ScanFrame(
            scanIndex: scanIndex,
            rawScanURL: rawScanURL,
            filmType: filmType,
            infraredScanURL: infraredScanURL,
            rawScanBookmarkData: rawScanBookmarkData,
            infraredScanBookmarkData: infraredScanBookmarkData,
            sourceKind: sourceKind,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            sourceResolutionDPI: sourceResolutionDPI,
            sourceBitDepth: sourceBitDepth,
            sourceMetadata: sourceMetadata,
            appMetadataOverlay: appMetadataOverlay,
            scanSessionID: scanSessionID,
            scanJobID: scanJobID,
            initialTransform: imageTransform,
            scannedAt: scannedAt,
            sourceFrameID: rootFrameID,
            sourceFrameDisplayName: rootFrameDisplayName,
            virtualCopyNumber: copyNumber,
            storageGroupName: storageGroupName
        )
        copy.preset = preset
        copy.params = params
        copy.imageTransform = imageTransform
        copy.baseRGB = baseRGB
        copy.developHistory = developHistory
        copy.developSnapshots = developSnapshots
        copy.rawPreviewImage = rawPreviewImage
        copy.developedImage = developedImage
        copy.clippingOverlayImage = clippingOverlayImage
        copy.destinationGamutOverlayImage = destinationGamutOverlayImage
        copy.displayPixelSize = displayPixelSize
        copy.thumbnailImage = thumbnailImage
        copy.hasDevelopedOnce = hasDevelopedOnce
        copy.showDeveloped = showDeveloped
        copy.developedPreviewTransform = developedPreviewTransform
        copy.rawPreviewTransform = rawPreviewTransform
        copy.developRevision = developRevision
        copy.cachedBaseKey = cachedBaseKey
        copy.cachedBase = cachedBase
        copy.cachedDevelopedBase = cachedDevelopedBase
        copy.cachedClippingOverlayBase = cachedClippingOverlayBase
        copy.cachedDestinationGamutOverlayBase = cachedDestinationGamutOverlayBase
        copy.cachedThumbnailBase = cachedThumbnailBase
        copy.cachedRawBase = cachedRawBase
        copy.displayedSoftProofRevision = displayedSoftProofRevision
        copy.proofCopyConfiguration = proofCopyConfiguration
        // defectEdits는 복사하되 cleaned raw 임시 파일은 공유하지 않는다(각 프레임이 자기 파일을
        // 새로 생성해야 한 쪽 삭제가 다른 쪽을 깨뜨리지 않는다).
        copy.defectEdits = defectEdits
        copy.defectEditUndoStack = defectEditUndoStack
        if let recipeSHA256 = copy.currentLibraryDevelopRecipeSHA256() {
            // 가상 사본은 생성 시점의 recipe를 독립 기준점으로 삼고, 원본의 내보내기·검토
            // 이력을 물려받지 않는다.
            copy.libraryWorkflowTrackingState = .newFrame(currentRecipeSHA256: recipeSHA256)
        }
        return copy
    }
}

extension AppModel {
    func createVirtualCopy(from frame: ScanFrame) {
        guard let copy = insertVirtualCopy(from: frame) else { return }
        statusMessage = text(AppLocalizedPhrase.virtualCopyCreatedFormat, copy.displayName)
    }

    @discardableResult
    func createProofCopy(from frame: ScanFrame) -> ScanFrame? {
        let settings = displaySoftProofSettings(for: frame)
        let usesCPrintProfile = settings.iccProfileData != nil
            && settings.iccProfileData == cPrintProofICCProfileData
        let usesPrinterProfile = settings.iccProfileData != nil
            && settings.iccProfileData == printerOutputICCProfileData
        let profileName: String
        if usesCPrintProfile {
            profileName = cPrintProofICCProfileName ?? "C-print ICC"
        } else if usesPrinterProfile {
            profileName = printerOutputICCProfileName ?? "Printer ICC"
        } else {
            profileName = softProofICCProfileName ?? exportColorSpace.uiLabel
        }
        guard let configuration = ProofCopyConfiguration(
            settings: settings,
            profileName: profileName
        ) else { return nil }
        guard let copy = insertVirtualCopy(from: frame, configure: { copy in
            copy.proofCopyConfiguration = configuration
            copy.customDisplayName = text(
                AppLocalizedPhrase.proofCopyNameFormat,
                frame.rootFrameDisplayName(language: appLanguage),
                profileName
            )
        }) else { return nil }
        statusMessage = text(AppLocalizedPhrase.proofCopyCreatedFormat, copy.displayName)
        return copy
    }

    private func insertVirtualCopy(
        from frame: ScanFrame,
        configure: (ScanFrame) -> Void = { _ in }
    ) -> ScanFrame? {
        guard allowsLibraryMutation, ownsFrame(frame), !frame.isPreviewScan else { return nil }
        let family = frames.filter {
            !$0.isPreviewScan && $0.rootFrameID == frame.rootFrameID
        }
        guard !family.isEmpty,
              let lastFamilyIndex = frames.indices.last(where: {
                  !frames[$0].isPreviewScan
                      && frames[$0].rootFrameID == frame.rootFrameID
        }) else { return nil }
        let sourceRollID = rollStore.rollID(containing: frame.id)
        guard sourceRollID != nil else { return nil }
        let copyNumber = nextVirtualCopyNumber(for: frame)
        let copy = frame.makeVirtualCopy(copyNumber: copyNumber)
        configure(copy)
        guard rollStore.insertVirtualCopy(
            copy.id,
            afterFamilyFrameIDs: family.map(\.id)
        ) else { return nil }
        frames.insert(copy, at: frames.index(after: lastFamilyIndex))
        selectedFrameID = copy.id
        // 결함 제거가 있으면 복사본 전용 cleaned raw를 새로 만든다.
        if !copy.defectEdits.isEmpty { rebuildCleanedRaw(copy) }
        return copy
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
