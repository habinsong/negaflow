import Chromabase

extension ScanFrame {
    /// params 대입을 사용하는 undo·복원도 같은 무효화 경계를 통과합니다.
    /// 원본 identity와 수락한 결함 recipe는 그대로 보존합니다.
    func invalidateInputInterpretation() {
        developRevision += 1
        transformRevision += 1
        cleanRawRevision += 1
        defectDetectRevision += 1
        initialThumbnailSeedGeneration += 1
        initialThumbnailSeedTask?.cancel()
        initialThumbnailSeedTask = nil
        transformTask?.cancel()
        cleanRawTask?.cancel()
        cleanRawTask = nil
        cleanedRawPersistTask?.cancel()
        cleanedRawPersistTask = nil
        defectDetectTask?.cancel()
        defectDetectTask = nil
        defectSessionSolidifyTask?.cancel()
        defectSessionSolidifyTask = nil
        printPackagePreviewGeneration &+= 1
        printPackagePreviewTask?.cancel()
        printPackagePreviewTask = nil
        printPackagePreviewImage = nil
        cleanedRawImage = nil
        cleanedRawCanvas = nil
        cleanedRawMemoryIdentity = nil
        // 백그라운드 출력이 보유한 이전 snapshot을 위해 파일은 여기서 지우지 않습니다.
        cleanedRawDiskURL = nil
        cleanedRawDiskIdentity = nil
        cleanedRawPreviousImage = nil
        cleanedRawPreviousIdentity = nil
        cleanedRawPreviousEditCount = -1
        cleanedRawEditCount = 0
        cleanedRawAppliedStamps = []
        stripDefectPatchCaches()
        defectSessionRaw = nil
        defectSessionRawRevision = -1
        defectActive = false
        defectIsDetecting = false
        defectIsRemoving = false
        isRemovingDefects = false
        defectPreview = []
        defectLabelField = nil
        defectExcludedIDs = []
        infraredAutoCleanAttempted = false
        clearPreviewRawCaches()
        cachedBase = nil
        cachedBaseKey = nil
        baseRGB = nil
        cachedSceneMeasurementsKey = nil
        cachedInteractiveSceneMeasurements = nil
        cachedSettledSceneMeasurements = nil
        rawPreviewImage = nil
        neutralPreviewImage = nil
        mainPreviewImage = nil
        // 새 감마의 프리뷰가 준비될 때까지 현재 화면을 유지합니다.
        clippingOverlayImage = nil
        destinationGamutOverlayImage = nil
        thumbnailRecipeID = nil
        cachedRawBase = nil
        cachedNeutralBase = nil
        cachedMainBase = nil
        cachedDevelopedBase = nil
        cachedClippingOverlayBase = nil
        cachedDestinationGamutOverlayBase = nil
        cachedThumbnailBase = nil
        neutralPreviewBaseKey = nil
        developedIsSettled = false
        debugPreviewImages = [:]
        debugMetrics = [:]
    }
}
