using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopRequestRouteTests
{
    public static void Run()
    {
        const string destination = @"C:\exports\IMG_0001.png";

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), filmType: FilmType.BlackAndWhiteNegative),
                destination).Request?.FilmType == NegativeFilmType.BlackAndWhite,
            "develop_request_bw_film_type");

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), emulation: FilmEmulation.None),
                destination).Request?.FilmEmulation == FilmEmulationProfile.None,
            "develop_request_no_emulation");

        Check(
            DevelopRequestFactory.Create(
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    filmType: FilmType.BlackAndWhiteNegative,
                    emulation: FilmEmulation.TriX400),
                destination).Request?.FilmEmulation == FilmEmulationProfile.TriX400,
            "develop_request_bw_emulation");

        Check(
            DevelopRequestFactory.Create(
                Frame(
                    null,
                    signal: SourceSignalKind.RenderedDigital,
                    filmType: FilmType.ColorPositive,
                    emulation: FilmEmulation.Vision3_500T),
                destination).Request?.FilmEmulation == FilmEmulationProfile.Vision3_500T,
            "develop_request_motion_picture_emulation");

        DevelopRequestResult auto = DevelopRequestFactory.Create(Frame(null), destination);
        Check(auto.IsSuccess, "develop_request_auto_without_manual_base_succeeds");
        Check(
            auto.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Auto,
            "develop_request_auto_mode");

        // Auto에는 이전 manual value가 남아 있을 수 있지만 resolver가 그것을 재사용하면 안 됩니다.
        DevelopRequestResult autoWithStaleManual = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                baseRecipe: BaseRecipe.Auto),
            destination);
        Check(
            autoWithStaleManual.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Auto &&
                autoWithStaleManual.Request?.DminRed == 0.0F,
            "develop_request_auto_ignores_stale_manual_base");

        // 수동인데 고른 값이 없으면 거절이 아니라 **자동**입니다. macOS
        // `resolveFilmBase` 는 `if let manual = params.manualBaseRGB, …` 로 값이 있을 때만
        // 수동을 쓰고 없으면 자동 추정으로 흘러갑니다 — `resetManualBase` 직후가 이 상태이며,
        // 여기서 막으면 값을 지운 사진이 통째로 보이지 않게 됩니다.
        DevelopRequestResult noBase = DevelopRequestFactory.Create(
            Frame(
                null,
                baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)),
            destination);
        Check(noBase.IsSuccess, "develop_request_manual_without_base_falls_back_to_auto");
        Check(
            noBase.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Auto &&
                noBase.Request?.DminRed == 0.0F,
            "develop_request_manual_without_base_sends_auto");

        DevelopRequestResult preset = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                baseRecipe: new BaseRecipe(
                    BaseEstimationMode.Preset,
                    "kodak-portra-400",
                    "warm-led",
                    "noritsu__color-nega__kodak-portra-400")),
            destination);
        Check(
            preset.IsSuccess &&
                preset.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Preset &&
                preset.Request?.FilmStockDminId == "kodak-portra-400" &&
                preset.Request?.LightSourceProfileId == "warm-led" &&
                preset.Request?.ScannerProfileId ==
                    "noritsu__color-nega__kodak-portra-400",
            "develop_request_carries_film_and_scanner_profile_identifiers");
        // 필름을 고르지 않은 preset 도 거절이 아니라 **자동**입니다. macOS
        // `applyNegativeFilmPipeline` 은 `filmStockDminID` 가 없으면 `preset` 자체를 nil 로
        // 두어 `resolveFilmBase` 와 반전이 모두 자동 경로로 갑니다.
        DevelopRequestResult presetWithoutStock = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                baseRecipe: new BaseRecipe(BaseEstimationMode.Preset, null, "warm-led", null)),
            destination);
        Check(presetWithoutStock.IsSuccess, "develop_request_preset_without_stock_succeeds");
        Check(
            presetWithoutStock.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Auto &&
                presetWithoutStock.Request?.FilmStockDminId is null &&
                // 광원 트림은 macOS 에서 preset 분기 안에서만 걸립니다.
                presetWithoutStock.Request?.LightSourceProfileId is null,
            "develop_request_preset_without_stock_sends_auto");

        DevelopRequestResult digital = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                SourceSignalKind.RenderedDigital,
                FilmType.ColorPositive),
            destination);
        Check(
            digital.IsSuccess &&
                digital.Request?.FilmLookSourceKind == DevelopSourceKind.RenderedDigital &&
                digital.Request?.FilmType == NegativeFilmType.Color &&
                digital.Request?.FilmPolarity == FilmPolarity.Positive &&
                digital.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Manual &&
                digital.Request?.DminRed == 0.0F,
            "develop_request_digital_bypasses_negative_base");

        DevelopRequestResult positiveFilm = DevelopRequestFactory.Create(
            Frame(null, SourceSignalKind.FilmPositiveScan, FilmType.ColorPositive),
            destination);
        Check(
            positiveFilm.IsSuccess &&
                positiveFilm.Request?.FilmLookSourceKind == DevelopSourceKind.FilmScan &&
                positiveFilm.Request?.FilmPolarity == FilmPolarity.Positive &&
                positiveFilm.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Manual,
            "develop_request_positive_film_bypasses_negative_base");

        DevelopRequestResult rawEyedropper = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.9, 0.65, 0.45)),
            destination,
            uninvertedSource: true);
        Check(
            rawEyedropper.IsSuccess &&
                rawEyedropper.Request?.FilmPolarity == FilmPolarity.Positive &&
                rawEyedropper.Request?.FilmType == NegativeFilmType.Color,
            "develop_request_eyedropper_shows_uninverted_raw");

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                "IMG_0001.png").Refusal == DevelopRequestRefusal.InvalidDestination,
            "develop_request_relative_destination_refused");
        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                "  ").Refusal == DevelopRequestRefusal.InvalidDestination,
            "develop_request_blank_destination_refused");
        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                destination,
                (DevelopExportFormat)99).Refusal ==
                DevelopRequestRefusal.UnknownOutputFormat,
            "develop_request_unknown_format_refused");
    }
}
