using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

public enum DevelopRequestRefusal
{
    None,

    /// <summary>고른 사진이 없습니다.</summary>
    /// <remarks>
    /// 예전에는 이 자리에 <c>MissingManualBase</c>(수동인데 Dmin 이 없음)와
    /// <c>MissingFilmStock</c>(preset 인데 필름이 없음)이 있었습니다. 두 상태 모두 macOS 는
    /// 거절하지 않고 자동 추정으로 현상하므로 (<c>resolveFilmBase</c>,
    /// <c>applyNegativeFilmPipeline</c>) 사유 자체가 없어졌습니다. 남아 있던 유일한 쓰임은
    /// "고른 사진이 없다" 를 이 값으로 알리던 것이라, 그 뜻을 이름에 담습니다.
    /// </remarks>
    NoFrameSelected,

    UnsupportedBaseEstimationMode,

    /// <summary>Scene-linear 또는 알 수 없는 digital source는 아직 지원하지 않습니다.</summary>
    UnsupportedDigitalSource,

    UnsupportedPositiveFilm,

    /// <summary>출력 형식이 알려진 값이 아닙니다.</summary>
    UnknownOutputFormat,

    UnsupportedAlpha,

    /// <summary>출력 경로가 비었거나 절대 경로가 아닙니다.</summary>
    InvalidDestination,

    InvalidDefectRecipe,

    UnsupportedDefectEditKind,

    /// <summary>
    /// 결함 편집을 기록할 때의 원본과 지금 파일이 다르고, <b>화소 격자까지 달라졌습니다.</b>
    /// 마스크를 다른 화소에 얹게 되므로 현상하지 않습니다.
    /// </summary>
    StaleDefectSource,
}

/// <param name="DroppedStaleDefectEdits">
/// 원본 파일이 결함 편집을 기록할 때와 달라져 <b>화면용 요청에서만</b> 편집을 내려놓았습니다.
/// 편집은 카탈로그에 그대로 있습니다 — 부르는 쪽이 사용자에게 알릴 자리입니다.
/// </param>
public readonly record struct DevelopRequestResult(
    DevelopExportRequest? Request,
    DevelopRequestRefusal Refusal,
    bool DroppedStaleDefectEdits = false)
{
    public bool IsSuccess => Refusal == DevelopRequestRefusal.None && Request is not null;

    internal static DevelopRequestResult Success(
        DevelopExportRequest request,
        bool droppedStaleDefectEdits = false) =>
        new(request, DevelopRequestRefusal.None, droppedStaleDefectEdits);

    internal static DevelopRequestResult Failure(DevelopRequestRefusal refusal) =>
        new(null, refusal);
}

/// <summary>
/// catalog 에 저장된 frame 을 네이티브 현상 요청으로 옮깁니다. 이 계층이 catalog 와 엔진을 동시에
/// 아는 유일한 곳이며, 그래서 <c>Shell.Core</c> 가 Interop 과 같은 아키텍처에 묶여 있습니다.
/// XAML 을 참조하지 않으므로 UI 없이 그대로 시험할 수 있습니다.
/// </summary>
public static partial class DevelopRequestFactory
{
    /// <summary>
    /// 결함 편집이 걸린 사진을 현상할 때 **원본 파일 내용을 SHA-256 으로 검증**할지입니다.
    /// 설정의 <c>이미지 내용 해시</c>(<see cref="ImageContentHashMode"/>)가 그대로 옵니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// 켜면 <b>렌더마다 원본 전체를 다시 읽어 해시합니다.</b> frame_1(104MB) 실측으로
    /// 슬라이더 틱당 약 140ms 였고, 단계 표 어디에도 안 잡히는 시간이었습니다. 그런데
    /// 설정의 기본값은 <c>Off</c> 인데도 그 검사가 무조건 돌고 있었습니다 — 설정을 저장만
    /// 하고 아무도 읽지 않았기 때문입니다.
    /// </para>
    /// <para>
    /// 정적인 이유 — <see cref="Create"/> 를 부르는 자리가 60곳이 넘고 전부 같은 사용자
    /// 설정 하나를 따릅니다. 인자로 나르면 한 곳만 빠뜨려도 경로마다 정책이 갈립니다.
    /// 값을 넣는 곳은 셸의 설정 적용 지점 한 곳뿐입니다.
    /// </para>
    /// </remarks>
    public static bool VerifyDefectSourceContent { get; set; }

