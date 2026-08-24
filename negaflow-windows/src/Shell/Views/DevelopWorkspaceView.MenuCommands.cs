using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 메뉴막대와 단축키가 부르는 현상 명령입니다.
/// </summary>
/// <remarks>
/// macOS 는 <c>DevelopCommands</c> 메뉴 항목 하나가 <c>AppModel</c> 함수 하나를 부릅니다.
/// 여기가 그 대응표이며, 인스펙터 컨트롤을 직접 누르는 것과 <b>같은 길</b>을 타야 화면과
/// 메뉴가 갈라지지 않습니다.
/// </remarks>
public sealed partial class DevelopWorkspaceView
{
    internal void RunAutoToneFromMenu() => autoAdjust.RunToneFromMenu();

    internal void RunAutoWhiteBalanceFromMenu() => autoAdjust.RunWhiteBalanceFromMenu();

    internal void ToggleAutoColorFromMenu()
    {
        if (panel is null)
        {
            return;
        }
        UpdateImageTransform(state => state.SetAutoNeutralBalance(!state.AutoNeutralBalance));
    }

    internal void ToggleAutoLevelsFromMenu()
    {
        if (panel is null)
        {
            return;
        }
        UpdateImageTransform(state => state.SetAutoLevels(!state.AutoLevels));
    }

    internal void ToggleNoiseReductionFromMenu()
    {
        if (panel is null)
        {
            return;
        }
        UpdateImageTransform(state =>
            state.SetNoiseReductionEnabled(state.NoiseReduction.Strength <= 1e-3));
    }

    internal void ToggleCropFromMenu()
    {
        inspectorChrome.SelectTab(DevelopInspectorTab.Edit);
        cropSession.ToggleFromMenu();
    }

    internal void ToggleBasePickerFromMenu()
    {
        inspectorChrome.SelectTab(DevelopInspectorTab.Base);
        BaseCard.ToggleBasePickerFromMenu();
    }

    /// <summary>
    /// macOS <c>handleDevelopToolShortcutRequest</c> 의 <c>.autoDefectTool</c>. 결함 도구는
    /// 결함 탭이 보일 때만 캔버스를 잡으므로(<c>DevelopGrainMendPanel.Apply</c>) 탭부터 엽니다.
    /// </summary>
    internal void RunAutoDefectFromMenu()
    {
        inspectorChrome.SelectTab(DevelopInspectorTab.Defects);
        // 칩을 누른 것과 같은 async void 길입니다 — 검출기가 자기 오류를 상태줄로 냅니다.
        _ = GrainMendPanel.RunAutoDefectAsync();
    }

    /// <summary>macOS <c>.guidedDefectTool</c>.</summary>
    internal void ToggleGuidedDefectFromMenu()
    {
        inspectorChrome.SelectTab(DevelopInspectorTab.Defects);
        GrainMendPanel.ToggleGuidedDefect();
    }

    /// <summary>macOS <c>.brushDefectTool</c>.</summary>
    internal void ToggleBrushDefectFromMenu()
    {
        inspectorChrome.SelectTab(DevelopInspectorTab.Defects);
        GrainMendPanel.ToggleBrushDefect();
    }

    /// <summary>macOS <c>.cloneStampTool</c>.</summary>
    internal void ToggleCloneStampFromMenu()
    {
        inspectorChrome.SelectTab(DevelopInspectorTab.Defects);
        GrainMendPanel.ToggleCloneStamp();
    }

    /// <summary>macOS <c>copyDevelopSettings</c> — 프리셋 패널과 같은 클립보드입니다.</summary>
    internal void ToggleBeforeAfterFromMenu()
    {
        if (panel is null)
        {
            return;
        }

        panel.ToggleBeforeAfter();
        OnCompareModeChosen(panel.Compare.Mode);
    }

    /// <summary>
    /// macOS <c>resetAllDevelopAdjustments</c> 뒤에는 <c>scheduleRedevelop</c> 이 옵니다.
    /// 값만 지우고 화면을 그대로 두면 사용자는 초기화가 안 된 줄 압니다.
    /// </summary>
    internal void ResetAllAdjustmentsFromMenu()
    {
        if (panel is null || panel.ResetAllAdjustments() != LibraryFrameError.None)
        {
            return;
        }

        SynchronizeInspectorValues();
        SyncToneControls();
        RequestPreview();
    }

    internal void CopyDevelopSettingsFromMenu() => _ = panel?.CopyDevelopSettings();

    internal bool CreateVirtualCopyFromMenu() => panel?.CreateVirtualCopy() == true;

    /// <summary>macOS <c>pasteDevelopSettings</c> — 고른 사진이 없으면 조용히 끝납니다.</summary>
    internal void PasteDevelopSettingsFromMenu()
    {
        if (panel is not null)
        {
            _ = panel.PasteDevelopSettings();
        }
    }

    /// <summary>
    /// 고른 프로파일의 용지 흰색과 잉크 검정을 미리보기에 겁니다.
    /// </summary>
    /// <remarks>
    /// 목적지는 현상 대상이 정합니다 — PRINT 로 현상할 때는 프린터 출력 프로파일이 목적지이며,
    /// 그래야 프루프가 화면이 아니라 인화될 종이를 보여 줍니다. 프로파일을 읽지 못하면 용지·
    /// 잉크를 흉내 내지 않습니다: 없는 값을 지어내느니 프로파일만 보는 쪽이 정직합니다.
    /// </remarks>
    internal void ApplySoftProof()
    {
        if (previewCoordinator is not { } coordinator)
        {
            return;
        }
        DevelopTarget target = panel?.SelectedFrame?.DevelopTarget ?? DevelopTarget.Main;
        coordinator.SoftProof = softProofPreferences.ToSettings(
            SoftProofProfileReader.Read(softProofPreferences.DestinationProfilePath(target)));
        RequestPreview();
    }
}
