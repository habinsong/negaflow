import Foundation
import Chromabase
import CoreGraphics
import CoreImage
import ImageIO

extension SANEBackend {
    /// scanimage -A 출력을 ScannerCapabilities로 변환한다.
    /// 형식 예: `--resolution 7200|3600|2400|1200|600dpi [600]`
    static func parseCapabilities(_ dump: String) -> ScannerCapabilities {
        var resolutions: [Resolution] = []
        var modes: [ColorMode] = []
        var bitDepths: [BitDepth] = []
        var supportsTransparency = false
        var supportsHardwareExposure = false

        for raw in dump.split(separator: "\n") {
            let line = String(raw)
            // --mode Color|Gray [Gray]
            if let r = captureAfter(line, option: "--mode") {
                let opts = r.split(whereSeparator: { $0 == "|" || $0 == " " })
                    .map { String($0).lowercased() }
                if opts.contains("color") { modes.append(.color) }
                if opts.contains("gray")  { modes.append(.gray) }
                if opts.contains("lineart") { modes.append(.lineart) }
            }
            // --depth 16 [16]
            if let r = captureAfter(line, option: "--depth") {
                for tok in r.split(whereSeparator: { $0 == " " || $0 == "|" }) {
                    if let v = Int(tok), let d = BitDepth(rawValue: v) { bitDepths.append(d) }
                }
            }
            // --resolution 7200|3600|2400|1200|600dpi [600]
            if let r = captureAfter(line, option: "--resolution") {
                for tok in r.split(whereSeparator: { $0 == "|" || $0 == " " }) {
                    let cleaned = tok.replacingOccurrences(of: "dpi", with: "")
                    if let v = Int(cleaned) { resolutions.append(Resolution(v)) }
                }
            }
            // --source Transparency Adapter [Transparency Adapter]
            if let r = captureAfter(line, option: "--source") {
                if r.localizedCaseInsensitiveContains("transparency") || r.localizedCaseInsensitiveContains("tpa") {
                    supportsTransparency = true
                }
            }
            if line.contains("--scan-exposure-time") {
                supportsHardwareExposure = true
            }
        }
        // 디폴트 보정 (비어 있으면 8200i 검증값)
        if resolutions.isEmpty { resolutions = [.r900, .r1800, .r3600, .r7200] }
        if modes.isEmpty { modes = [.color, .gray] }
        if bitDepths.isEmpty { bitDepths = [.eight, .sixteen] }

        return ScannerCapabilities(
            supportedResolutions: resolutions.sorted(),
            supportedModes: modes,
            supportedBitDepths: bitDepths,
            supportsPreview: true,
            supportsTransparency: supportsTransparency,
            // genesys 백엔드는 8200i에서 IR 옵션을 노출하지 않는다. (Phase 5 과제)
            supportsInfrared: false,
            supportsMultiExposure: supportsHardwareExposure,
            supportsScanArea: true,
            supportsLampWarmupStatus: true,
            outputFormats: ["tiff", "pnm"]
        )
    }

    private static func captureAfter(_ line: String, option: String) -> String? {
        guard let r = line.range(of: option) else { return nil }
        let after = line[r.upperBound...]
        // ` Color|Gray [Gray]` → "Color|Gray [Gray]"
        return after.trimmingCharacters(in: .whitespaces)
    }

    // MARK: scan
}
