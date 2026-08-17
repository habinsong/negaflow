using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 촬영 기록 변환과 정보 카드 투영입니다. 이 계약은 `DevelopWorkspaceView` 안에 있을 때는
/// 화면을 띄우지 않고 확인할 수 없었습니다.
/// </summary>
internal static class DevelopMetadataTests
{
    public static void Run()
    {
        VerifyShutterRoundTrip();
        VerifyNumberFields();
        VerifyKeywordSplitting();
        VerifyEquivalence();
        VerifyInfoCardRows();
    }

    private static void VerifyShutterRoundTrip()
    {
        Check(DevelopMetadataFields.ParseShutter("1/125") is { } fast &&
            Math.Abs(fast - (1.0 / 125.0)) < 1e-9,
            "metadata_shutter_reads_a_fraction");
        Check(DevelopMetadataFields.ParseShutter("2") is { } slow && Math.Abs(slow - 2.0) < 1e-9,
            "metadata_shutter_reads_whole_seconds");
        Check(DevelopMetadataFields.ParseShutter("  ") is null &&
            DevelopMetadataFields.ParseShutter("1/0") is null &&
            DevelopMetadataFields.ParseShutter("x/y") is null,
            "metadata_shutter_refuses_what_it_cannot_read");
        // 1 초보다 짧으면 사진가가 읽는 분수로 되돌아와야 합니다.
        Check(DevelopMetadataFields.FormatShutter(1.0 / 125.0) == "1/125",
            "metadata_shutter_writes_a_fraction_back");
        Check(DevelopMetadataFields.FormatShutter(2.0) == "2" &&
            DevelopMetadataFields.FormatShutter(null) == string.Empty,
            "metadata_shutter_writes_whole_seconds_back");
    }

    private static void VerifyNumberFields()
    {
        Check(DevelopMetadataFields.ParseInteger("400") == 400 &&
            DevelopMetadataFields.ParseInteger("0") is null &&
            DevelopMetadataFields.ParseInteger("-1") is null &&
            DevelopMetadataFields.ParseInteger("abc") is null,
            "metadata_iso_takes_only_a_positive_whole_number");
        Check(DevelopMetadataFields.ParseNumber("2.8") is { } aperture &&
            Math.Abs(aperture - 2.8) < 1e-9 &&
            DevelopMetadataFields.ParseNumber("0") is null &&
            DevelopMetadataFields.ParseNumber("NaN") is null,
            "metadata_aperture_takes_only_a_positive_finite_number");
    }

    private static void VerifyKeywordSplitting()
    {
        IReadOnlyList<string> keywords = DevelopMetadataFields.SplitKeywords(" 서울 , 필름 , ");
        Check(keywords.Count == 2 && keywords[0] == "서울" && keywords[1] == "필름",
            "metadata_keywords_split_on_commas_and_drop_blanks");
        Check(DevelopMetadataFields.SplitKeywords(null).Count == 0,
            "metadata_keywords_accept_no_text");
    }

    private static void VerifyEquivalence()
    {
        AppMetadataOverlay stored = new() { Title = "A", Revision = 3 };
        // 개정 번호와 수정 시각만 다른 것은 같은 값입니다 — 아니면 저장할 때마다 다시 씁니다.
        AppMetadataOverlay same = new()
        {
            Title = "A",
            Revision = 9,
            UpdatedAt = DateTimeOffset.UnixEpoch,
        };
        Check(DevelopMetadataFields.Equivalent(stored, same),
            "metadata_ignores_revision_and_timestamp");
        Check(!DevelopMetadataFields.Equivalent(stored, new AppMetadataOverlay { Title = "B" }),
            "metadata_sees_a_changed_title");
        Check(!DevelopMetadataFields.Equivalent(
                stored,
                new AppMetadataOverlay { Title = "A", Keywords = ["서울"] }),
            "metadata_sees_changed_keywords");
    }

    private static void VerifyInfoCardRows()
    {
        DevelopInfoCardText text = new(
            "출처", "사이드카", "카메라", "날짜", "제목", "키워드",
            "—", "스캔", "가져오기", "미확인", "없음");
        Check(DevelopInfoCardProjection.Rows(null, text, _ => false).Count == 0,
            "info_card_has_no_rows_without_a_frame");

        LibraryFrameSnapshot frame = Frame(
            new ManualBaseRgb(0.2, 0.2, 0.2),
            sourcePath: @"C:\scans\roll\IMG_0001.tif");
        IReadOnlyList<DevelopInfoRow> rows =
            DevelopInfoCardProjection.Rows(frame, text, _ => false);
        Check(rows.Count == 6, "info_card_keeps_the_six_macos_rows");
        // 스캐너로 들어온 frame 이므로 출처 줄은 스캔이고 파일 이름만 붙습니다.
        Check(rows[0].Label == "출처" && rows[0].Value == "스캔 · IMG_0001.tif",
            "info_card_names_the_origin_and_the_file");
        Check(rows[1].Value == "없음", "info_card_says_a_missing_sidecar_is_missing");
        Check(DevelopInfoCardProjection.Rows(frame, text, _ => true)[1].Value == "미확인",
            "info_card_does_not_claim_it_read_a_present_sidecar");
        // 값이 없는 줄은 macOS 처럼 가운뎃점으로 이은 빈 표기입니다.
        Check(rows[2].Value == "— · —" && rows[3].Value == "— · —",
            "info_card_writes_the_macos_empty_pair");
        Check(DevelopInfoCardProjection.DescribeSidecar(
                frame,
                text,
                _ => throw new IOException("unreadable")) == "미확인",
            "info_card_treats_an_unreadable_sidecar_as_unknown");
    }
}
