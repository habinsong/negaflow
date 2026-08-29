using Negaflow.Shell.Develop;
using Negaflow.Shell.Print;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 인화 배치별로 <b>파일이 몇 개 나오는지</b>와, 그 수가 내보내기 단추에 어떻게 적히는지의
/// 전수 시험입니다. 한 장만 고른 경우와 여러 장을 고른 경우를 모두 봅니다.
/// </summary>
/// <remarks>
/// macOS <c>printExportOutputCount</c> 와 <c>ExportSection.exportButtonTitle(_:)</c> 를
/// 옮긴 자리입니다 — 낱장은 사진마다 판 하나이고, 콘택트 시트·사진 패키지·사용자 패키지는
/// 한 판에 여러 장을 얹으므로 사진 수와 파일 수가 다릅니다. 윈도우는 그 계산이 아예 없어
/// 단추가 늘 사진 수를 적었고, 판 수와 어긋나도 아무도 막지 않았습니다.
/// </remarks>
internal static class PrintExportOutputCountTests
{
    public static void Run()
    {
        VerifySingleImageIsOnePagePerPhoto();
        VerifyContactSheetPacksManyPhotosOntoOnePage();
        VerifyContactSheetRepeatsOnePhotoPerPage();
        VerifyPicturePackageCapacityPerTemplate();
        VerifyCustomPackageCountsItsOwnPages();
        VerifyRefusedLayoutsReportNoCount();
        VerifyButtonTitleFollowsTheLayout();
        VerifyPlannedPagesMatchTheExpectedCount();
    }

    /// <summary>
    /// <b>센 판 수와 실제로 짜인 판 수가 같아야 합니다.</b> 어긋나면 단추에 적힌 수와 나오는
    /// 파일 수가 달라지고, 인화 쓰기는 그 어긋남을 보고 거부합니다 — 그러면 사용자는 아무
    /// 파일도 못 받습니다. macOS 도 쓰기 전에 같은 것을 확인합니다.
    /// </summary>
    private static void VerifyPlannedPagesMatchTheExpectedCount()
    {
        PrintCompositionSettings composition = new();
        (string Name, PrintPackageSettings Package, int Sources)[] cases =
        [
            ("contact-1", Sheet(2, 3), 1),
            ("contact-full", Sheet(2, 3), 6),
            ("contact-spill", Sheet(2, 3), 7),
            ("contact-repeat", Sheet(2, 3) with { RepeatOnePhotoPerPage = true }, 3),
            ("picture-one-large", Picture(PrintPicturePackageTemplate.OneLargeTwoSmall), 4),
            ("picture-two-up", Picture(PrintPicturePackageTemplate.TwoUp), 3),
            ("picture-four-up", Picture(PrintPicturePackageTemplate.FourUp), 5),
            ("custom-two-pages", Custom(), 2),
        ];
        foreach ((string name, PrintPackageSettings package, int sources) in cases)
        {
            int? expected = PrintPackageLayout.ExpectedPageCount(sources, package);
            IReadOnlyList<PrintPackagePageLayout>? pages = PrintPackageLayout.Make(
                [.. Enumerable.Repeat(new PrintSizeMm(3000, 2000), sources)],
                composition,
                package);
            Check(
                expected is not null && pages is not null && pages.Count == expected.Value,
                "print_pages_match_the_expected_count_" + name);
        }
    }

    private static PrintPackageSettings Picture(PrintPicturePackageTemplate template) =>
        Sheet(2, 2) with
        {
            Mode = PrintPackageMode.PicturePackage,
            PictureTemplate = template,
        };

    private static PrintPackageSettings Custom() =>
        Sheet(2, 2) with
        {
            Mode = PrintPackageMode.CustomPackage,
            CustomItems = [Item(0, 0), Item(1, 1)],
        };

    /// <summary>낱장·청사진·유리건판·젤라틴은 패키지가 아닙니다 — 사진마다 한 판입니다.</summary>
    private static void VerifySingleImageIsOnePagePerPhoto()
    {
        foreach (PrintLayoutMode mode in new[]
        {
            PrintLayoutMode.SingleImage,
            PrintLayoutMode.Cyanotype,
            PrintLayoutMode.GlassPlate,
            PrintLayoutMode.Gelatin,
        })
        {
            Check(
                PrintPreferences.PackageModeFor(mode) is null,
                "print_layout_" + mode + "_is_not_a_package");
        }
    }

    /// <summary>콘택트 시트는 칸이 다 찰 때까지 한 판에 담습니다.</summary>
    private static void VerifyContactSheetPacksManyPhotosOntoOnePage()
    {
        PrintPackageSettings sheet = Sheet(rows: 7, columns: 6);
        Check(
            PrintPackageLayout.ExpectedPageCount(1, sheet) == 1,
            "contact_sheet_one_photo_is_one_page");
        Check(
            PrintPackageLayout.ExpectedPageCount(42, sheet) == 1,
            "contact_sheet_fills_one_page_to_capacity");
        Check(
            PrintPackageLayout.ExpectedPageCount(43, sheet) == 2,
            "contact_sheet_spills_onto_a_second_page");
        Check(
            PrintPackageLayout.ExpectedPageCount(0, sheet) == 0,
            "contact_sheet_without_photos_has_no_page");
    }

    /// <summary>"사진마다 한 판" 을 켜면 칸 수와 무관하게 사진 수만큼 나옵니다.</summary>
    private static void VerifyContactSheetRepeatsOnePhotoPerPage()
    {
        PrintPackageSettings repeated = Sheet(rows: 7, columns: 6) with
        {
            RepeatOnePhotoPerPage = true,
        };
        Check(
            PrintPackageLayout.ExpectedPageCount(3, repeated) == 3,
            "contact_sheet_repeat_makes_one_page_per_photo");
    }

