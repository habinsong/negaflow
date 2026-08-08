import Foundation

public enum ScannerNoiseProfileSelection {
    public static func automaticProfile(
        for captureKey: ScannerNoiseCaptureKey,
        profiles: [ScannerNoiseProfile]
    ) -> ScannerNoiseProfile? {
        let matches = profiles.filter {
            $0.captureKey == captureKey && $0.allowsAutomaticUse
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}