    /// <summary>
    /// 내용 해시를 끈 상태에서 보내는 자리표시자 sha 입니다. 전부 0 이면 네이티브가
    /// "바이트 수만 확인" 으로 읽습니다 — 실제 파일의 SHA-256 이 64자리 0 일 수는 없습니다.
    /// </summary>
    private const string DefectSourceContentCheckOnly =
        "0000000000000000000000000000000000000000000000000000000000000000";

    public static DevelopRequestResult Create(
        LibraryFrameSnapshot frame,
        string destinationPath,
        DevelopExportFormat format = DevelopExportFormat.Png16,
        ExportEncodingOptions? encoding = null,
        bool uninvertedSource = false,
        bool forceDefectSourceContentVerification = false,
        bool allowStaleDefectSource = false,
        uint proxyInputLongEdge = 0U)
    {
        ArgumentNullException.ThrowIfNull(frame);
        // 인코딩 값은 게시되는 파일에만 영향을 줍니다. preview 는 항상 기본값으로 도므로 크기·
        // DPI·출력 선명도가 화면과 파일을 갈라놓지 않습니다.
        ExportEncodingOptions output = (encoding ?? ExportEncodingOptions.Default).Sanitized();

        if (!Enum.IsDefined(format))
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.UnknownOutputFormat);
        }
        if (output.PreserveAlpha && format == DevelopExportFormat.Jpeg8)
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.UnsupportedAlpha);
        }
        if (string.IsNullOrWhiteSpace(destinationPath) ||
            !Path.IsPathFullyQualified(destinationPath))
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.InvalidDestination);
        }
        bool renderedDigital = frame.Route.FilmLookSource == FilmLookSource.RenderedDigital;
        bool positive = frame.Route.FilmType is
            FilmType.ColorPositive or FilmType.BlackAndWhitePositive;
        if (frame.Route.SourceSignalKind is
            SourceSignalKind.SceneLinearDigital or SourceSignalKind.Unknown)
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.UnsupportedDigitalSource);
        }
        if ((frame.Route.SourceSignalKind == SourceSignalKind.FilmNegativeScan && positive) ||
            (frame.Route.SourceSignalKind == SourceSignalKind.FilmPositiveScan && !positive) ||
            (renderedDigital && !positive))
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.UnsupportedPositiveFilm);
        }
        DevelopBaseEstimationMode baseMode;
        ManualBaseRgb manualBase = default;
        string? filmStockDminId = null;
        string? lightSourceProfileId = null;
        if (positive)
        {
            // Positive film and digital input bypass Dmin/base resolution and inversion.
            // Manual+zero is an explicit inert ABI value; the native digital branch ignores it.
            baseMode = DevelopBaseEstimationMode.Manual;
        }
        else switch (frame.Base.Mode)
        {
            case BaseEstimationMode.Auto:
                baseMode = DevelopBaseEstimationMode.Auto;
                break;
            case BaseEstimationMode.Manual when frame.ManualBase is { } selectedManualBase:
                baseMode = DevelopBaseEstimationMode.Manual;
                manualBase = selectedManualBase;
                break;
            // 수동인데 고른 값이 없으면 자동으로 갑니다. macOS
            // `ChromabaseEngine+NegativePipeline.resolveFilmBase` 가 그렇습니다:
            //     if let manual = params.manualBaseRGB, params.baseEstimationMode == .manual {…}
            // **값이 있을 때만** 수동을 쓰고, 없으면 그대로 자동 추정으로 흘러갑니다.
            // `resetManualBase` 가 값을 지운 직후가 정확히 이 상태입니다.
            case BaseEstimationMode.Manual:
                baseMode = DevelopBaseEstimationMode.Auto;
                break;
            case BaseEstimationMode.Preset when !string.IsNullOrWhiteSpace(frame.Base.FilmStockDminId):
                baseMode = DevelopBaseEstimationMode.Preset;
                filmStockDminId = frame.Base.FilmStockDminId;
                lightSourceProfileId = frame.Base.LightSourceProfileId;
                break;
            // 필름을 고르지 않은 preset 도 같습니다. macOS
            // `ChromabaseEngine+NegativePipeline.applyNegativeFilmPipeline`:
            //     let preset: FilmStockDmin? = (params.baseEstimationMode == .preset)
            //         ? params.filmStockDminID.flatMap { FilmStockDminRegistry.find($0) } : nil
            // `filmStockDminID` 가 없으면 `preset` 자체가 nil 이 되어 `resolveFilmBase` 는
            // 자동 분기로, 반전도 `applySceneRanged`(자동 경로)로 갑니다. 광원 프로파일은
            // preset 분기에서만 쓰이므로 여기서도 붙이지 않습니다.
            case BaseEstimationMode.Preset:
                baseMode = DevelopBaseEstimationMode.Auto;
                break;
            default:
                return DevelopRequestResult.Failure(
                    DevelopRequestRefusal.UnsupportedBaseEstimationMode);
        }
        if (!DefectRecipeProjector.TryProject(
                frame.DefectRecipe,
                out IReadOnlyList<DevelopDefectRegionEdit> defectRegions,
                out IReadOnlyList<DevelopDefectInfraredEdit> defectInfrared,
                out IReadOnlyList<DevelopDefectCloneEdit> defectClones,
                out IReadOnlyList<DevelopDefectBrushEdit> defectBrushes,
                out IReadOnlyList<DevelopDefectRecipeEditRef> defectEditOrder,
                out DevelopRequestRefusal defectRefusal))
        {
            return DevelopRequestResult.Failure(defectRefusal);
        }
        // 프리셋 합성은 여기 한 곳에서만 합니다. preview, thumbnail, export 가 모두 이 함수를
        // 지나므로 세 경로가 같은 레시피를 쓰는 것이 구조로 보장됩니다.
        LookPreset? preset = LookPresetLibrary.Resolve(frame.LookPresetId);
        ToneAdjustment tone = preset is null
            ? frame.Tone
            : LookPresetComposition.Compose(preset, frame.Tone);
        TextureRecipe texture = preset is null
            ? frame.Texture
            : LookPresetComposition.Compose(preset, frame.Texture);
        ColorModelRecipe colorModel = preset is null
            ? frame.ColorModel
            : LookPresetComposition.Compose(preset, frame.ColorModel);

        // macOS `DevelopFrameRenderer.renderRawPreview` 는 원본 CIImage 에 기하 변환만 걸어
        // 그립니다 — 톤도, 커브도, 스캐너 타깃도, 필름 룩도 얹지 않습니다.
        //
        // 여기서 레시피를 남겨 두면 `원본` 탭이 **반전만 빠진 현상본**이 됩니다. 자동 레벨이
        // 채널을 각각 끝까지 늘려 네거티브의 주황 마스크를 탈색시키고, NORITSU 타깃의 루마
        // USM 이 그레인을 깎아 세웁니다 — 사진앱으로 본 원본과 전혀 다른 그림이 되고,
        // "원본부터 베이스 색이 이상하고 컬러 노이즈 범벅" 으로 보입니다.
        //
        // 결함 제거는 남깁니다. macOS 도 raw 프리뷰에 cleaned raw 를 넘깁니다.
        if (uninvertedSource)
        {
            tone = default;
            texture = TextureRecipe.Identity;
            colorModel = ColorModelRecipe.Identity;
        }
        PointCurveRecipe pointCurves =
            uninvertedSource ? PointCurveRecipe.Identity : frame.PointCurves;
        ColorMixerRecipe colorMixer =
            uninvertedSource ? ColorMixerRecipe.Identity : frame.ColorMixer;
        ColorGradingRecipe colorGrading =
            uninvertedSource ? ColorGradingRecipe.Identity : frame.ColorGrading;
        PrimaryCalibrationRecipe calibration =
            uninvertedSource ? PrimaryCalibrationRecipe.Identity : frame.PrimaryCalibration;
        NoiseReductionRecipe noiseReduction =
            uninvertedSource ? NoiseReductionRecipe.Identity : frame.NoiseReduction;
        BwToningRecipe bwToning = uninvertedSource ? default : frame.BwToning;
        IReadOnlyList<LocalDodgeBurnAdjustment> dodgeBurn =
            uninvertedSource ? [] : frame.LocalDodgeBurn;
        DevelopTarget developTarget =
            uninvertedSource ? DevelopTarget.Main : frame.DevelopTarget;
        FilmEmulation filmEmulation =
            uninvertedSource ? FilmEmulation.None : frame.Route.FilmEmulation;

        DevelopDefectSourceIdentity? defectSourceIdentity = null;
        bool droppedStaleDefectEdits = false;
        // **원본이 바뀌었으면 결함 편집만 내려놓고 사진은 보여 줍니다.**
        //
        // 엔진은 identity 가 어긋나면 현상을 통째로 거부합니다
        // (`observe.cpp`: `defect_source_identity_mismatch`). 마스크를 다른 화소에 얹지
        // 않으려는 것이라 그 자체는 옳습니다. 그런데 셸이 그 실패를 그대로 받아 캔버스를
        // 비우면 **사진이 아예 안 보입니다** - 실기에서 스캔 원본 파일이 바뀐 사진 한 장이
        // 썸네일을 눌러도 열리지 않았습니다.
        //
        // 그래서 화면용 요청에서만(`allowStaleDefectSource`) 미리 크기를 보고, 어긋나면
        // 결함 편집을 뺀 채로 청합니다. 편집은 카탈로그에 그대로 남아 있고, 부르는 쪽이
        // 사용자에게 알릴 수 있게 결과에 표시를 답니다. **내보내기는 이 길로 오지
        // 않습니다** - 거기서는 편집을 조용히 빼면 안 되므로 그대로 거부합니다.
        if (allowStaleDefectSource && defectEditOrder.Count != 0 &&
            frame.DefectRecipe?.SourceIdentity is { } recorded &&
            !SourceStillMatches(frame.SourcePath, recorded.ByteCount))
        {
            defectRegions = [];
            defectInfrared = [];
            defectClones = [];
            defectBrushes = [];
            defectEditOrder = [];
            droppedStaleDefectEdits = true;
        }
        if (defectEditOrder.Count != 0)
        {
            if (frame.DefectRecipe?.SourceIdentity is not { } sourceIdentity)
            {
                return DevelopRequestResult.Failure(
                    DevelopRequestRefusal.InvalidDefectRecipe);
            }
            // 여기 실린 sha 는 네이티브 `observe_source_before` 가 **렌더마다 원본 파일
            // 전체를 다시 읽어 SHA-256 하게** 만듭니다. frame_1(104MB) 실측으로 슬라이더
            // 틱당 약 140ms 이고, 설정 `이미지 내용 해시` 의 기본값이 **끔**인데도 돌고
            // 있었습니다 — 그 설정을 아무도 읽지 않았기 때문입니다.
            //
            // ABI 는 결함 편집이 있으면 identity 를 **요구**하므로(`has_edits ==
            // has_identity`) 빼지 못합니다. 대신 sha 를 0 으로 채워 보냅니다 —
            // 네이티브가 그것을 "바이트 수만 확인" 으로 읽습니다
            // (`export/stages/observe.cpp`). 파일이 바뀌면 크기·수정 시각이 먼저
            // 달라지므로 값싼 검사만으로도 마스크를 엉뚱한 사진에 걸 일은 없습니다.
            // 기록된 바이트 수가 **지금 파일과 다를 수 있습니다.** 원본이 그 자리에서 한 번
            // 다시 쓰이면(결함 굽기·IR 정리·스캐너 재저장) 그렇게 됩니다.
            //
            // 앞 판은 그대로 보냈고, 네이티브가 `defect_source_identity_mismatch` 로 거부해
            // **그 사진은 영영 내보낼 수 없었습니다.** 화면에는 프리뷰가 멀쩡히 나오는데
            // (프리뷰는 `allowStaleDefectSource` 로 편집을 빼고 그립니다) 내보내기만
            // 1~4 ms 만에 끝나고 아무 파일도 남지 않았습니다 — 실기 2026-08-29,
            // `OpticFilm8100-0002.tif` 가 109,181,328 → 109,216,380 바이트로 바뀐 뒤부터.
            //
            // macOS 는 이때 거부하지 않고 cleaned raw 를 **다시 짓습니다**
            // (`prepareCleanedRawForExport`: `discardCleanedRaw` → `rebuildCleanedRaw`).
            // 이 검사의 목적은 마스크를 **다른 화소**에 얹지 않는 것이므로, 화소 격자가
            // 그대로일 때만 지금 파일로 다시 앵커해 같은 결론에 이릅니다. 크기가 달라졌으면
            // 그때는 정말로 다른 그림이라 거부합니다.
            ulong anchoredByteCount = sourceIdentity.ByteCount;
            bool reanchored = false;
            // **원본을 다시 쓰는 길에서는 다시 앵커하지 않습니다.** 결함 굽기가
            // `forceDefectSourceContentVerification` 으로 내용 해시까지 확인하는 이유가
            // 그것입니다 — 화소 격자가 같다는 것만으로 원본을 덮어쓰면 안 됩니다. 읽기만
            // 하는 내보내기는 격자가 같으면 이어 갑니다.
            if (!forceDefectSourceContentVerification &&
                !SourceStillMatches(frame.SourcePath, sourceIdentity.ByteCount))
            {
                if (CurrentSourceByteCount(frame.SourcePath) is not { } currentByteCount ||
                    !SourcePixelGridUnchanged(frame))
                {
                    return DevelopRequestResult.Failure(
                        DevelopRequestRefusal.StaleDefectSource);
                }
                anchoredByteCount = currentByteCount;
                reanchored = true;
            }
            defectSourceIdentity = new DevelopDefectSourceIdentity(
                anchoredByteCount,
                // 다시 앵커했으면 기록된 sha 는 이 파일의 것이 아닙니다. 그것을 그대로
                // 보내면 내용 검사를 켠 사용자만 다시 거부당합니다.
                !reanchored &&
                (VerifyDefectSourceContent || forceDefectSourceContentVerification)
                    ? sourceIdentity.Sha256
                    : DefectSourceContentCheckOnly);
        }

        return Succeed(droppedStaleDefectEdits, new DevelopExportRequest
        {
            SourcePath = frame.SourcePath,
            DestinationPath = destinationPath,
            Format = format,
            OutputDpi = (uint)output.Dpi,
            OutputLongEdge = (uint)output.LongEdge,
            // 0 이 기본입니다 — 인화 판만 값을 넘깁니다.
            ProxyInputLongEdge = proxyInputLongEdge,
            JpegQuality = (float)output.JpegQuality,
            TiffCompression = output.TiffCompression,
            OutputBitDepth = (uint)output.BitDepth,
            OutputColorSpace = output.ColorSpace,
            OutputIccProfile = output.OutputIccProfile,
            PreserveAlpha = output.PreserveAlpha,
            MetadataPolicy = output.MetadataPolicy,
            Metadata = output.Metadata ?? new ExportMetadataValues(),
            OutputSharpening = (float)output.OutputSharpening,
            OutputSharpeningMedium = output.OutputSharpeningMedium,
            OutputSharpeningDpi = output.Dpi,
            FilmType = MapFilmType(frame.Route.FilmType),
            // macOS `selectCompareMode(.raw)` — 스포이드는 반전 전 raw 를 본다.
            FilmPolarity = positive || uninvertedSource
                ? FilmPolarity.Positive
                : FilmPolarity.Negative,
            BaseEstimationMode = baseMode,
            DminRed = (float)manualBase.Red,
            DminGreen = (float)manualBase.Green,
            DminBlue = (float)manualBase.Blue,
            FilmStockDminId = filmStockDminId,
            LightSourceProfileId = lightSourceProfileId,
            ScannerProfileId = uninvertedSource ? null : frame.Base.ScannerProfileId,
            ExposureStops = (float)tone.Exposure,
            Contrast = (float)tone.Contrast,
            Density = (float)tone.Density,
            Highlight = (float)tone.Highlight,
            Shadow = (float)tone.Shadow,
            Whites = (float)tone.Whites,
            Blacks = (float)tone.Blacks,
            Highlights = (float)tone.CurveHighlights,
            Lights = (float)tone.CurveLights,
            Darks = (float)tone.CurveDarks,
            Shadows = (float)tone.CurveShadows,
            Warmth = (float)colorModel.Warmth,
            Tint = (float)colorModel.Tint,
            ColorDepth = (float)colorModel.ColorDepth,
            Vibrance = (float)colorModel.Vibrance,
            Saturation = (float)colorModel.Saturation,
            RedPrimary = (float)colorModel.RedPrimary,
            GreenPrimary = (float)colorModel.GreenPrimary,
            BluePrimary = (float)colorModel.BluePrimary,
            AutoLevels = !uninvertedSource && frame.AutoLevels,
            AutoNeutralBalance = !uninvertedSource && frame.AutoNeutralBalance,
            DevelopTarget = developTarget switch
            {
                DevelopTarget.Main => DevelopTargetMode.Main,
                DevelopTarget.Print => DevelopTargetMode.Print,
                DevelopTarget.Noritsu => DevelopTargetMode.Noritsu,
                DevelopTarget.Sp3000 => DevelopTargetMode.Sp3000,
                DevelopTarget.F135 => DevelopTargetMode.F135,
                DevelopTarget.Hr => DevelopTargetMode.Hr,
                DevelopTarget.Rescue => DevelopTargetMode.Rescue,
                _ => throw new ArgumentOutOfRangeException(nameof(frame)),
            },
            PointCurves = new DevelopPointCurves
            {
                Rgb = pointCurves.Rgb.Select(point =>
                    new DevelopPointCurvePoint(point.X, point.Y)).ToArray(),
                Red = pointCurves.Red.Select(point =>
                    new DevelopPointCurvePoint(point.X, point.Y)).ToArray(),
                Green = pointCurves.Green.Select(point =>
                    new DevelopPointCurvePoint(point.X, point.Y)).ToArray(),
                Blue = pointCurves.Blue.Select(point =>
                    new DevelopPointCurvePoint(point.X, point.Y)).ToArray(),
            },
            ColorMixer = new DevelopColorMixer
            {
                Hue = colorMixer.Hue.Select(value => (float)value).ToArray(),
                Saturation = colorMixer.Saturation.Select(value => (float)value).ToArray(),
                Luminance = colorMixer.Luminance.Select(value => (float)value).ToArray(),
            },
            ColorGrading = new DevelopColorGrading
            {
                Shadows = MapColorGradeRegion(colorGrading.Shadows),
                Midtones = MapColorGradeRegion(colorGrading.Midtones),
                Highlights = MapColorGradeRegion(colorGrading.Highlights),
                Blending = (float)colorGrading.Blending,
                Balance = (float)colorGrading.Balance,
            },
            PrimaryCalibration = new DevelopPrimaryCalibration
            {
                RedHue = (float)calibration.RedHue,
                RedSaturation = (float)calibration.RedSaturation,
                GreenHue = (float)calibration.GreenHue,
                GreenSaturation = (float)calibration.GreenSaturation,
                BlueHue = (float)calibration.BlueHue,
                BlueSaturation = (float)calibration.BlueSaturation,
            },
            FilmLookSourceKind = renderedDigital
                ? DevelopSourceKind.RenderedDigital
                : DevelopSourceKind.FilmScan,
            FilmEmulation = MapFilmEmulation(filmEmulation),
            FilmEmulationIntensity = uninvertedSource ? 0.0f : frame.Route.FilmEmulationIntensity,
            ImageTransform = MapImageTransform(frame.ImageTransform),
            Grain = (float)texture.Grain,
            Sharpness = (float)texture.Sharpness,
            Halation = (float)texture.Halation,
            Clarity = (float)texture.Clarity,
            Vignette = (float)texture.Vignette,
            NoiseReductionStrength = (float)noiseReduction.Strength,
            NoiseReductionLuma = (float)noiseReduction.Luma,
            NoiseReductionChroma = (float)noiseReduction.Chroma,
            NoiseReductionDarkTone = (float)noiseReduction.DarkTone,
            NoiseReductionDetail = (float)noiseReduction.Detail,
            NoiseReductionGrainProtect = (float)noiseReduction.GrainProtect,
            NoiseReductionFilmProfile = MapNoiseReductionFilmProfile(frame.Route.FilmType),
            BwToningMode = bwToning.Mode switch
            {
                Catalog.BwToningMode.Selenium => Interop.BwToningMode.Selenium,
                Catalog.BwToningMode.Sepia => Interop.BwToningMode.Sepia,
                _ => Interop.BwToningMode.None,
            },
            DefectRemovalStrength = frame.DefectRemovalStrength,
            BwToningShadowHue = bwToning.ShadowHue,
            BwToningHighlightHue = bwToning.HighlightHue,
            BwToningStrength = bwToning.ClampedStrength,
            DefectRegions = defectRegions,
            DefectInfrared = defectInfrared,
            DefectClones = defectClones,
            DefectBrushes = defectBrushes,
            DefectEditOrder = defectEditOrder,
            DefectSourceIdentity = defectSourceIdentity,
            DefectRecipeSha256 = defectEditOrder.Count == 0
                ? null
                : frame.DefectRecipe!.RecipeSha256,
            DefectRecipeAppendPrefixSha256 = defectEditOrder.Count <= 1
                ? null
                : frame.DefectRecipe!.AppendPrefixSha256,
            DefectRecipeAppendPrefixEditCount = defectEditOrder.Count <= 1
                ? 0
                : frame.DefectRecipe!.AppendPrefixEditCount,
            LocalDodgeBurn = dodgeBurn.Select(MapLocalDodgeBurn).ToArray(),
        });
    }


    private static DevelopRequestResult Succeed(
        bool droppedStaleDefectEdits,
        DevelopExportRequest request) =>
        DevelopRequestResult.Success(request, droppedStaleDefectEdits);

}
