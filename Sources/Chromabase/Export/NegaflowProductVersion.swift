import Foundation

/// 앱 번들, CLI, 엔진 sidecar가 공유하는 제품 버전 소스.
/// `scripts/run-app.sh`도 같은 ProductVersion.txt로 CFBundleShortVersionString을 만든다.
public enum NegaflowProductVersion {
    public static let current: String = {
        guard let url = Bundle.module.url(forResource: "ProductVersion", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return "unknown"
        }
        let version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? "unknown" : version
    }()

    /// 패키징된 앱에서는 실제 Info.plist 버전을 사용하고, CLI/XCTest에서는 공유 리소스로 폴백한다.
    public static func applicationVersion(in bundle: Bundle = .main) -> String {
        guard bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let bundled = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return current
        }
        let version = bundled.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? current : version
    }

    public static var rendererVersion: String {
        "chromabase/\(current)"
    }
}
