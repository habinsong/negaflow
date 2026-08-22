using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

public sealed class WorkspacePresentationState
{
    private readonly PresentationSettingsStore settingsStore;

    public WorkspacePresentationState(PresentationSettingsStore settingsStore)
    {
        this.settingsStore = settingsStore;
        settingsStore.Changed += OnSettingsChanged;
        ApplyDevelopPolicies(settingsStore.Current);
    }

    public event EventHandler<ShellPreferences>? Changed;

    /// <summary>
    /// 지금 붙어 있는 스캐너가 보고한 성능입니다. 설정 · 스캔의 "스캐너 정보" 가 이것을
    /// 읽습니다. 저장하지 않습니다 - 장치를 바꾸면 값도 바뀌어야 하고, 지난 실행의 값을
    /// 이번 장치의 사양으로 보여 주면 거짓말이 됩니다.
    /// </summary>
    public ScannerPluginCapabilities? ScannerCapabilities { get; private set; }

    /// <summary>스캐너 성능이 바뀌었습니다. 설정 창이 열려 있으면 다시 그립니다.</summary>
    public event EventHandler? ScannerCapabilitiesChanged;

    public void PublishScannerCapabilities(ScannerPluginCapabilities? capabilities)
    {
        if (Equals(ScannerCapabilities, capabilities))
        {
            return;
        }
        ScannerCapabilities = capabilities;
        ScannerCapabilitiesChanged?.Invoke(this, EventArgs.Empty);
    }

    public ShellPreferences Current => settingsStore.Current;

    public void SelectWorkspace(WorkspaceModule module) =>
        settingsStore.Update(value => value with { SelectedWorkspace = module });

    public void SetActiveFrame(string? frameId) =>
        settingsStore.Update(value => value with { ActiveFrameId = frameId });

    public void SelectDevelopSidebarTab(WorkflowSidebarTab tab) =>
        settingsStore.Update(value => value with { SelectedDevelopSidebarTab = tab });

    public void SetAppearance(AppearanceMode appearance) =>
        settingsStore.Update(value => value with { Appearance = appearance });

    public void SetImageContentHashMode(ImageContentHashMode mode) =>
        settingsStore.Update(value => value with { ImageContentHash = mode });

    public void SelectSettingsCategory(SettingsCategory category) =>
        settingsStore.Update(value => value with { SelectedSettingsCategory = category });

    public void ToggleSidebar() => settingsStore.Update(value => value with
    {
        IsSidebarVisible = !value.IsSidebarVisible,
    });

    public void ToggleInspector() => settingsStore.Update(value => value with
    {
        IsInspectorVisible = !value.IsInspectorVisible,
    });

    public void ToggleFilmstrip() => settingsStore.Update(value => value with
    {
        IsFilmstripVisible = !value.IsFilmstripVisible,
    });

    public void SetSidebarWidth(double width) =>
        settingsStore.Update(value => value with { SidebarWidth = width });

    public void SetInspectorWidth(double width) =>
        settingsStore.Update(value => value with { InspectorWidth = width });

    public void SetLibraryControlsWidth(double width) =>
        settingsStore.Update(value => value with { LibraryControlsWidth = width });

    public void SetFilmstripHeight(double height) =>
        settingsStore.Update(value => value with { FilmstripHeight = height });

