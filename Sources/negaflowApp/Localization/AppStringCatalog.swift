import Foundation

enum AppStringCatalog {
    static func frameCount(_ count: Int, language: AppLanguage) -> String {
        plural(key: "frame_count", count: count, language: language)
    }

    static func defectCount(_ count: Int, language: AppLanguage) -> String {
        plural(key: "defect_count", count: count, language: language)
    }

    private static func plural(
        key: String,
        count: Int,
        language: AppLanguage
    ) -> String {
        let resourceBundle = AppLocalizationResourceBundle.bundle
        let languageCode = language.resolved.rawValue
        let localizedBundle = Self.localizationBundle(
            for: languageCode, in: resourceBundle
        ) ?? resourceBundle
        let format = localizedBundle.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
        return String(
            format: format,
            locale: Locale(identifier: languageCode),
            arguments: [Int64(count)]
        )
    }

    /// 요청한 언어의 `.lproj` 번들.
    ///
    /// 번들 루트에 `<lang>.lproj` 가 있다고 가정하면 **앱 번들에서 항상 실패한다** — 앱은
    /// `Contents/Resources` 아래에 두기 때문이다. 실패하면 시스템 언어로 폴백해서, 앱 언어를
    /// 영어로 바꿔도 복수형 문자열(결함/프레임 개수)만 한국어로 나왔다. 번들의 리소스 경로를
    /// 실제로 찾는 `path(forResource:ofType:)` 으로 해결한다(SwiftPM 번들도 같은 경로로 찾는다).
    /// 대소문자를 그대로 쓴다 — `zh-Hans.lproj` 는 소문자로 바꾸면 못 찾는 파일 시스템이 있다.
    private static func localizationBundle(
        for languageCode: String,
        in resourceBundle: Bundle
    ) -> Bundle? {
        if let path = resourceBundle.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        // SwiftPM 리소스 번들처럼 루트에 바로 두는 경우의 폴백.
        let rootURL = resourceBundle.bundleURL.appendingPathComponent(
            "\(languageCode).lproj", isDirectory: true
        )
        return Bundle(url: rootURL)
    }
}

private enum AppLocalizationResourceBundle {
    /// 복수형 문자열(`Localizable.stringsdict`)이 실제로 들어 있는 번들.
    ///
    /// SwiftPM 으로 실행하면 `.module` 이지만, Xcode 로 앱을 빌드하면 `SWIFT_PACKAGE` 가 정의되지
    /// 않아 `.main` 이 된다. 그런데 패키지 리소스는 앱 번들 안에 **중첩된**
    /// `negaflow_negaflowApp.bundle` 로 들어가므로 `.main` 에는 Localizable 테이블이 없다 —
    /// 그대로 조회하면 앱 언어 설정과 무관한 문자열이 나온다("결함 727개"가 영어 UI에 섞이던 원인).
    /// 중첩 리소스 번들을 찾아서 쓴다.
    static let bundle: Bundle = {
#if SWIFT_PACKAGE
        return .module
#else
        for name in ["negaflow_negaflowApp", "negaflowApp"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "bundle"),
               let nested = Bundle(url: url) {
                return nested
            }
        }
        return .main
#endif
    }()
}
