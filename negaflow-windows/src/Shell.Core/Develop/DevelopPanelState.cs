using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>
/// Develop 패널이 들고 있는 것 전부입니다. XAML 코드비하인드가 아니라 여기 두어야 슬라이더의
/// clamp 와 결과 문구가 UI 없이 시험됩니다.
/// </summary>
public sealed class DevelopPanelState
{
    private readonly LibraryHostService host;
    private readonly DevelopBaseEditor baseEditor;
    private readonly DevelopColorEditor colorEditor;
    private readonly DevelopDefectEditor defectEditor;
    private readonly DevelopEffectsEditor effectsEditor;
    private readonly DevelopExportController exports;
    private readonly DevelopRouteEditor routeEditor;
    private readonly DevelopToneEditor toneEditor;
    private readonly DevelopTransformEditor transformEditor;
    private readonly DevelopVersionPresetController versionPresets;

    public DevelopPanelState(
        LibraryHostService host,
        ToneLimits limits,
        NegativeLimits negativeLimits)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(limits);
        ArgumentNullException.ThrowIfNull(negativeLimits);
        this.host = host;
        baseEditor = new DevelopBaseEditor(host, negativeLimits);
        colorEditor = new DevelopColorEditor(host);
        defectEditor = new DevelopDefectEditor(host);
        effectsEditor = new DevelopEffectsEditor(host);
        exports = new DevelopExportController(host);
        routeEditor = new DevelopRouteEditor(host);
        toneEditor = new DevelopToneEditor(host, limits);
        transformEditor = new DevelopTransformEditor(host);
        versionPresets = new DevelopVersionPresetController(host);
        Tone = new DevelopTonePanel(this, toneEditor);
        Color = new DevelopColorPanel(this, colorEditor);
        DefectLayers = new DevelopDefectLayerPanel(this, defectEditor);
    }

    /// <summary>
    /// 적용된 결함 제거를 항목별로 다루는 표면입니다. 획을 새로 긋는 것과 다른 이유로
    /// 바뀝니다 — macOS 도 Defect Layer 패널을 따로 둡니다.
    /// </summary>
    public DevelopDefectLayerPanel DefectLayers { get; }

    public double MinimumManualDmin => baseEditor.MinimumManualDmin;

    public double MaximumManualDmin => baseEditor.MaximumManualDmin;

    /// <summary>
    /// 아직 수동 base 를 고르지 않은 frame 의 슬라이더 시작 위치입니다. **이 값이 catalog 에 저장되지는
    /// 않습니다.** Auto 모드의 preview/export는 이 값이 아니라 native resolver를 사용합니다.
    /// </summary>
    public double SuggestedManualDmin => baseEditor.SuggestedManualDmin;

    public ManualBaseRgb? ManualBase => SelectedFrame?.ManualBase;

    public BaseEstimationMode BaseMode => SelectedFrame?.Base.Mode ?? BaseEstimationMode.Auto;

    public bool CanEditBase => DevelopBaseEditor.CanEdit(SelectedFrame);

    public bool CanEditTone => Tone.CanEdit;

    public LibraryFrameError SetBaseMode(BaseEstimationMode mode)
    {
        return RefreshAfterEdit(baseEditor.SetMode(SelectedFrame, mode));
    }

    public LibraryFrameError SetFilmStock(string? filmStockDminId)
    {
        return RefreshAfterEdit(baseEditor.SetFilmStock(SelectedFrame, filmStockDminId));
    }

    public LibraryFrameError SetLightSourceProfile(string? lightSourceProfileId)
    {
        return RefreshAfterEdit(
            baseEditor.SetLightSource(SelectedFrame, lightSourceProfileId));
    }

    /// <summary>
    /// 스캐너 프로파일을 고릅니다. 이 값이 붙어야 native 가 NORITSU·SP-3000 의 톤·색·질감
    /// 성격을 얹습니다 — 고르지 않으면 그 단계는 통째로 건너뜁니다.
    /// </summary>
    public LibraryFrameError SetScannerProfile(string? scannerProfileId)
    {
        return RefreshAfterEdit(
            baseEditor.SetScannerProfile(SelectedFrame, scannerProfileId));
    }

    /// <summary>
    /// 수동 필름 base 를 설정합니다. 범위는 엔진이 알려 준 것이며, 엔진은 벗어난 값을 거부하지
    /// 않고 조용히 clamp 하므로 여기서 먼저 묶어 저장된 값과 쓰인 값이 같게 합니다.
    /// </summary>
    public LibraryFrameError SetManualBase(double red, double green, double blue)
    {
        return RefreshAfterEdit(baseEditor.SetManualBase(SelectedFrame, red, green, blue));
    }

    public LibraryFrameSnapshot? SelectedFrame { get; private set; }

    /// <summary>기본 톤과 톤 커브의 조작 표면입니다.</summary>
    public DevelopTonePanel Tone { get; }

    /// <summary>포인트 커브·믹서·그레이딩·색상 다섯 축·원색 캘리브레이션·흑백 토닝입니다.</summary>
    public DevelopColorPanel Color { get; }

    public TextureRecipe Texture => SelectedFrame?.Texture ?? TextureRecipe.Identity;

    public NoiseReductionRecipe NoiseReduction =>
        SelectedFrame?.NoiseReduction ?? NoiseReductionRecipe.Identity;

    public ImageTransformRecipe ImageTransform =>
        SelectedFrame?.ImageTransform ?? ImageTransformRecipe.Identity;

    public bool CanExport => SelectedFrame is { CanDevelop: true } && !host.IsExporting;

    public bool Select(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        foreach (LibraryFrameSnapshot frame in host.Frames)
        {
            if (string.Equals(frame.Id, frameId, StringComparison.Ordinal))
            {
                SelectedFrame = frame;
                return true;
            }
        }
        SelectedFrame = null;
        return false;
    }
    /// <summary>
    /// macOS GrainMend 브러시의 기본 굵기입니다. 짧은 변에 대한 비율입니다.
    /// </summary>
    public const double DefaultBrushThickness = 0.01;

    /// <summary>macOS 복제 도장의 기본 지름입니다. 원본 raw 화소 단위입니다.</summary>
    public const double DefaultCloneDiameterPixels = 48.0;

    public const double MinimumCloneDiameterPixels = 4.0;

    public const double MaximumCloneDiameterPixels = 512.0;

    /// <summary>
    /// 캔버스에서 그은 치유 브러시 획 하나를 남깁니다. 점은 <b>표시 좌표</b>로 받고 여기서
    /// 원본 좌표로 되돌립니다 — 호출부가 좌표계를 알 필요가 없어야 어긋날 자리가 줄어듭니다.
    /// </summary>
    public LibraryFrameError AddBrushStroke(
        IReadOnlyList<DefectPoint> displayPoints,
        double thickness = DefaultBrushThickness)
    {
        DevelopDefectEditResult result = defectEditor.AddBrushStroke(
            SelectedFrame,
            displayPoints,
            thickness);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>
    /// 복제 도장 획 하나입니다. 원본 점은 표시 좌표로 받으며, 변위는 원본 공간에서 계산합니다 —
    /// 표시 공간에서 뺀 변위는 회전·수평보정이 걸린 프레임에서 방향이 틀어집니다.
    /// </summary>
    public LibraryFrameError AddCloneStroke(
        IReadOnlyList<DefectPoint> displayPoints,
        DefectPoint displaySourceAnchor,
        double diameter = DefaultCloneDiameterPixels) =>
        AddCloneStroke(
            displayPoints,
            displaySourceAnchor,
            alignedRawOffset: null,
            out _,
            diameter,
            DefectStrokeRecipeBuilder.DefaultCloneHardness);

    /// <summary>
    /// 첫 획에서 확정한 원본 공간 오프셋을 이후 획에도 그대로 씁니다. macOS 복제 도장은
    /// 소스가 브러시를 따라 움직이므로, 새 획의 시작점마다 소스 앵커와의 변위를 다시 계산하면
    /// 복제 위치가 튑니다.
    /// </summary>
    public LibraryFrameError AddCloneStroke(
        IReadOnlyList<DefectPoint> displayPoints,
        DefectPoint displaySourceAnchor,
        DefectPoint? alignedRawOffset,
        out DefectPoint usedRawOffset,
        double diameter = DefaultCloneDiameterPixels,
        double hardness = DefectStrokeRecipeBuilder.DefaultCloneHardness)
    {
        DevelopDefectEditResult result = defectEditor.AddCloneStroke(
            SelectedFrame,
            displayPoints,
            displaySourceAnchor,
            alignedRawOffset,
            out usedRawOffset,
            diameter,
            hardness,
            MinimumCloneDiameterPixels,
            MaximumCloneDiameterPixels);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>
    /// 검토를 마친 검출 결과를 recipe 에 담습니다. 자동·가이드는 이 호출 전까지 사진을
    /// 바꾸지 않습니다 — macOS 와 같은 상태 전환입니다.
    /// </summary>
    public LibraryFrameError AcceptDefectRegion(DefectEditItem edit)
    {
        DevelopDefectEditResult result = defectEditor.AcceptRegion(SelectedFrame, edit);
        return RefreshAfterDefectEdit(result);
    }

    public bool HasDefectEdits(DefectEditKind kind) =>
        DevelopDefectEditor.HasEdits(SelectedFrame, kind);

    public bool HasDefectEdits(DefectEditLabelKind label) =>
        DevelopDefectEditor.HasEdits(SelectedFrame, label);

    /// <summary>
    /// 한 도구가 남긴 편집만 지웁니다. 다른 도구의 편집과 자동 검출 결과는 남습니다 — macOS 의
    /// 도구별 초기화와 같습니다.
    /// </summary>
    public LibraryFrameError RemoveDefectEdits(DefectEditKind kind)
    {
        DevelopDefectEditResult result = defectEditor.RemoveEdits(SelectedFrame, kind);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>Resets just one visible GrainMend tool without discarding its siblings.</summary>
    public LibraryFrameError RemoveDefectEdits(DefectEditLabelKind label)
    {
        DevelopDefectEditResult result = defectEditor.RemoveEdits(SelectedFrame, label);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>
    /// Maps a display-space, top-first normalized rectangle to the smallest axis-aligned
    /// raw rectangle that contains all four inverse-transformed corners. Region defect
    /// recipes are raw-space data, so persisting the display rectangle directly would
    /// repair the wrong pixels after rotation, crop, or straighten.
    /// </summary>
    public bool TryMapDisplayRectToRaw(DefectRect displayRect, out DefectRect rawRect)
    {
        return DevelopDefectEditor.TryMapDisplayRectToRaw(
            SelectedFrame,
            displayRect,
            out rawRect);
    }

    internal LibraryFrameError RefreshAfterDefectEdit(DevelopDefectEditResult result)
    {
        if (result.Changed && SelectedFrame is { } frame)
        {
            Select(frame.Id);
        }
        return result.Error;
    }

    /// <summary>
    /// 실제로 바뀐 뒤에만 다시 고릅니다. 이 규칙은 여기 한 곳에만 있고, 도메인별 하위 표면도
    /// 이것을 거쳐야 합니다 — 두 벌이 되면 한쪽만 고쳐질 때 화면이 옛 값을 붙듭니다.
    /// </summary>
    internal LibraryFrameError RefreshAfterEdit(DevelopEditResult result)
    {
        if (result.Changed && SelectedFrame is { } frame)
        {
            Select(frame.Id);
        }
        return result.Error;
    }

    public LibraryFrameError ResetDetailAndEffects()
    {
        return RefreshAfterEdit(effectsEditor.Reset(SelectedFrame));
    }

    public LibraryFrameError SetTexture(TextureRecipe texture)
    {
        return RefreshAfterEdit(effectsEditor.SetTexture(SelectedFrame, texture));
    }

    public LibraryFrameError SetNoiseReduction(NoiseReductionRecipe noiseReduction)
    {
        return RefreshAfterEdit(
            effectsEditor.SetNoiseReduction(SelectedFrame, noiseReduction));
    }

    public LibraryFrameError SetNoiseReductionEnabled(bool enabled) =>
        SetNoiseReduction(NoiseReduction with { Strength = enabled ? 0.7 : 0.0 });

    public LibraryFrameError Rotate(bool clockwise)
    {
        return RefreshAfterEdit(transformEditor.Rotate(SelectedFrame, clockwise));
    }

    public LibraryFrameError FlipHorizontally() =>
        RefreshAfterEdit(transformEditor.FlipHorizontally(SelectedFrame));

    public LibraryFrameError FlipVertically() =>
        RefreshAfterEdit(transformEditor.FlipVertically(SelectedFrame));

    /// <summary>
    /// 반전 직후에 걸리는 opt-in Auto Levels 입니다. macOS 는 음화 route 에서만 이 토글을
    /// 내놓으므로, 양화에서 켜지지 않도록 여기서 막습니다.
    /// </summary>
    public LibraryFrameError SetAutoLevels(bool enabled) =>
        RefreshAfterEdit(routeEditor.SetAutoLevels(SelectedFrame, enabled));

    /// <summary>Auto Neutral Balance 입니다. macOS 의 "자동 색상" 토글과 같은 자리입니다.</summary>
    public LibraryFrameError SetAutoNeutralBalance(bool enabled) =>
        RefreshAfterEdit(routeEditor.SetAutoNeutralBalance(SelectedFrame, enabled));

    /// <summary>
    /// 지금 프레임의 현상 프로세스입니다. macOS <c>DevelopmentProcess(filmType:isDigitalSource:)</c>
    /// 와 같은 유도입니다 — 디지털 표시는 포지티브 경로에만 있고, 음화에 그 표시가 남아 있으면
    /// 필름으로 읽습니다.
    /// </summary>
    public DevelopmentProcess DevelopmentProcess =>
        DevelopRouteEditor.DevelopmentProcess(SelectedFrame);

    /// <summary>
    /// 현상 프로세스를 바꿉니다. 필름 룩과 세기는 그대로 두고 route 만 옮깁니다 — 프로세스를
    /// 바꿨다고 고른 필름이 사라지면 사용자가 다시 고르게 됩니다.
    /// </summary>
    public LibraryFrameError SetDevelopmentProcess(DevelopmentProcess process)
    {
        return RefreshAfterEdit(
            routeEditor.SetDevelopmentProcess(SelectedFrame, process));
    }

    /// <summary>이 frame 에 담긴 현상 버전입니다. 최근에 담은 것이 뒤에 옵니다.</summary>
    public IReadOnlyList<LibraryVersionSnapshot> Versions =>
        SelectedFrame?.Versions ?? [];

    /// <summary>
    /// 지금 recipe 를 이름 붙여 담습니다. macOS 처럼 현재 상태는 그대로 두고 목록에만 더합니다 —
    /// 담는 것이 되돌리는 것을 뜻하지는 않습니다.
    /// </summary>
    public LibraryFrameError CaptureVersion(string name) =>
        RefreshAfterEdit(versionPresets.CaptureVersion(SelectedFrame, name));

    /// <summary>담아 둔 버전의 recipe 로 되돌립니다. 버전 목록은 남습니다.</summary>
    public LibraryFrameError RestoreVersion(string versionId) =>
        RefreshAfterEdit(versionPresets.RestoreVersion(SelectedFrame, versionId));

    public LibraryFrameError DeleteVersion(string versionId) =>
        RefreshAfterEdit(versionPresets.DeleteVersion(SelectedFrame, versionId));

    /// <summary>
    /// 적어 둔 메타데이터를 바꿉니다. 레시피가 아니므로 미리보기를 다시 돌리지 않습니다 —
    /// 제목을 적었다고 사진이 다시 현상될 이유가 없습니다.
    /// </summary>
    public LibraryFrameError SetAppMetadata(
        Func<AppMetadataOverlay, AppMetadataOverlay> update)
    {
        return RefreshAfterEdit(versionPresets.SetAppMetadata(SelectedFrame, update));
    }

    /// <summary>
    /// 복사해 둔 현상 설정입니다. macOS 처럼 앱이 사는 동안만 남고 저장되지 않습니다 — 클립보드에
    /// 가까운 물건이지 카탈로그의 일부가 아닙니다.
    /// </summary>
    public LibraryFrameSnapshot? CopiedSettings => versionPresets.CopiedSettings;

    public string? CopiedSettingsSourceName => versionPresets.CopiedSettingsSourceName;

    /// <summary>
    /// macOS 의 붙여넣기 범위입니다. 한 번 정하면 다음 붙여넣기에도 그대로 쓰입니다.
    /// </summary>
    public DevelopSettingsPasteScope PasteScope
    {
        get => versionPresets.PasteScope;
        set => versionPresets.PasteScope = value;
    }

    public IReadOnlyList<DevelopUserPreset> UserPresets => versionPresets.UserPresets;

    /// <summary>지금 프레임의 현상 설정을 복사해 둡니다.</summary>
    public bool CopyDevelopSettings()
    {
        return versionPresets.CopyDevelopSettings(SelectedFrame);
    }

    /// <summary>
    /// 복사해 둔 설정을 지금 프레임에 <see cref="PasteScope"/> 만큼 붙입니다. 복사한 것이 없거나
    /// 범위가 비어 있으면 아무것도 하지 않습니다.
    /// </summary>
    public LibraryFrameError PasteDevelopSettings()
    {
        return RefreshAfterEdit(versionPresets.PasteDevelopSettings(SelectedFrame));
    }

    /// <summary>
    /// 사용자 프리셋 목록을 이 파일에서 읽고, 이후 저장·삭제도 여기에 씁니다. 경로를 주지 않으면
    /// 목록 기능이 그냥 비어 있습니다 — 셸이 저장소를 열지 못한 경우입니다.
    /// </summary>
    public void OpenUserPresets(string? path)
    {
        versionPresets.OpenUserPresets(path);
    }

    /// <summary>지금 프레임의 현상 설정을 이름 붙여 프리셋으로 저장합니다.</summary>
    public DevelopUserPreset? SaveUserPreset(string name)
    {
        return versionPresets.SaveUserPreset(SelectedFrame, name);
    }

    public LibraryFrameError ApplyUserPreset(Guid id)
    {
        return RefreshAfterEdit(versionPresets.ApplyUserPreset(SelectedFrame, id));
    }

    public bool DeleteUserPreset(Guid id)
    {
        return versionPresets.DeleteUserPreset(id);
    }

    public FilmEmulation FilmEmulation => SelectedFrame?.Route.FilmEmulation ?? FilmEmulation.None;

    public double FilmEmulationIntensity => SelectedFrame?.Route.FilmEmulationIntensity ?? 0.5;

    /// <summary>
    /// macOS 는 필름 룩을 digital source 에서만 적용합니다. 스캔 프레임에서는 고르는 자리
    /// 대신 그 안내를 냅니다.
    /// </summary>
    public bool AppliesFilmLook => DevelopRouteEditor.AppliesFilmLook(SelectedFrame);

    /// <summary>필름 룩을 고릅니다. <c>None</c> 이면 룩을 끕니다.</summary>
    public LibraryFrameError SetFilmEmulation(FilmEmulation emulation) =>
        RefreshAfterEdit(routeEditor.SetFilmEmulation(SelectedFrame, emulation));

    /// <summary>룩의 세기입니다. macOS 와 같이 0...1 로 자릅니다.</summary>
    public LibraryFrameError SetFilmEmulationIntensity(double intensity) =>
        RefreshAfterEdit(routeEditor.SetFilmEmulationIntensity(SelectedFrame, intensity));

    /// <summary>macOS 와 같이 음화 route 에서만 자동 보정 토글을 보여 줍니다.</summary>
    public bool ShowsAutoCorrections =>
        DevelopRouteEditor.ShowsAutoCorrections(SelectedFrame);

    public bool AutoLevels => SelectedFrame?.AutoLevels ?? false;

    public bool AutoNeutralBalance => SelectedFrame?.AutoNeutralBalance ?? false;

    public LibraryFrameError SetStraightenAngle(double angle) =>
        RefreshAfterEdit(transformEditor.SetStraightenAngle(SelectedFrame, angle));

    /// <summary>
    /// Canvas crop session의 단일 commit 지점입니다. null은 전체 프레임을 뜻하며, drag 중에는
    /// 이 메서드를 호출하지 않아 preview/export와 catalog가 중간 선택 상태를 보지 않습니다.
    /// </summary>
    public LibraryFrameError SetCrop(ImageCropRect? crop) =>
        RefreshAfterEdit(transformEditor.SetCrop(SelectedFrame, crop));

    /// <summary>
    /// 종횡비를 고릅니다. 원본은 비율과 crop 을 함께 지우고, 고정 비율은 그 비율로 가운데
    /// 정렬된 최대 crop 을 만듭니다 — macOS <c>applyCropAspect</c> 와 같습니다.
    /// </summary>
    public LibraryFrameError SetCropAspect(CropAspectOption option) =>
        RefreshAfterEdit(transformEditor.SetCropAspect(SelectedFrame, option));

    public CatalogStoreError Save() => exports.Save();

    public Task<bool> ExportAsync(
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted,
        ExportEncodingOptions? encoding = null)
    {
        return exports.ExportAsync(
            SelectedFrame,
            destinationPath,
            format,
            onCompleted,
            encoding);
    }

    /// <summary>
    /// 결과를 사용자에게 보여 줄 한 줄로 만듭니다. 실패는 어느 단계에서 왜 멈췄는지를 남깁니다 —
    /// "Export failed" 만 보여 주면 스캔을 다시 하는 것 말고 할 수 있는 일이 없습니다.
    /// </summary>
    public static string Describe(DevelopExportOutcome outcome)
    {
        return DevelopExportOutcomePresenter.Describe(outcome);
    }
}