    /// <summary>사진 패키지는 서식마다 칸 수가 정해져 있습니다.</summary>
    private static void VerifyPicturePackageCapacityPerTemplate()
    {
        (PrintPicturePackageTemplate Template, int Capacity)[] templates =
        [
            (PrintPicturePackageTemplate.OneLargeTwoSmall, 3),
            (PrintPicturePackageTemplate.TwoUp, 2),
            (PrintPicturePackageTemplate.FourUp, 4),
        ];
        foreach ((PrintPicturePackageTemplate template, int capacity) in templates)
        {
            PrintPackageSettings package = Sheet(rows: 2, columns: 2) with
            {
                Mode = PrintPackageMode.PicturePackage,
                PictureTemplate = template,
            };
            Check(
                PrintPackageLayout.ExpectedPageCount(1, package) == 1,
                "picture_package_" + template + "_one_photo_is_one_page");
            Check(
                PrintPackageLayout.ExpectedPageCount(capacity, package) == 1,
                "picture_package_" + template + "_fills_one_page");
            Check(
                PrintPackageLayout.ExpectedPageCount(capacity + 1, package) == 2,
                "picture_package_" + template + "_spills_onto_a_second_page");
        }
    }

    /// <summary>사용자 패키지는 칸이 스스로 몇 판인지 말합니다.</summary>
    private static void VerifyCustomPackageCountsItsOwnPages()
    {
        PrintPackageSettings custom = Sheet(rows: 2, columns: 2) with
        {
            Mode = PrintPackageMode.CustomPackage,
            CustomItems =
            [
                Item(sourceIndex: 0, pageIndex: 0),
                Item(sourceIndex: 1, pageIndex: 1),
            ],
        };
        Check(
            PrintPackageLayout.ExpectedPageCount(2, custom) == 2,
            "custom_package_counts_its_highest_page");
        // 없는 사진을 가리키면 판을 낼 수 없습니다 — 한 장만 골랐는데 두 번째 칸이 있는 경우.
        Check(
            PrintPackageLayout.ExpectedPageCount(1, custom) is null,
            "custom_package_refuses_when_an_item_points_past_the_selection");
    }

    /// <summary>셀 수 없는 설정은 <see langword="null"/> 입니다 — 그때는 판을 쓰지 않습니다.</summary>
    private static void VerifyRefusedLayoutsReportNoCount()
    {
        PrintPackageSettings invalid = Sheet(rows: 0, columns: 6);
        Check(
            PrintPackageLayout.ExpectedPageCount(4, invalid) is null,
            "invalid_package_has_no_page_count");
        // 판이 상한을 넘으면 거부합니다.
        PrintPackageSettings tiny = Sheet(rows: 1, columns: 1) with
        {
            RepeatOnePhotoPerPage = true,
        };
        Check(
            PrintPackageLayout.ExpectedPageCount(
                PrintPackageSettings.MaximumPageCount + 1, tiny) is null,
            "package_beyond_the_page_limit_has_no_count");
    }

    /// <summary>
    /// 단추 문구입니다. 낱장은 여러 장일 때만 숫자를 달고, 한 판에 여러 장을 얹는 배치는
    /// <b>한 장이어도</b> 숫자를 답니다 — 그 숫자가 나올 파일 수이기 때문입니다.
    /// </summary>
    private static void VerifyButtonTitleFollowsTheLayout()
    {
        Check(
            Title(selected: 1, paperCount: 0, paper: false, composite: false) == "내보내기",
            "develop_one_frame_has_no_count");
        Check(
            Title(selected: 3, paperCount: 0, paper: false, composite: false) == "내보내기 (3)",
            "develop_many_frames_show_the_frame_count");
        // 인화 낱장: 사진 셋이면 판도 셋입니다.
        Check(
            Title(selected: 3, paperCount: 3, paper: true, composite: false) == "내보내기 (3)",
            "print_single_image_shows_one_page_per_photo");
        // 인화 콘택트 시트: 사진 열둘이 판 하나입니다. 한 장을 골라도 적습니다.
        Check(
            Title(selected: 12, paperCount: 1, paper: true, composite: true) == "내보내기 (1)",
            "print_contact_sheet_shows_the_page_count_not_the_photo_count");
        Check(
            Title(selected: 1, paperCount: 1, paper: true, composite: true) == "내보내기 (1)",
            "print_composite_shows_the_count_even_for_one_photo");
    }

    private static string Title(int selected, int paperCount, bool paper, bool composite) =>
        ExportPanelProjection.Create(
            null,
            new ExportSettings(),
            new QuickExportSettings(),
            namingContext: null,
            canExport: true,
            selectedFrameCount: selected,
            "원본 옆",
            "내보내기",
            "빠른 내보내기",
            usesPaperLayout: paper,
            usesCompositeLayout: composite,
            paperOutputCount: paperCount).ExportButtonText;

    private static PrintPackageSettings Sheet(int rows, int columns) => new()
    {
        Mode = PrintPackageMode.ContactSheet,
        ContactRows = rows,
        ContactColumns = columns,
    };

    private static PrintCustomPackageItem Item(int sourceIndex, int pageIndex) =>
        new(sourceIndex, new PrintRect(0.1, 0.1, 0.3, 0.3)) { PageIndex = pageIndex };
}
