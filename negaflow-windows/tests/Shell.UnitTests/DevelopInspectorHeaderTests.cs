using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 현상 인스펙터 머리줄 한 줄과 필름스트립 크기 산술입니다. 둘 다 화면이 아니라 값이라
/// 창 없이 잽니다.
/// </summary>
internal static class DevelopInspectorHeaderTests
{
    public static void Run()
    {
        VerifyScannerFrameShowsTargetAndProcess();
        VerifyImportedFrameShowsRealExif();
        VerifyMissingTagsStayEmpty();
        VerifyFilmstripItemScaleReachesTheCard();
    }

    /// <summary>
    /// 스캐너 TIFF 는 노출을 내지 않습니다 — 필름 카메라는 EXIF 를 남기지 않고, 스캔
    /// 파일에 적힌 노출은 스캐너의 것입니다. macOS <c>DevelopInspectorHeaderSummary</c> 도
    /// 이 갈래에서 타깃·공정만 냅니다.
    /// </summary>
    private static void VerifyScannerFrameShowsTargetAndProcess()
    {
        LibraryFrameSnapshot frame = Frame(null) with
        {
            SourceKind = FrameSourceKind.ScannerTiff,
            DevelopTarget = DevelopTarget.Noritsu,
        };
        Check(
            DevelopInspectorHeaderSummary.Text(
                frame,
                new ImageShotMetadata(400, 0.008, 2.8, 50)) == "HS · C-41/ECN-2",
            "develop_header_scanner_tiff_shows_target_and_process");
    }

    private static void VerifyImportedFrameShowsRealExif()
    {
        LibraryFrameSnapshot frame = Frame(null) with
        {
            SourceKind = FrameSourceKind.ImportedFile,
        };
        // 1/125 초는 0.008 로 적히는데, 되돌린 1/125 와 0.008 의 차이는 0.4% 라
        // macOS 와 같이 분수로 냅니다.
        Check(
            DevelopInspectorHeaderSummary.Text(
                frame,
                new ImageShotMetadata(400, 0.008, 2.8, 50)) ==
                "ISO 400 · 1/125 s · f/2.8 · 50 mm",
            "develop_header_imported_file_shows_real_exif");
        // 2 초는 분수로 되돌릴 값이 아니므로 초 그대로입니다.
        Check(
            DevelopInspectorHeaderSummary.ImportedMetadata(
                new ImageShotMetadata(100, 2.0, 11, 24)) ==
                "ISO 100 · 2 s · f/11 · 24 mm",
            "develop_header_long_exposure_stays_in_seconds");
        // 분수로 되돌리면 8% 넘게 어긋나는 값은 속이지 않고 초로 냅니다.
        Check(
            DevelopInspectorHeaderSummary.ImportedMetadata(
                new ImageShotMetadata(null, 0.4, null, null)) ==
                "ISO — · 0.4 s · f/— · — mm",
            "develop_header_unroundable_shutter_stays_in_seconds");
    }

    /// <summary>
    /// 값이 없으면 <c>—</c> 입니다. 앞 판은 이 자리에 상수 문자열을 박아 두어 값이 있는
    /// 파일에서도 늘 빈 줄이 나왔습니다.
    /// </summary>
    private static void VerifyMissingTagsStayEmpty()
    {
        Check(
            DevelopInspectorHeaderSummary.ImportedMetadata(default) ==
                "ISO — · — s · f/— · — mm",
            "develop_header_absent_exif_stays_absent");
        Check(
            new ImageShotMetadata(null, null, null, null).IsEmpty,
            "image_shot_metadata_without_tags_is_empty");
    }

    /// <summary>
    /// 하단바의 크기 HUD 가 실제로 카드 크기를 바꾸는지입니다. 앞 판은 카드를 잴 때 배율을
    /// <c>1.0</c> 으로 박아 두어 <c>−</c>·<c>+</c> 가 퍼센트 글자만 바꿨습니다.
    /// </summary>
    private static void VerifyFilmstripItemScaleReachesTheCard()
    {
        const double height = ShellLayoutMetrics.FilmstripDefaultHeight;
        double small = FilmstripMetrics.ItemHeight(
            ShellLayoutMetrics.FilmstripMinimumItemScale, height);
        double normal = FilmstripMetrics.ItemHeight(1.0, height);
        Check(small < normal, "filmstrip_smaller_scale_makes_a_smaller_card");
        Check(
            FilmstripMetrics.CardWidth(small) < FilmstripMetrics.CardWidth(normal),
            "filmstrip_smaller_scale_makes_a_narrower_card");
        // macOS `itemSize.height` 는 줄 칸을 넘지 않습니다. 배율을 올려도 마찬가지입니다.
        double large = FilmstripMetrics.ItemHeight(
            ShellLayoutMetrics.FilmstripMaximumItemScale, height);
        Check(large <= height, "filmstrip_card_never_exceeds_the_strip");
        // 스트립이 낮으면 저장된 배율을 그대로 쓸 수 없습니다 — macOS 도 실효 배율로 접습니다.
        Check(
            FilmstripMetrics.EffectiveItemScale(
                ShellLayoutMetrics.FilmstripMaximumItemScale,
                ShellLayoutMetrics.FilmstripMinimumHeight) <=
                FilmstripMetrics.MaximumEffectiveItemScale(
                    ShellLayoutMetrics.FilmstripMaximumItemScale,
                    ShellLayoutMetrics.FilmstripMinimumHeight),
            "filmstrip_effective_scale_never_exceeds_its_own_maximum");
    }
}
