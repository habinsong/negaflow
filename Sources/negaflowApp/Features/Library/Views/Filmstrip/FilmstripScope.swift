import Foundation

/// 현상·인화 하단 필름스트립이 어떤 사진을 보여줄지. 기준은 지금 열려 있는 사진이다.
enum FilmstripScope: String, CaseIterable, Identifiable {
    case all
    case folder
    case process
    case target

    var id: Self { self }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .all:
            AppLocalization.text(AppLocalizedPhrase.libraryAllShort, language: language)
        case .folder:
            AppLocalization.text(AppLocalizedPhrase.filmstripScopeFolder, language: language)
        case .process:
            AppLocalization.text(AppLocalizedPhrase.process, language: language)
        case .target:
            AppLocalization.text(AppLocalizedPhrase.target, language: language)
        }
    }

    /// 기준 사진과 같은 범위에 속한 사진만 남긴다. 기준이 없으면 전체를 보여준다 —
    /// 기준 사진은 언제나 자기 범위에 포함되므로 현재 선택이 목록 밖으로 밀려나지 않는다.
    @MainActor
    func filtered(_ frames: [ScanFrame], reference: ScanFrame?) -> [ScanFrame] {
        guard let reference, self != .all else { return frames }
        switch self {
        case .all:
            return frames
        case .folder:
            let path = Self.folderPath(of: reference)
            return frames.filter { Self.folderPath(of: $0) == path }
        case .process:
            let process = Self.process(of: reference)
            return frames.filter { Self.process(of: $0) == process }
        case .target:
            let target = reference.params.developTarget
            return frames.filter { $0.params.developTarget == target }
        }
    }

    @MainActor
    private static func folderPath(of frame: ScanFrame) -> String {
        LibraryPresentation.normalizedFolderPath(LibraryPresentation.folderURL(for: frame))
    }

    @MainActor
    private static func process(of frame: ScanFrame) -> DevelopmentProcess {
        DevelopmentProcess(
            filmType: frame.filmType,
            isDigitalSource: frame.params.isDigitalSource
        )
    }
}
