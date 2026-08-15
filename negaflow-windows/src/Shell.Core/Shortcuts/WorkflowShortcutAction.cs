namespace Negaflow.Shell.Shortcuts;

/// <summary>macOS <c>WorkflowShortcutGroup</c> 과 같은 묶음입니다. 설정 표의 머리줄이 됩니다.</summary>
public enum WorkflowShortcutGroup
{
    Library,
    Photo,
    Develop,
    View,
    Scanner,
    Export,
}

/// <summary>
/// 단축키가 부르는 명령입니다.
/// </summary>
/// <remarks>
/// macOS 는 57개를 냅니다. 여기 있는 것은 그중 **Windows 가 실제로 할 수 있는 것들**이며, 이름과
/// 기본 키는 macOS 와 같습니다. 아직 못 하는 명령(가상 사본, 비교·설문 보기, HS/SP/F135 대상
/// 등)을 목록에만 올리면 사용자는 눌러도 아무 일이 없는 키를 배우게 됩니다 — 이 저장소가
/// 파일명 토큰에서 이미 내린 것과 같은 판단입니다. 그 명령이 붙는 날 여기에 한 줄씩 늘립니다.
/// </remarks>
public enum WorkflowShortcutAction
{
    ImportImages,
    ImportFolder,
    RefreshLibrary,
    PreviousPhoto,
    NextPhoto,
    PickPhoto,
    ClearPick,
    RejectPhoto,
    DeletePhoto,
    RateZero,
    RateOne,
    RateTwo,
    RateThree,
    RateFour,
    RateFive,
    ResetAdjustments,
    CopyDevelopSettings,
    PasteDevelopSettings,
    ProcessColorNegative,
    ProcessColorPositive,
    ProcessBwNegative,
    ProcessBwPositive,
    RotateLeft,
    RotateRight,
    FlipHorizontal,
    FlipVertical,
    ToggleBeforeAfter,
    ShowHideSidebar,
    ShowHideFilmstrip,
    ShowHideInspector,
    OpenLibraryWorkspace,
    OpenDevelopWorkspace,
    DetectScanners,
    PreviewScan,
    ScanFrame,
    QuickExport,
    ExportPhoto,
}

public static class WorkflowShortcutActions
{
    /// <summary>설정 표에 나오는 차례입니다 — macOS 와 같이 묶음 순, 묶음 안에서는 명령 순입니다.</summary>
    public static IReadOnlyList<WorkflowShortcutAction> All { get; } =
        [.. Enum.GetValues<WorkflowShortcutAction>()];

    public static WorkflowShortcutGroup Group(WorkflowShortcutAction action) => action switch
    {
        WorkflowShortcutAction.ImportImages or
        WorkflowShortcutAction.ImportFolder or
        WorkflowShortcutAction.RefreshLibrary => WorkflowShortcutGroup.Library,

        WorkflowShortcutAction.PreviousPhoto or
        WorkflowShortcutAction.NextPhoto or
        WorkflowShortcutAction.PickPhoto or
        WorkflowShortcutAction.ClearPick or
        WorkflowShortcutAction.RejectPhoto or
        WorkflowShortcutAction.DeletePhoto or
        WorkflowShortcutAction.RateZero or
        WorkflowShortcutAction.RateOne or
        WorkflowShortcutAction.RateTwo or
        WorkflowShortcutAction.RateThree or
        WorkflowShortcutAction.RateFour or
        WorkflowShortcutAction.RateFive => WorkflowShortcutGroup.Photo,

        WorkflowShortcutAction.ShowHideSidebar or
        WorkflowShortcutAction.ShowHideFilmstrip or
        WorkflowShortcutAction.ShowHideInspector or
        WorkflowShortcutAction.OpenLibraryWorkspace or
        WorkflowShortcutAction.OpenDevelopWorkspace or
        WorkflowShortcutAction.ToggleBeforeAfter => WorkflowShortcutGroup.View,

        WorkflowShortcutAction.DetectScanners or
        WorkflowShortcutAction.PreviewScan or
        WorkflowShortcutAction.ScanFrame => WorkflowShortcutGroup.Scanner,

        WorkflowShortcutAction.QuickExport or
        WorkflowShortcutAction.ExportPhoto => WorkflowShortcutGroup.Export,

        _ => WorkflowShortcutGroup.Develop,
    };

