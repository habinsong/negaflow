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
