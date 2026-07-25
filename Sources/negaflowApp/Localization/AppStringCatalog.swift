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
        let localizationURL = resourceBundle.bundleURL.appendingPathComponent(
            "\(languageCode.lowercased()).lproj",
            isDirectory: true
        )
        let localizedBundle = Bundle(url: localizationURL) ?? resourceBundle
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
}

private enum AppLocalizationResourceBundle {
    static var bundle: Bundle {
#if SWIFT_PACKAGE
        .module
#else
        .main
#endif
    }
}