    public void UpdateExport(Func<ExportSettings, ExportSettings> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { Export = update(value.Export) });
    }

    public void UpdateSoftProof(Func<SoftProofPreferences, SoftProofPreferences> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { SoftProof = update(value.SoftProof) });
    }

    public void UpdateExportRecipes(Func<ExportRecipeLibrary, ExportRecipeLibrary> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { ExportRecipes = update(value.ExportRecipes) });
    }

    public void UpdateShortcuts(
        Func<Shortcuts.WorkflowShortcutMap, Shortcuts.WorkflowShortcutMap> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { Shortcuts = update(value.Shortcuts) });
    }

    public void SetAutoDefectMicroSpecks(bool value) =>
        settingsStore.Update(current => current with { AutoDefectDetectsMicroSpecks = value });

    public void SetGuidedDefectMicroSpecks(bool value) =>
        settingsStore.Update(current => current with { GuidedDefectDetectsMicroSpecks = value });

    public void SetLanguage(string language) =>
        settingsStore.Update(current => current with { Language = language });

    /// <summary>저장 위치를 바꿉니다. 폴더는 <b>실제로 쓸 때</b> 만듭니다.</summary>
    public void UpdateDisk(
        Func<Storage.DiskStorageSettings, Storage.DiskStorageSettings> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(current => current with { Disk = update(current.Disk) });
    }

    public void SetCanvasBackground(Develop.CanvasBackgroundKind background) =>
        settingsStore.Update(value => value with { CanvasBackground = background });

    public void SetDevelopsImportsAutomatically(bool value) =>
        settingsStore.Update(current => current with { DevelopsImportsAutomatically = value });

    public void SetScannerSimulatorEnabled(bool value) =>
        settingsStore.Update(current => current with { ScannerSimulatorEnabled = value });

    /// <summary>백업 일정과 기록을 고칩니다.</summary>
    public void UpdateBackup(
        Func<Storage.LibraryBackupSettings, Storage.LibraryBackupSettings> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(current => current with { Backup = update(current.Backup) });
    }

    public void SetDeveloperMode(bool value) =>
        settingsStore.Update(value2 => value2 with { DeveloperMode = value });

    /// <summary>
    /// 상주 프레임 한도를 바꿉니다. 바뀐 값은 <see cref="ApplyDevelopPolicies"/> 가
    /// <c>ThumbnailService</c> 에 그대로 걸어 줍니다 — 저장만 하고 안 걸면 다음 실행까지
    /// 예전 한도로 돕니다.
    /// </summary>
    public void UpdateFrameCache(
        Func<Library.FrameCacheResidencySettings, Library.FrameCacheResidencySettings> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(current => current with { FrameCache = update(current.FrameCache) });
    }

    public void SetPixelSamplerEnabled(bool value) =>
        settingsStore.Update(current => current with { PixelSamplerEnabled = value });

    public void SetClippingOverlayEnabled(bool value) =>
        settingsStore.Update(current => current with { ClippingOverlayEnabled = value });

    public void SetDefaultScanRotation(Negaflow.Catalog.ImageRotation rotation) =>
        settingsStore.Update(current => current with { DefaultScanRotation = rotation });

    public void UpdatePrint(Func<Print.PrintPreferences, Print.PrintPreferences> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { Print = update(value.Print) });
    }

    public void UpdateQuickExport(Func<QuickExportSettings, QuickExportSettings> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { QuickExport = update(value.QuickExport) });
    }

    /// <summary>
    /// 설정 중 <b>현상 파이프라인이 읽는 것</b>을 여기서 한 번에 반영합니다.
    /// </summary>
    /// <remarks>
    /// <c>이미지 내용 해시</c> 는 오랫동안 <b>저장만 되고 아무도 읽지 않았습니다.</b>
    /// 기본값이 끔인데도 결함 편집이 걸린 사진은 렌더마다 원본 전체를 SHA-256 했습니다 —
    /// frame_1(104MB)에서 슬라이더 틱당 약 140ms 입니다. 설정을 실제로 따르게 하는 자리가
    /// 여기입니다.
    /// </remarks>
    /// <summary>
    /// 상주 프레임 한도를 실제 캐시에 거는 자리입니다. <c>ThumbnailService</c> 는 셸이 만드는
    /// 것이라 여기서 직접 잡을 수 없으므로, 만든 쪽(<c>App</c>)이 이 자리를 채웁니다.
    /// </summary>
    public static Action<Library.FrameCacheResidencySettings>? FrameCacheLimitsChanged { get; set; }

    /// <summary>마지막으로 적용한 개발자 모드입니다. 처음에는 모름(null)입니다.</summary>
    private static bool? lastAppliedDeveloperMode;

    private static void ApplyDevelopPolicies(ShellPreferences preferences)
    {
        DevelopRequestFactory.VerifyDefectSourceContent =
            preferences.ImageContentHash == ImageContentHashMode.Sha256;
        FrameCacheLimitsChanged?.Invoke(preferences.FrameCache);
        // 개발자 모드는 썸네일·미리보기·단축키 추적 기록을 켭니다. 표시 파일이 생기고
        // 다음 동작부터 %LOCALAPPDATA%\Negaflow\Logs 에 줄이 쌓입니다.
        // 값이 **바뀔 때만** 손댑니다. 시작할 때마다 지우면 손으로 놓아 둔 표시 파일이
        // 사라져 진단을 못 합니다.
        if (lastAppliedDeveloperMode != preferences.DeveloperMode)
        {
            lastAppliedDeveloperMode = preferences.DeveloperMode;
            Diagnostics.DiagnosticTraceSwitches.Apply(preferences.DeveloperMode);
        }
    }

    private void OnSettingsChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        ApplyDevelopPolicies(preferences);
        Changed?.Invoke(this, preferences);
    }
}