    /// <summary>
    /// macOS <c>defaultShortcut</c> 과 **같은 키**입니다. macOS 의 command 는 Windows 의
    /// Control 로, option 은 Alt 로 옮깁니다.
    /// </summary>
    public static WorkflowShortcut Default(WorkflowShortcutAction action) => action switch
    {
        WorkflowShortcutAction.ImportImages => new("i", WorkflowShortcutModifiers.Control),
        WorkflowShortcutAction.ImportFolder =>
            new("i", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.RefreshLibrary => new("r", WorkflowShortcutModifiers.Control),
        WorkflowShortcutAction.PreviousPhoto => new("[", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.NextPhoto => new("]", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.PickPhoto => new("p", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.ClearPick => new("u", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.RejectPhoto => new("x", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.DeletePhoto => new("delete", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.RateZero => new("0", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.RateOne => new("1", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.RateTwo => new("2", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.RateThree => new("3", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.RateFour => new("4", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.RateFive => new("5", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.ResetAdjustments =>
            new("r", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.CopyDevelopSettings =>
            new("c", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.PasteDevelopSettings =>
            new("v", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift),
        // macOS 는 여기에 control+shift 를 씁니다. Windows 에는 command 가 없어 그 자리를
        // Control 이 이미 쓰므로 alt+shift 로 옮깁니다.
        WorkflowShortcutAction.ProcessColorNegative =>
            new("1", WorkflowShortcutModifiers.Alt | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.ProcessColorPositive =>
            new("2", WorkflowShortcutModifiers.Alt | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.ProcessBwNegative =>
            new("3", WorkflowShortcutModifiers.Alt | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.ProcessBwPositive =>
            new("4", WorkflowShortcutModifiers.Alt | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.RotateLeft =>
            new("[", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.RotateRight =>
            new("]", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.FlipHorizontal =>
            new("h", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt),
        WorkflowShortcutAction.FlipVertical =>
            new("v", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt),
        WorkflowShortcutAction.ToggleBeforeAfter => new("\\", WorkflowShortcutModifiers.None),
        WorkflowShortcutAction.ShowHideSidebar =>
            new("1", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt),
        WorkflowShortcutAction.ShowHideFilmstrip =>
            new("2", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt),
        WorkflowShortcutAction.ShowHideInspector =>
            new("3", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt),
        WorkflowShortcutAction.OpenLibraryWorkspace =>
            new("4", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt),
        WorkflowShortcutAction.OpenDevelopWorkspace =>
            new("5", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt),
        WorkflowShortcutAction.DetectScanners =>
            new("d", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift),
        WorkflowShortcutAction.PreviewScan =>
            new("p", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt),
        WorkflowShortcutAction.ScanFrame =>
            new("s", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt),
        WorkflowShortcutAction.QuickExport => new("e", WorkflowShortcutModifiers.Control),
        WorkflowShortcutAction.ExportPhoto =>
            new("e", WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift),
        _ => WorkflowShortcut.None,
    };

    /// <summary>별점 키가 부르는 명령입니다.</summary>
    public static WorkflowShortcutAction Rating(int value) => value switch
    {
        1 => WorkflowShortcutAction.RateOne,
        2 => WorkflowShortcutAction.RateTwo,
        3 => WorkflowShortcutAction.RateThree,
        4 => WorkflowShortcutAction.RateFour,
        5 => WorkflowShortcutAction.RateFive,
        _ => WorkflowShortcutAction.RateZero,
    };
}
