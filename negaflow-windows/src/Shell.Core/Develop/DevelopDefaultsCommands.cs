using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>
/// 프로세스·타깃 전환의 단 하나의 구현입니다. macOS <c>AppModel.applyDevelopmentProcess</c> ·
/// <c>applyDevelopTarget</c> 자리이며, 그쪽도 화면이 아니라 모델이 들고 있습니다.
///
/// 예전에는 이 로직이 라이브러리 좌측탭의 <c>LibraryDevelopDefaultsPanel</c> 안에만 있어
/// 단축키가 **그 컨트롤이 화면에 있어야만** 동작했습니다. macOS 좌측탭에는 그 구획이 아예
/// 없으므로(폴더 머리줄이 그 일을 합니다) 컨트롤을 떼면 단축키가 통째로 죽습니다.
/// 그래서 카탈로그를 고치는 부분만 여기로 내려 두 곳이 같은 길을 타게 합니다.
/// </summary>
public static class DevelopDefaultsCommands
{
    /// <summary>
    /// 타깃을 바꿉니다. macOS 처럼 **스캐너 프로파일도 함께 정리합니다** — 남겨 두면 타깃의
    /// 성격과 프로파일의 성격이 겹칩니다.
    /// </summary>
    public static LibraryFrameError ApplyTarget(
        LibraryHostService host,
        LibraryFrameSnapshot frame,
        DevelopTarget target)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(frame);
        string? profileId = DevelopTargets.ProfileAfterTargetChange(
            target,
            frame.Route.FilmType,
            frame.Base.ScannerProfileId);
        return host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                frame.Base with { ScannerProfileId = profileId },
                DevelopTarget: target));
    }

    /// <summary>필름 프로파일(HS·SP 갈래의 기종별 프로파일)만 바꿉니다.</summary>
    public static LibraryFrameError ApplyScannerProfile(
        LibraryHostService host,
        LibraryFrameSnapshot frame,
        string? profileId)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(frame);
        return host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                frame.Base with { ScannerProfileId = profileId }));
    }

    public static LibraryFrameError ApplyProcess(
        LibraryHostService host,
        LibraryFrameSnapshot frame,
        DevelopmentProcess process)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(frame);
        return host.EditRoute(frame.Id, DevelopRouteSelection.FromProcess(process));
    }

    /// <summary>macOS 워크플로 메뉴의 프로세스 명령 넷을 프로세스 값으로 옮깁니다.</summary>
    public static DevelopmentProcess ProcessFor(Shortcuts.WorkflowShortcutAction action) =>
        action switch
        {
            Shortcuts.WorkflowShortcutAction.ProcessColorPositive => DevelopmentProcess.E6,
            Shortcuts.WorkflowShortcutAction.ProcessBwNegative => DevelopmentProcess.D76,
            Shortcuts.WorkflowShortcutAction.ProcessBwPositive =>
                DevelopmentProcess.BlackAndWhiteReversal,
            _ => DevelopmentProcess.C41,
        };
}
