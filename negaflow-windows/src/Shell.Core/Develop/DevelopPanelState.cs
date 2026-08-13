using System.Globalization;
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
    private readonly ToneLimits limits;

    private readonly NegativeLimits negativeLimits;

    public DevelopPanelState(
        LibraryHostService host,
        ToneLimits limits,
        NegativeLimits negativeLimits)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(limits);
        ArgumentNullException.ThrowIfNull(negativeLimits);
        this.host = host;
        this.limits = limits;
        this.negativeLimits = negativeLimits;
    }

    public double MinimumManualDmin => negativeLimits.MinimumManualDmin;

    public double MaximumManualDmin => negativeLimits.MaximumManualDmin;

    /// <summary>
    /// 아직 수동 base 를 고르지 않은 frame 의 슬라이더 시작 위치입니다. **이 값이 catalog 에 저장되지는
    /// 않습니다.** Auto 모드의 preview/export는 이 값이 아니라 native resolver를 사용합니다.
    /// </summary>
    public double SuggestedManualDmin =>
        negativeLimits.ClampChannel((MinimumManualDmin + MaximumManualDmin) / 4.0);

    public ManualBaseRgb? ManualBase => SelectedFrame?.ManualBase;

    public BaseEstimationMode BaseMode => SelectedFrame?.Base.Mode ?? BaseEstimationMode.Auto;

    public bool CanEditBase => SelectedFrame?.Route.FilmType is FilmType.ColorNegative or FilmType.BlackAndWhiteNegative;

    public bool CanEditTone => SelectedFrame is not null;

    public LibraryFrameError SetBaseMode(BaseEstimationMode mode)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (mode is not (BaseEstimationMode.Auto or BaseEstimationMode.Preset or BaseEstimationMode.Manual))
        {
            return LibraryFrameError.InvalidBaseRecipe;
        }
        if (!CanEditBase)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        ManualBaseRgb? manualBase = frame.ManualBase;
        if (mode == BaseEstimationMode.Manual && manualBase is null)
        {
            manualBase = new ManualBaseRgb(
                negativeLimits.ClampChannel(0.90),
                negativeLimits.ClampChannel(0.65),
                negativeLimits.ClampChannel(0.45));
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, manualBase, frame.Base with { Mode = mode }));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameError SetFilmStock(string? filmStockDminId)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditBase)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }
        if (!BundledFilmBaseOptions.IsKnownFilmStock(filmStockDminId))
        {
            return LibraryFrameError.InvalidBaseRecipe;
        }

        BaseRecipe updated = frame.Base with
        {
            Mode = filmStockDminId is null ? BaseEstimationMode.Auto : BaseEstimationMode.Preset,
            FilmStockDminId = filmStockDminId,
        };
        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, updated));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameError SetLightSourceProfile(string? lightSourceProfileId)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditBase)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }
        if (frame.Base.Mode != BaseEstimationMode.Preset)
        {
            return LibraryFrameError.InvalidBaseRecipe;
        }
        if (!BundledFilmBaseOptions.IsKnownLightSource(lightSourceProfileId))
        {
            return LibraryFrameError.InvalidBaseRecipe;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                frame.Base with { LightSourceProfileId = lightSourceProfileId }));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>
    /// 수동 필름 base 를 설정합니다. 범위는 엔진이 알려 준 것이며, 엔진은 벗어난 값을 거부하지
    /// 않고 조용히 clamp 하므로 여기서 먼저 묶어 저장된 값과 쓰인 값이 같게 합니다.
    /// </summary>
    public LibraryFrameError SetManualBase(double red, double green, double blue)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditBase)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        ManualBaseRgb clamped = new(
            negativeLimits.ClampChannel(red),
            negativeLimits.ClampChannel(green),
            negativeLimits.ClampChannel(blue));
        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                clamped,
                frame.Base with { Mode = BaseEstimationMode.Manual }));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameSnapshot? SelectedFrame { get; private set; }

    public double MaximumExposureStops => limits.MaximumExposureStops;

    public double MaximumToneControl => limits.MaximumToneControl;

    public double Exposure => SelectedFrame?.Tone.Exposure ?? 0.0;

    public double Contrast => SelectedFrame?.Tone.Contrast ?? 0.0;

    public double Highlights => SelectedFrame?.Tone.Highlight ?? 0.0;

    public double Shadows => SelectedFrame?.Tone.Shadow ?? 0.0;

    public double Whites => SelectedFrame?.Tone.Whites ?? 0.0;

    public double Blacks => SelectedFrame?.Tone.Blacks ?? 0.0;

    public double Density => SelectedFrame?.Tone.Density ?? 0.0;

    public double CurveHighlights => SelectedFrame?.Tone.CurveHighlights ?? 0.0;

    public double CurveLights => SelectedFrame?.Tone.CurveLights ?? 0.0;

    public double CurveDarks => SelectedFrame?.Tone.CurveDarks ?? 0.0;

    public double CurveShadows => SelectedFrame?.Tone.CurveShadows ?? 0.0;

    public PointCurveRecipe PointCurves => SelectedFrame?.PointCurves ?? PointCurveRecipe.Identity;

    public ColorMixerRecipe ColorMixer => SelectedFrame?.ColorMixer ?? ColorMixerRecipe.Identity;

    public ColorGradingRecipe ColorGrading => SelectedFrame?.ColorGrading ?? ColorGradingRecipe.Identity;

    public PrimaryCalibrationRecipe PrimaryCalibration =>
        SelectedFrame?.PrimaryCalibration ?? PrimaryCalibrationRecipe.Identity;

    public TextureRecipe Texture => SelectedFrame?.Texture ?? TextureRecipe.Identity;

    public NoiseReductionRecipe NoiseReduction =>
        SelectedFrame?.NoiseReduction ?? NoiseReductionRecipe.Identity;

    public ImageTransformRecipe ImageTransform =>
        SelectedFrame?.ImageTransform ?? ImageTransformRecipe.Identity;

    public bool CanExport => SelectedFrame is { CanDevelop: true } && !host.IsExporting;

    public LibraryFrameError ApplyAutoTone(AutoAdjustSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return SelectedFrame is not { } frame
            ? LibraryFrameError.MissingId
            : ApplyAutoAdjusted(AutoAdjustCoordinator.ApplyTone(frame, settings));
    }

    public LibraryFrameError ApplyAutoWhiteBalance(AutoAdjustSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return SelectedFrame is not { } frame
            ? LibraryFrameError.MissingId
            : ApplyAutoAdjusted(AutoAdjustCoordinator.ApplyWhiteBalance(frame, settings));
    }

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
    /// 노출을 바꿉니다. 범위는 엔진이 알려 준 값이고, clamp 를 통과한 값은 엔진이 받습니다.
    /// 저장은 하지 않습니다 — <see cref="Save"/> 를 부르십시오.
    /// </summary>
    public LibraryFrameError SetExposure(double stops)
    {
        return SetTone(tone => tone with { Exposure = limits.ClampExposure(stops) });
    }

    public LibraryFrameError SetContrast(double value) =>
        SetTone(tone => tone with { Contrast = limits.ClampToneControl(value) });

    public LibraryFrameError SetHighlights(double value) =>
        SetTone(tone => tone with { Highlight = limits.ClampToneControl(value) });

    public LibraryFrameError SetShadows(double value) =>
        SetTone(tone => tone with { Shadow = limits.ClampToneControl(value) });

    public LibraryFrameError SetWhites(double value) =>
        SetTone(tone => tone with { Whites = limits.ClampToneControl(value) });

    public LibraryFrameError SetBlacks(double value) =>
        SetTone(tone => tone with { Blacks = limits.ClampToneControl(value) });

    public LibraryFrameError SetDensity(double value) =>
        SetTone(tone => tone with { Density = limits.ClampToneControl(value) });

    public LibraryFrameError SetCurveHighlights(double value) =>
        SetTone(tone => tone with { CurveHighlights = limits.ClampToneControl(value) });

    public LibraryFrameError SetCurveLights(double value) =>
        SetTone(tone => tone with { CurveLights = limits.ClampToneControl(value) });

    public LibraryFrameError SetCurveDarks(double value) =>
        SetTone(tone => tone with { CurveDarks = limits.ClampToneControl(value) });

    public LibraryFrameError SetCurveShadows(double value) =>
        SetTone(tone => tone with { CurveShadows = limits.ClampToneControl(value) });

    public LibraryFrameError ResetBasicTone() =>
        SetTone(tone => tone with
        {
            Exposure = 0,
            Contrast = 0,
            Density = 0,
            Highlight = 0,
            Shadow = 0,
            Whites = 0,
            Blacks = 0,
        });

    public LibraryFrameError ResetToneCurve()
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        ToneAdjustment tone = frame.Tone with
        {
            CurveHighlights = 0,
            CurveLights = 0,
            CurveDarks = 0,
            CurveShadows = 0,
        };
        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                tone,
                frame.ManualBase,
                PointCurves: PointCurveRecipe.Identity));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>
    /// 색상 섹션의 다섯 축만 0 으로 돌립니다. 같은 recipe 에 있는 원색 세 축은 이 섹션의 것이
    /// 아니므로 건드리지 않습니다.
    /// </summary>
    public LibraryFrameError ResetColor()
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                ColorModel: frame.ColorModel with
                {
                    Warmth = 0.0,
                    Tint = 0.0,
                    Vibrance = 0.0,
                    Saturation = 0.0,
                    ColorDepth = 0.0,
                }));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameError ResetColorMixer()
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                ColorMixer: ColorMixerRecipe.Identity));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameError ResetColorGrading()
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                ColorGrading: ColorGradingRecipe.Identity));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameError ResetPrimaryCalibration() =>
        SetPrimaryCalibration(PrimaryCalibrationRecipe.Identity);

    public LibraryFrameError ResetDetailAndEffects()
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                Texture: TextureRecipe.Identity,
                NoiseReduction: NoiseReductionRecipe.Identity));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>
    /// Point Curve는 Parametric Tone Curve와 별도 recipe로 저장합니다. Catalog writer가
    /// 좌표의 finite/range/중복 조건을 검증해 preview와 export가 같은 값만 받습니다.
    /// </summary>
    public LibraryFrameError SetPointCurves(PointCurveRecipe pointCurves)
    {
        ArgumentNullException.ThrowIfNull(pointCurves);
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, PointCurves: pointCurves));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>Color Mixer는 Tone과 별도 recipe로 저장되어 preview/export에 같은 값을 전달합니다.</summary>
    public LibraryFrameError SetColorMixer(ColorMixerRecipe colorMixer)
    {
        ArgumentNullException.ThrowIfNull(colorMixer);
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, ColorMixer: colorMixer));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>Color Grading은 Tone과 별도 recipe로 저장되어 preview/export에 같은 값을 전달합니다.</summary>
    public LibraryFrameError SetColorGrading(ColorGradingRecipe colorGrading)
    {
        ArgumentNullException.ThrowIfNull(colorGrading);
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, ColorGrading: colorGrading));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>
    /// macOS 색상 섹션의 다섯 축입니다. 원색 세 축은 이 섹션에 없으므로 그대로 둡니다.
    /// </summary>
    public ColorModelRecipe ColorModel => SelectedFrame?.ColorModel ?? ColorModelRecipe.Identity;

    public LibraryFrameError SetColorModel(ColorModelRecipe colorModel)
    {
        ArgumentNullException.ThrowIfNull(colorModel);
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, ColorModel: colorModel));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>
    /// macOS GrainMend 브러시의 기본 굵기입니다. 짧은 변에 대한 비율입니다.
    /// </summary>
    public const double DefaultBrushThickness = 0.01;

    /// <summary>
    /// 캔버스에서 그은 치유 브러시 획 하나를 남깁니다. 점은 <b>표시 좌표</b>로 받고 여기서
    /// 원본 좌표로 되돌립니다 — 호출부가 좌표계를 알 필요가 없어야 어긋날 자리가 줄어듭니다.
    /// </summary>
    public LibraryFrameError AddBrushStroke(
        IReadOnlyList<DefectPoint> displayPoints,
        double thickness = DefaultBrushThickness)
    {
        ArgumentNullException.ThrowIfNull(displayPoints);
        return AddStroke(
            displayPoints,
            (frameId, identity, existing, points, baseSize) =>
                DefectStrokeRecipeBuilder.AppendBrushStroke(
                    frameId, identity, existing, points, thickness, baseSize));
    }

    /// <summary>
    /// 복제 도장 획 하나입니다. 원본 점은 표시 좌표로 받으며, 변위는 원본 공간에서 계산합니다 —
    /// 표시 공간에서 뺀 변위는 회전·수평보정이 걸린 프레임에서 방향이 틀어집니다.
    /// </summary>
    public LibraryFrameError AddCloneStroke(
        IReadOnlyList<DefectPoint> displayPoints,
        DefectPoint displaySourceAnchor,
        double diameter = DefaultBrushThickness)
    {
        ArgumentNullException.ThrowIfNull(displayPoints);
        if (displayPoints.Count == 0 ||
            !TryMapToRaw(displayPoints[0], out DefectPoint firstTarget) ||
            !TryMapToRaw(displaySourceAnchor, out DefectPoint anchor))
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }
        double offsetX = anchor.X - firstTarget.X;
        double offsetY = anchor.Y - firstTarget.Y;
        return AddStroke(
            displayPoints,
            (frameId, identity, existing, points, baseSize) =>
                DefectStrokeRecipeBuilder.AppendCloneStroke(
                    frameId, identity, existing, points, diameter, offsetX, offsetY, baseSize));
    }

    private LibraryFrameError AddStroke(
        IReadOnlyList<DefectPoint> displayPoints,
        Func<Guid, DefectSourceIdentity, DefectRecipeSnapshot?, IReadOnlyList<DefectPoint>,
            DefectSize, DefectRecipeSnapshot?> build)
    {
        if (SelectedFrame is not { } frame ||
            !Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
            frame.SourceMetadata is not { } metadata ||
            metadata.PixelWidth == 0U || metadata.PixelHeight == 0U)
        {
            return LibraryFrameError.MissingId;
        }

        List<DefectPoint> rawPoints = new(displayPoints.Count);
        foreach (DefectPoint point in displayPoints)
        {
            if (TryMapToRaw(point, out DefectPoint raw))
            {
                rawPoints.Add(raw);
            }
        }
        if (rawPoints.Count == 0)
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }

        DefectSize baseSize = new(metadata.PixelWidth, metadata.PixelHeight);
        LibraryFrameError error = host.AppendDefectStroke(
            frame.Id,
            (identity, existing) =>
                build(frameId, identity, existing, rawPoints, baseSize));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public bool HasDefectEdits(DefectEditKind kind) =>
        SelectedFrame?.DefectRecipe?.Items.Any(item => item.Kind == kind) == true;

    /// <summary>
    /// 한 도구가 남긴 편집만 지웁니다. 다른 도구의 편집과 자동 검출 결과는 남습니다 — macOS 의
    /// 도구별 초기화와 같습니다.
    /// </summary>
    public LibraryFrameError RemoveDefectEdits(DefectEditKind kind)
    {
        if (SelectedFrame is not { } frame ||
            !Guid.TryParseExact(frame.Id, "D", out Guid frameId))
        {
            return LibraryFrameError.MissingId;
        }
        if (frame.DefectRecipe is not { } recipe ||
            recipe.Items.All(item => item.Kind != kind))
        {
            return LibraryFrameError.None;
        }

        DefectEditItem[] remaining = [.. recipe.Items.Where(item => item.Kind != kind)];
        LibraryFrameError error = host.AppendDefectStroke(
            frame.Id,
            (identity, _) =>
            {
                try
                {
                    // 남은 항목이 없어도 recipe 자체는 남깁니다. 개정 번호가 이어져야
                    // 이전 편집이 되살아나지 않습니다.
                    return DefectRecipeSnapshot.Create(
                        frameId,
                        checked(recipe.RecipeRevision + 1UL),
                        identity,
                        remaining);
                }
                catch (Exception failure) when (failure is ArgumentException or OverflowException)
                {
                    return null;
                }
            });
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    private bool TryMapToRaw(DefectPoint displayPoint, out DefectPoint rawPoint)
    {
        rawPoint = default;
        if (SelectedFrame is not { } frame || frame.SourceMetadata is not { } metadata)
        {
            return false;
        }
        if (!DevelopDisplayGeometry.TryMapDisplayToRaw(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                displayPoint.X,
                displayPoint.Y,
                out double rawX,
                out double rawY))
        {
            return false;
        }
        rawPoint = new DefectPoint(rawX, rawY);
        return true;
    }

    public BwToningRecipe BwToning => SelectedFrame?.BwToning ?? BwToningRecipe.None;

    /// <summary>
    /// macOS 는 흑백 필름에서만 토닝 섹션을 냅니다. 컬러에서는 자리째 사라집니다.
    /// </summary>
    public bool ShowsBwToning => SelectedFrame?.Route.FilmType is
        FilmType.BlackAndWhiteNegative or FilmType.BlackAndWhitePositive;

    public LibraryFrameError SetBwToning(BwToningRecipe bwToning)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, BwToning: bwToning));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>
    /// 모드를 고릅니다. 켜는 순간 macOS 처럼 최소 세기를 보장합니다 — 0 인 채로 켜면 아무 일도
    /// 일어나지 않아 고장으로 보입니다. 색조는 그 모드의 기본값에서 시작합니다.
    /// </summary>
    public LibraryFrameError SetBwToningMode(Catalog.BwToningMode mode)
    {
        if (!Enum.IsDefined(mode))
        {
            return LibraryFrameError.InvalidBwToning;
        }
        return SetBwToning(mode == Catalog.BwToningMode.None
            ? BwToningRecipe.None
            : BwToningRecipe.For(
                mode,
                Math.Max(BwToning.ClampedStrength, BwToningRecipe.EngagedStrength)));
    }

    public LibraryFrameError ResetBwToning() => SetBwToning(BwToningRecipe.None);

    public LibraryFrameError SetPrimaryCalibration(PrimaryCalibrationRecipe primaryCalibration)
    {
        ArgumentNullException.ThrowIfNull(primaryCalibration);
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                PrimaryCalibration: primaryCalibration));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameError SetTexture(TextureRecipe texture)
    {
        ArgumentNullException.ThrowIfNull(texture);
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, Texture: texture));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameError SetNoiseReduction(NoiseReductionRecipe noiseReduction)
    {
        ArgumentNullException.ThrowIfNull(noiseReduction);
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, NoiseReduction: noiseReduction));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameError SetNoiseReductionEnabled(bool enabled) =>
        SetNoiseReduction(NoiseReduction with { Strength = enabled ? 0.7 : 0.0 });

    public LibraryFrameError Rotate(bool clockwise)
    {
        ImageRotation rotation = ImageTransform.Rotation;
        ImageRotation updated = clockwise
            ? rotation switch
            {
                ImageRotation.Degrees0 => ImageRotation.Degrees90,
                ImageRotation.Degrees90 => ImageRotation.Degrees180,
                ImageRotation.Degrees180 => ImageRotation.Degrees270,
                _ => ImageRotation.Degrees0,
            }
            : rotation switch
            {
                ImageRotation.Degrees0 => ImageRotation.Degrees270,
                ImageRotation.Degrees90 => ImageRotation.Degrees0,
                ImageRotation.Degrees180 => ImageRotation.Degrees90,
                _ => ImageRotation.Degrees180,
            };
        return SetImageTransform(ImageTransform with { Rotation = updated });
    }

    public LibraryFrameError FlipHorizontally() =>
        SetImageTransform(ImageTransform with { FlipHorizontal = !ImageTransform.FlipHorizontal });

    public LibraryFrameError FlipVertically() =>
        SetImageTransform(ImageTransform with { FlipVertical = !ImageTransform.FlipVertical });

    /// <summary>
    /// 반전 직후에 걸리는 opt-in Auto Levels 입니다. macOS 는 음화 route 에서만 이 토글을
    /// 내놓으므로, 양화에서 켜지지 않도록 여기서 막습니다.
    /// </summary>
    public LibraryFrameError SetAutoLevels(bool enabled) =>
        SetAutoCorrection(enabled, neutralBalance: null);

    /// <summary>Auto Neutral Balance 입니다. macOS 의 "자동 색상" 토글과 같은 자리입니다.</summary>
    public LibraryFrameError SetAutoNeutralBalance(bool enabled) =>
        SetAutoCorrection(autoLevels: null, neutralBalance: enabled);

    /// <summary>
    /// 지금 프레임의 현상 프로세스입니다. macOS <c>DevelopmentProcess(filmType:isDigitalSource:)</c>
    /// 와 같은 유도입니다 — 디지털 표시는 포지티브 경로에만 있고, 음화에 그 표시가 남아 있으면
    /// 필름으로 읽습니다.
    /// </summary>
    public DevelopmentProcess DevelopmentProcess =>
        SelectedFrame is not { } frame
            ? DevelopmentProcess.C41
            : DevelopProcesses.From(frame.Route.FilmType, frame.Route.IsDigitalSource);

    /// <summary>
    /// 현상 프로세스를 바꿉니다. 필름 룩과 세기는 그대로 두고 route 만 옮깁니다 — 프로세스를
    /// 바꿨다고 고른 필름이 사라지면 사용자가 다시 고르게 됩니다.
    /// </summary>
    public LibraryFrameError SetDevelopmentProcess(DevelopmentProcess process)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!Enum.IsDefined(process))
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        DevelopRouteSelection selection = DevelopRouteSelection.FromProcess(
            process,
            frame.Route.FilmEmulation,
            frame.Route.FilmEmulationIntensity);
        LibraryFrameError error = host.EditRoute(frame.Id, selection);
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>이 frame 에 담긴 현상 버전입니다. 최근에 담은 것이 뒤에 옵니다.</summary>
    public IReadOnlyList<LibraryVersionSnapshot> Versions =>
        SelectedFrame?.Versions ?? [];

    /// <summary>
    /// 지금 recipe 를 이름 붙여 담습니다. macOS 처럼 현재 상태는 그대로 두고 목록에만 더합니다 —
    /// 담는 것이 되돌리는 것을 뜻하지는 않습니다.
    /// </summary>
    public LibraryFrameError CaptureVersion(string name) =>
        EditFrameRecord(record => LibraryVersions.Capture(
            record,
            Guid.NewGuid().ToString("D"),
            name,
            DateTimeOffset.UtcNow));

    /// <summary>담아 둔 버전의 recipe 로 되돌립니다. 버전 목록은 남습니다.</summary>
    public LibraryFrameError RestoreVersion(string versionId) =>
        EditFrameRecord(record => LibraryVersions.Restore(record, versionId));

    public LibraryFrameError DeleteVersion(string versionId) =>
        EditFrameRecord(record => LibraryVersions.Delete(record, versionId));

    private LibraryFrameError EditFrameRecord(
        Func<System.Text.Json.Nodes.JsonObject, LibraryFrameWriteResult> edit)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        LibraryFrameError error = host.EditFrameRecord(frame.Id, edit);
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>
    /// 복사해 둔 현상 설정입니다. macOS 처럼 앱이 사는 동안만 남고 저장되지 않습니다 — 클립보드에
    /// 가까운 물건이지 카탈로그의 일부가 아닙니다.
    /// </summary>
    public LibraryFrameSnapshot? CopiedSettings { get; private set; }

    public string? CopiedSettingsSourceName { get; private set; }

    /// <summary>
    /// macOS 의 붙여넣기 범위입니다. 한 번 정하면 다음 붙여넣기에도 그대로 쓰입니다.
    /// </summary>
    public DevelopSettingsPasteScope PasteScope { get; set; } = DevelopSettingsPasteScope.All;

    public IReadOnlyList<DevelopUserPreset> UserPresets { get; private set; } = [];

    /// <summary>지금 프레임의 현상 설정을 복사해 둡니다.</summary>
    public bool CopyDevelopSettings()
    {
        if (SelectedFrame is not { } frame)
        {
            return false;
        }
        CopiedSettings = frame;
        CopiedSettingsSourceName = frame.DisplayName ?? Path.GetFileName(frame.SourcePath);
        return true;
    }

    /// <summary>
    /// 복사해 둔 설정을 지금 프레임에 <see cref="PasteScope"/> 만큼 붙입니다. 복사한 것이 없거나
    /// 범위가 비어 있으면 아무것도 하지 않습니다.
    /// </summary>
    public LibraryFrameError PasteDevelopSettings()
    {
        if (CopiedSettings is not { } source)
        {
            return LibraryFrameError.MissingId;
        }
        if (PasteScope.IsEmpty)
        {
            return LibraryFrameError.None;
        }
        if (SelectedFrame is not { } destination)
        {
            return LibraryFrameError.MissingId;
        }
        return EditFrameRecord(record =>
            DevelopSettingsTransfer.Paste(record, source, destination, PasteScope));
    }

    /// <summary>
    /// 사용자 프리셋 목록을 이 파일에서 읽고, 이후 저장·삭제도 여기에 씁니다. 경로를 주지 않으면
    /// 목록 기능이 그냥 비어 있습니다 — 셸이 저장소를 열지 못한 경우입니다.
    /// </summary>
    public void OpenUserPresets(string? path)
    {
        userPresetPath = path;
        UserPresets = string.IsNullOrWhiteSpace(path)
            ? []
            : DevelopUserPresetStore.Load(path);
    }

    /// <summary>지금 프레임의 현상 설정을 이름 붙여 프리셋으로 저장합니다.</summary>
    public DevelopUserPreset? SaveUserPreset(string name)
    {
        if (SelectedFrame is not { } frame ||
            string.IsNullOrWhiteSpace(name) ||
            DevelopUserPresetStore.Capture(frame, name.Trim()) is not { } preset)
        {
            return null;
        }
        UserPresets = [.. UserPresets, preset];
        PersistUserPresets();
        return preset;
    }

    public LibraryFrameError ApplyUserPreset(Guid id)
    {
        if (UserPresets.FirstOrDefault(preset => preset.Id == id) is not { } chosen)
        {
            return LibraryFrameError.MissingId;
        }
        if (SelectedFrame is not { } destination)
        {
            return LibraryFrameError.MissingId;
        }
        return EditFrameRecord(record =>
            DevelopUserPresetStore.Apply(record, chosen, destination));
    }

    public bool DeleteUserPreset(Guid id)
    {
        int before = UserPresets.Count;
        UserPresets = [.. UserPresets.Where(preset => preset.Id != id)];
        if (UserPresets.Count == before)
        {
            return false;
        }
        PersistUserPresets();
        return true;
    }

    private string? userPresetPath;

    private void PersistUserPresets()
    {
        if (userPresetPath is { Length: > 0 } path)
        {
            _ = DevelopUserPresetStore.Save(path, UserPresets);
        }
    }

    public FilmEmulation FilmEmulation => SelectedFrame?.Route.FilmEmulation ?? FilmEmulation.None;

    public double FilmEmulationIntensity => SelectedFrame?.Route.FilmEmulationIntensity ?? 0.5;

    /// <summary>
    /// macOS 는 필름 룩을 digital source 에서만 적용합니다. 스캔 프레임에서는 고르는 자리
    /// 대신 그 안내를 냅니다.
    /// </summary>
    public bool AppliesFilmLook => SelectedFrame?.Route.IsDigitalSource == true;

    /// <summary>필름 룩을 고릅니다. <c>None</c> 이면 룩을 끕니다.</summary>
    public LibraryFrameError SetFilmEmulation(FilmEmulation emulation) =>
        SetFilmLook(emulation, null);

    /// <summary>룩의 세기입니다. macOS 와 같이 0...1 로 자릅니다.</summary>
    public LibraryFrameError SetFilmEmulationIntensity(double intensity) =>
        SetFilmLook(null, Math.Clamp(intensity, 0.0, 1.0));

    private LibraryFrameError SetFilmLook(FilmEmulation? emulation, double? intensity)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        // 스캔 프레임에 룩을 적으면 macOS 가 내지 않는 단계가 걸립니다. 기록하지 않고 막습니다.
        if (!AppliesFilmLook)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.EditRoute(
            frame.Id,
            new DevelopRouteSelection(
                frame.Route.SourceSignalKind,
                frame.Route.FilmType,
                emulation ?? frame.Route.FilmEmulation,
                intensity ?? frame.Route.FilmEmulationIntensity));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    /// <summary>macOS 와 같이 음화 route 에서만 자동 보정 토글을 보여 줍니다.</summary>
    public bool ShowsAutoCorrections =>
        SelectedFrame?.Route.FilmType is FilmType.ColorNegative or FilmType.BlackAndWhiteNegative;

    public bool AutoLevels => SelectedFrame?.AutoLevels ?? false;

    public bool AutoNeutralBalance => SelectedFrame?.AutoNeutralBalance ?? false;

    private LibraryFrameError SetAutoCorrection(bool? autoLevels, bool? neutralBalance)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!ShowsAutoCorrections)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                AutoLevels: autoLevels ?? frame.AutoLevels,
                AutoNeutralBalance: neutralBalance ?? frame.AutoNeutralBalance));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameError SetStraightenAngle(double angle) =>
        SetImageTransform(ImageTransform with { StraightenAngle = Math.Clamp(angle, -45.0, 45.0) });

    /// <summary>
    /// Canvas crop session의 단일 commit 지점입니다. null은 전체 프레임을 뜻하며, drag 중에는
    /// 이 메서드를 호출하지 않아 preview/export와 catalog가 중간 선택 상태를 보지 않습니다.
    /// </summary>
    public LibraryFrameError SetCrop(ImageCropRect? crop) =>
        SetImageTransform(ImageTransform with { Crop = crop });

    /// <summary>
    /// 종횡비를 고릅니다. 원본은 비율과 crop 을 함께 지우고, 고정 비율은 그 비율로 가운데
    /// 정렬된 최대 crop 을 만듭니다 — macOS <c>applyCropAspect</c> 와 같습니다.
    /// </summary>
    public LibraryFrameError SetCropAspect(CropAspectOption option) =>
        SelectedFrame is not { } frame
            ? LibraryFrameError.MissingId
            : SetImageTransform(CropAspect.Apply(
                ImageTransform,
                option,
                frame.SourceMetadata?.PixelWidth ?? 0U,
                frame.SourceMetadata?.PixelHeight ?? 0U));

    private LibraryFrameError SetImageTransform(ImageTransformRecipe imageTransform)
    {
        ArgumentNullException.ThrowIfNull(imageTransform);
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, ImageTransform: imageTransform));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    private LibraryFrameError ApplyAutoAdjusted(LibraryFrameSnapshot adjusted)
    {
        LibraryFrameError error = host.Edit(
            adjusted.Id,
            new LibraryFrameEdit(
                adjusted.Tone,
                adjusted.ManualBase,
                ColorModel: adjusted.ColorModel));
        if (error == LibraryFrameError.None)
        {
            Select(adjusted.Id);
        }
        return error;
    }

    private LibraryFrameError SetTone(Func<ToneAdjustment, ToneAdjustment> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (!CanEditTone)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        ToneAdjustment tone = update(frame.Tone);
        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(tone, frame.ManualBase));
        if (error == LibraryFrameError.None)
        {
            // 편집 뒤 snapshot 은 새 객체이므로 선택을 다시 잡습니다.
            Select(frame.Id);
        }
        return error;
    }

    public CatalogStoreError Save() => host.Save();

    public Task<bool> ExportAsync(
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted)
    {
        ArgumentNullException.ThrowIfNull(onCompleted);
        if (SelectedFrame is not { } frame)
        {
            onCompleted(new DevelopExportOutcome(
                DevelopExportOutcomeKind.Refused,
                null,
                DevelopRequestRefusal.MissingManualBase,
                null));
            return Task.FromResult(true);
        }
        return host.ExportAsync(frame, destinationPath, format, onCompleted);
    }

    /// <summary>
    /// 결과를 사용자에게 보여 줄 한 줄로 만듭니다. 실패는 어느 단계에서 왜 멈췄는지를 남깁니다 —
    /// "Export failed" 만 보여 주면 스캔을 다시 하는 것 말고 할 수 있는 일이 없습니다.
    /// </summary>
    public static string Describe(DevelopExportOutcome outcome)
    {
        ArgumentNullException.ThrowIfNull(outcome);
        switch (outcome.Kind)
        {
            case DevelopExportOutcomeKind.Completed when outcome.Result is { } result:
                if (!result.Succeeded)
                {
                    return $"Develop stopped at {Humanize(result.FailedStage)}: {result.FailureName}";
                }
                double milliseconds = result.WallMicroseconds / 1000.0;
                return string.Create(
                    CultureInfo.CurrentCulture,
                    $"Exported {result.ImageWidth}×{result.ImageHeight} in {milliseconds:F0} ms");

            case DevelopExportOutcomeKind.Refused:
                return outcome.Refusal switch
                {
                    DevelopRequestRefusal.MissingManualBase =>
                        "Set the film base (Dmin) before developing this frame.",
                    DevelopRequestRefusal.MissingFilmStock =>
                        "Select a film stock before developing this frame.",
                    DevelopRequestRefusal.UnsupportedBaseEstimationMode =>
                        "This film-base mode is not supported by the Windows engine yet.",
                    DevelopRequestRefusal.UnsupportedDigitalSource =>
                        "This frame is a rendered digital source, which cannot be developed yet.",
                    DevelopRequestRefusal.UnsupportedPositiveFilm =>
                        "Positive film development is not supported by the Windows engine yet.",
                    DevelopRequestRefusal.InvalidDestination =>
                        "Choose a full path to export to.",
                    DevelopRequestRefusal.UnknownOutputFormat =>
                        "That export format is not supported.",
                    _ => "The develop request was refused.",
                };

            case DevelopExportOutcomeKind.Faulted:
                return $"The engine failed: {outcome.FaultMessage}";

            case DevelopExportOutcomeKind.Busy:
                return "A develop is already running.";

            default:
                return "The develop produced no result.";
        }
    }

    private static string Humanize(DevelopExportStage stage) => stage switch
    {
        DevelopExportStage.RequestValidation => "request validation",
        DevelopExportStage.ObserveSourceBefore => "reading the source file",
        DevelopExportStage.Decode => "decoding",
        DevelopExportStage.ObserveSourceAfter => "re-checking the source file",
        DevelopExportStage.FilmLookWorkspace => "preparing the Film Look",
        DevelopExportStage.Develop => "developing",
        DevelopExportStage.ToneAdjust => "tone adjustment",
        DevelopExportStage.FilmLook => "the Film Look",
        DevelopExportStage.Output => "writing the file",
        _ => "an unknown stage",
    };
}
