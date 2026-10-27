import Chromabase
import Foundation

/// 워터마크 로고를 경로에서 읽는다. 설정·템플릿은 경로만 들고, 그릴 때마다 여기서 그림을 채운다.
///
/// - 로고를 켜고 경로를 비워 두면 negaflow 로고(앱 아이콘)를 쓴다.
/// - 경로의 파일이 지워졌거나 옮겨졌거나 그림이 아니면 nil 을 돌려줘 **로고만 빠지게** 한다. 앱이
///   멈추거나 내보내기가 실패하지 않는다. 그 사실은 검사기에 띄우지 않고 하단 상태 점과 진단의
///   오류 기록(`reportMissing`)에만 남긴다 — 같은 경로는 다시 찾을 때까지 한 번만 남긴다.
/// - 같은 파일(크기·수정 시각이 같음)은 다시 읽지 않는다.
@MainActor
enum PrintWatermarkLogoLoader {
    private struct Entry {
        let size: Int
        let modified: Date?
        let png: Data?
    }

    private static var cache: [String: Entry] = [:]
    private static var reportedMissing: Set<String> = []

    /// 경로의 로고를 읽을 수 없을 때 부른다(AppModel 이 오류 기록에 남긴다).
    static var reportMissing: ((String) -> Void)?

    /// 설정이 쓰는 로고. 꺼져 있으면 nil.
    static func logo(for settings: PrintWatermarkSettings) -> Data? {
        guard settings.showsLogo else { return nil }
        return settings.logoSourcePath.isEmpty ? builtIn : png(at: settings.logoSourcePath)
    }

    /// negaflow 로고(앱 아이콘). 앱 리소스 번들에 있다.
    static let builtIn: Data? = AppLocalizationResourceBundle.bundle
        .url(forResource: "AppIcon-1024", withExtension: "png")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap(PrintWatermarkRenderer.normalizedLogoPNG(from:))

    static func png(at path: String) -> Data? {
        guard !path.isEmpty else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.type] as? FileAttributeType) == .typeRegular else {
            cache[path] = nil
            noteMissing(path)
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
        let modified = attributes[.modificationDate] as? Date
        if let entry = cache[path], entry.size == size, entry.modified == modified {
            return entry.png
        }
        let png = (try? Data(contentsOf: URL(fileURLWithPath: path)))
            .flatMap(PrintWatermarkRenderer.normalizedLogoPNG(from:))
        cache[path] = Entry(size: size, modified: modified, png: png)
        if png == nil {
            noteMissing(path)
        } else {
            reportedMissing.remove(path)
        }
        return png
    }

    private static func noteMissing(_ path: String) {
        guard reportedMissing.insert(path).inserted else { return }
        // 화면을 그리는 도중에 불릴 수 있으므로 기록은 다음 차례로 미룬다(그리는 중 상태 변경 금지).
        Task { @MainActor in reportMissing?(path) }
    }
}

extension PrintWatermarkSettings {
    /// 로고를 채운 사본. 꺼져 있거나 읽을 수 없으면 로고 없이 돌려준다.
    @MainActor
    func resolvingLogo() -> PrintWatermarkSettings {
        var result = self
        result.logoPNGData = PrintWatermarkLogoLoader.logo(for: self)
        return result
    }
}

extension AppModel {
    /// 로고 파일을 찾지 못하면 하단 상태 점과 진단의 오류 기록에 남긴다(검사기에는 띄우지 않는다).
    func observePrintWatermarkLogoProblems() {
        PrintWatermarkLogoLoader.reportMissing = { [weak self] path in
            guard let self else { return }
            let message = PrintWatermarkLocalizedText.logoMissing.resolved(language: self.appLanguage)
                + " " + URL(fileURLWithPath: path).lastPathComponent
            self.errorLog.record(message)
        }
    }
}
