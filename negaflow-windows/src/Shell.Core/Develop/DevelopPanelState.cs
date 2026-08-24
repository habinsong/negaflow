using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>
/// Develop 패널이 들고 있는 것 전부입니다. XAML 코드비하인드가 아니라 여기 두어야 슬라이더의
/// clamp 와 결과 문구가 UI 없이 시험됩니다.
/// </summary>
public sealed partial class DevelopPanelState
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
        InfraredClean = new DevelopInfraredCleanState(host);
        Compare = new CanvasCompareState();
        Viewport = new CanvasViewportState();
        Tone = new DevelopTonePanel(this, toneEditor);
        Color = new DevelopColorPanel(this, colorEditor);
        DefectLayers = new DevelopDefectLayerPanel(this, defectEditor, host.DefectLiveStrengths);
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

    /// <summary>
    /// macOS <c>ScanFrame.baseRGB</c> — 마지막 미리보기가 쓴 Dmin 입니다. 카탈로그
    /// <c>baseRGB</c> 에 남기고, 프레임을 고르면 그 값을 다시 읽습니다.
    /// </summary>
    public ManualBaseRgb? LastAppliedBase { get; private set; }

    public void RememberAppliedBase(float red, float green, float blue)
    {
        ManualBaseRgb rgb = new(red, green, blue);
        LastAppliedBase = rgb;
        if (SelectedFrame is not { } frame)
        {
            return;
        }
        if (host.EditFrameRecord(frame.Id, record => AppliedBaseWriter.Apply(record, rgb))
            != LibraryFrameError.None)
        {
            return;
        }
        foreach (LibraryFrameSnapshot updated in host.Frames)
        {
            if (string.Equals(updated.Id, frame.Id, StringComparison.Ordinal))
            {
                SelectedFrame = updated;
                LastAppliedBase = updated.AppliedBase ?? rgb;
                return;
            }
        }
    }

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

    public event Action<string?>? SelectedFrameChanged;

    public CanvasCompareState Compare { get; }

    /// <summary>macOS <c>CanvasView.viewport</c>.</summary>
    public CanvasViewportState Viewport { get; }

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

    /// <summary>
    /// 이 프레임을 고를 때 IR 결함 제거가 낸 결과입니다. macOS <c>statusMessage</c> 자리이며,
    /// 화면이 읽어 문구로 바꿉니다. IR 이 돌지 않았으면 <see cref="InfraredCleanMessage.None"/>
    /// 입니다.
    /// </summary>
    public DevelopInfraredCleanState InfraredClean { get; }

    public InfraredCleanStatus LastInfraredClean => InfraredClean.Status;

    public bool Select(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        DefectLayers.RetainFrames(host.Frames.Select(frame => frame.Id));
        string? priorFrameId = SelectedFrame?.Id;
        foreach (LibraryFrameSnapshot frame in host.Frames)
        {
            if (string.Equals(frame.Id, frameId, StringComparison.Ordinal))
            {
                SelectedFrame = frame;
                LastAppliedBase = frame.AppliedBase;
                InfraredClean.BindFrame(frame.Id);
                // macOS 는 `showDeveloped` 가 프레임 객체에 붙어 있어 프레임을 옮기면 그
                // 프레임의 비교 모드가 따라옵니다. 여기가 그 자리입니다.
                Compare.BindFrame(frame.Id);
                SelectedFrameChanged?.Invoke(frame.Id);
                return true;
            }
        }
        SelectedFrame = null;
        LastAppliedBase = null;
        InfraredClean.BindFrame(null);
        Compare.BindFrame(null);
        if (priorFrameId is not null)
        {
            SelectedFrameChanged?.Invoke(null);
        }
        return false;
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

    /// <summary>macOS <c>selectCompareMode</c>.</summary>
    public void SelectCompareMode(CanvasCompareMode mode)
    {
        if (SelectedFrame is { } frame)
        {
            Compare.DevelopTarget = frame.DevelopTarget;
        }

        Compare.Select(mode);
    }

    /// <summary>macOS <c>beforeContentRaw =</c>.</summary>
    public void SelectCompareBefore(string id, Func<string, bool>? frameExists = null) =>
        Compare.SelectBefore(id, frameExists);

    /// <summary>macOS <c>toggleDevelopedShortcut</c>.</summary>
    public void ToggleBeforeAfter()
    {
        if (SelectedFrame is { } frame)
        {
            Compare.DevelopTarget = frame.DevelopTarget;
        }

        Compare.ToggleDeveloped();
    }

    /// <summary>
    /// macOS <c>AppModel.resetAllDevelopAdjustments(frame:neutralPreset:)</c>. 호출부가
    /// 프리셋을 정하지 않으면 macOS 인스펙터와 같이 "neutral" 을 되돌려 놓습니다 — 앞서는
    /// 프리셋을 아예 지워서 macOS 와 다른 그림이 나왔습니다.
    /// </summary>
    public LibraryFrameError ResetAllAdjustments(string? neutralPresetId = null)
    {
        neutralPresetId ??= DevelopInspectorResetter.NeutralPresetId;
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }

        LibraryFrameEdit edit = DevelopInspectorResetter.ResetAllAdjustments(
            frame,
            neutralPresetId);
        LibraryFrameError error = host.EditUndoable(
            frame.Id,
            LibraryHostService.UndoActions.ResetAdjustments,
            edit);
        return RefreshAfterEdit(new DevelopEditResult(error, error == LibraryFrameError.None));
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

    /// <summary>macOS <c>resetPhotoAngle</c> — 회전과 수평 보정만 되돌립니다.</summary>
    public LibraryFrameError ResetPhotoAngle() =>
        RefreshAfterEdit(transformEditor.ResetPhotoAngle(SelectedFrame));

    /// <summary>
    /// macOS <c>canResetPhotoAngle</c> — 회전이 0 이 아니거나 수평 보정이 1e-4 이상일 때만
    /// 누를 수 있습니다(<c>DevelopWorkflowInspector.swift:246-248</c>).
    /// </summary>
    public bool CanResetPhotoAngle =>
        SelectedFrame is { } frame &&
        (frame.ImageTransform.Rotation != ImageRotation.Degrees0 ||
            Math.Abs(frame.ImageTransform.StraightenAngle) >= 1e-4);

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
}
