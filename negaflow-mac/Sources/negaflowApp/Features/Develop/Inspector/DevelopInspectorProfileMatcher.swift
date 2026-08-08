import Chromabase

enum DevelopInspectorProfileMatcher {
    @MainActor
    static func matchingProfiles(frame: ScanFrame, profiles: [ScannerProfile]) -> [ScannerProfile] {
        ScannerProfileMatcher.matchingProfiles(
            target: frame.params.developTarget,
            filmType: frame.params.filmType,
            profiles: profiles
        )
    }

    @MainActor
    static func autoMatchedScannerProfileID(
        frame: ScanFrame,
        profiles: [ScannerProfile],
        filmStockDminID: String?
    ) -> String? {
        ScannerProfileMatcher.preferredProfileID(
            target: frame.params.developTarget,
            filmType: frame.params.filmType,
            filmStockDminID: filmStockDminID,
            currentID: nil,
            profiles: profiles
        )
    }
}
