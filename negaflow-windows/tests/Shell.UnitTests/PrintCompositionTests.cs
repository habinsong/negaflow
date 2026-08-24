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

internal static class PrintCompositionTests
{
    public static void Run()
    {
        VerifyPrintComposition();
    }

    private static void VerifyPrintComposition()
    {
        LibraryFrameSnapshot durable = Frame(null) with { Id = "print-durable" };
        LibraryFrameSnapshot preview = Frame(null) with
        {
            Id = "print-preview",
            IsPreviewScan = true,
        };
        Check(
            PrintSourceSelection.Eligible([preview, durable]).Single().Id == durable.Id &&
            PrintSourceSelection.Resolve([preview], [preview, durable]).Single().Id == durable.Id &&
            PrintSourceSelection.Resolve([preview], [preview]).Count == 0 &&
            PrintSourceSelection.ActiveFrameId(preview.Id, [durable]) == durable.Id,
            "print_excludes_transient_scanner_preview_from_all_sources");

        // 용지 치수는 macOS dimensionsMM 과 같은 수여야 합니다.
        Check(
            PrintPaper.DimensionsMm(PrintPaperSize.A4) == new PrintSizeMm(210, 297) &&
                PrintPaper.DimensionsMm(PrintPaperSize.Letter) == new PrintSizeMm(215.9, 279.4) &&
                PrintPaper.DimensionsMm(PrintPaperSize.EightByTen) == new PrintSizeMm(203.2, 254),
            "print_paper_dimensions_match_mac");
        Check(PrintPaper.All.Count == 27, "print_paper_count_matches_mac");

        // 사진 비율 용지는 사진을 따라갑니다. 비율을 모르면 3:2 입니다.
        Check(
            PrintPaper.DimensionsMm(PrintPaperSize.PhotoRatio, null) ==
                new PrintSizeMm(PrintPaper.PhotoRatioLongEdgeMm * 2 / 3,
                    PrintPaper.PhotoRatioLongEdgeMm),
            "print_photo_ratio_defaults_to_three_by_two");
        Check(
            PrintPaper.DimensionsMm(PrintPaperSize.PhotoRatio, 1.5) ==
                new PrintSizeMm(254, 254 / 1.5),
            "print_photo_ratio_follows_a_landscape_photo");

        PrintCompositionSettings a4 = new() { PaperSize = PrintPaperSize.A4, Dpi = 300 };
        // 자동 방향은 사진을 따라갑니다 — 가로 사진에는 가로 용지입니다.
        PrintCompositionLayout landscape =
            PrintCompositionLayout.Make(new PrintSizeMm(3000, 2000), a4)!;
        Check(
            landscape.CanvasSize.Width > landscape.CanvasSize.Height,
            "print_automatic_orientation_follows_the_photo");
        // 297mm 를 300dpi 로 재면 3508 화소입니다.
        Check(
            Math.Abs(landscape.CanvasSize.Width - 3508) < 1 &&
                Math.Abs(landscape.CanvasSize.Height - 2480) < 1,
            "print_canvas_is_the_paper_at_the_chosen_dpi");
        // 여백은 화소가 아니라 밀리미터입니다.
        Check(
            Math.Abs(landscape.ContentRect.X - (10 * 300 / 25.4)) < 0.5,
            "print_margin_is_millimetres_not_pixels");

        PrintCompositionLayout portrait = PrintCompositionLayout.Make(
            new PrintSizeMm(2000, 3000),
            a4 with { Orientation = PrintPaperOrientation.Landscape })!;
        Check(
            portrait.CanvasSize.Width > portrait.CanvasSize.Height,
            "print_explicit_orientation_overrides_the_photo");

        // 말이 안 되는 설정은 판을 만들지 않습니다.
        Check(
            PrintCompositionLayout.Make(new PrintSizeMm(0, 100), a4) is null,
            "print_refuses_an_empty_source");
        Check(
            PrintCompositionLayout.Make(new PrintSizeMm(100, 100), a4 with { MarginMm = 200 })
                is null,
            "print_refuses_a_margin_that_eats_the_page");
        Check(
            !(a4 with { Dpi = 20 }).IsValid && !(a4 with { MarginMm = 60 }).IsValid,
            "print_settings_validity_matches_mac_limits");

        // 천공은 ISO 1007 의 135 규격입니다 — 한 쪽 8개씩 모두 16개.
        PrintCompositionLayout perforated = PrintCompositionLayout.Make(
            new PrintSizeMm(3000, 2000),
            a4 with { PerforationStyle = PrintPerforationStyle.ThirtyFiveMillimeter })!;
        Check(perforated.PerforationRects.Count == 16, "print_perforation_count_matches_iso_1007");
        Check(perforated.FilmRect is not null, "print_perforation_adds_a_film_rect");
        // 필름 폭 35mm 안의 게이트는 24mm 이므로 이미지가 필름보다 작아야 합니다.
        Check(
            perforated.ImageRect.Height < perforated.FilmRect!.Value.Height,
            "print_image_sits_inside_the_film_gate");

        // 시아노타입만 색이 다릅니다.
        Check(
            PrintPresentationAppearance.For(PrintPresentationStyle.Cyanotype).ShadowBlue > 0.3 &&
                PrintPresentationAppearance.For(PrintPresentationStyle.GelatinSilver).ShadowBlue == 0,
            "print_presentation_colours_match_mac");

        // 판 배치: 7 곱하기 6 격자에 42장이 한 판, 43장이면 두 판입니다.
        PrintPackageSettings sheet = new() { ContactRows = 7, ContactColumns = 6 };
        PrintSizeMm[] fortyTwo = [.. Enumerable.Repeat(new PrintSizeMm(3000, 2000), 42)];
        IReadOnlyList<PrintPackagePageLayout> onePage =
            PrintPackageLayout.Make(fortyTwo, a4, sheet)!;
        Check(
            onePage.Count == 1 && onePage[0].Items.Count == 42,
            "print_contact_sheet_fills_one_page");
        PrintSizeMm[] fortyThree = [.. Enumerable.Repeat(new PrintSizeMm(3000, 2000), 43)];
        IReadOnlyList<PrintPackagePageLayout> twoPages =
            PrintPackageLayout.Make(fortyThree, a4, sheet)!;
        Check(
            twoPages.Count == 2 && twoPages[1].Items.Count == 1,
            "print_contact_sheet_spills_to_a_second_page");

        // 칸은 왼쪽 위부터 오른쪽으로 채웁니다.
        Check(
            onePage[0].Items[0].CellRect.X < onePage[0].Items[1].CellRect.X &&
                Math.Abs(onePage[0].Items[0].CellRect.Y - onePage[0].Items[1].CellRect.Y) < 0.001,
            "print_contact_sheet_fills_left_to_right");
        Check(
            onePage[0].Items[6].CellRect.Y > onePage[0].Items[0].CellRect.Y,
            "print_contact_sheet_wraps_to_the_next_row");

        // 한 판에 한 사진을 반복하면 사진 수만큼 판이 나옵니다.
        IReadOnlyList<PrintPackagePageLayout> repeated = PrintPackageLayout.Make(
            [new PrintSizeMm(3000, 2000), new PrintSizeMm(2000, 3000)],
            a4,
            sheet with { RepeatOnePhotoPerPage = true })!;
        Check(
            repeated.Count == 2 && repeated[0].Items.Count == 42 &&
                repeated[0].Items.All(item => item.SourceIndex == 0),
            "print_repeat_gives_each_photo_its_own_page");

        // 채우기는 칸을 넘고, 맞추기는 칸 안에 듭니다.
        PrintPackageItemLayout fit = onePage[0].Items[0];
        PrintPackageItemLayout fill = PrintPackageLayout.Make(
            [new PrintSizeMm(3000, 2000)],
            a4,
            sheet with { ContentMode = PrintPackageContentMode.Fill })![0].Items[0];
        Check(
            fit.ImageRect.Width <= fit.CellRect.Width + 0.001 &&
                fit.ImageRect.Height <= fit.CellRect.Height + 0.001,
            "print_fit_stays_inside_the_cell");
        Check(
            fill.ImageRect.Width >= fill.CellRect.Width - 0.001 &&
                fill.ImageRect.Height >= fill.CellRect.Height - 0.001,
            "print_fill_covers_the_cell");

        // 돌려 맞추기는 더 커질 때만 돕니다.
        IReadOnlyList<PrintPackagePageLayout> rotated = PrintPackageLayout.Make(
            [new PrintSizeMm(2000, 3000)],
            a4,
            new PrintPackageSettings { ContactRows = 1, ContactColumns = 1, RotateToFit = true })!;
        Check(
            rotated[0].Items[0].QuarterTurns == 1,
            "print_rotate_to_fit_turns_a_portrait_photo_on_a_landscape_cell");
        IReadOnlyList<PrintPackagePageLayout> notRotated = PrintPackageLayout.Make(
            [new PrintSizeMm(3000, 2000)],
            a4,
            new PrintPackageSettings { ContactRows = 1, ContactColumns = 1, RotateToFit = true })!;
        Check(
            notRotated[0].Items[0].QuarterTurns == 0,
            "print_rotate_to_fit_leaves_a_matching_photo_alone");

        // 설정 파일이 이상해도 화면이 비지 않아야 합니다.
        PrintPreferences wild = new()
        {
            MarginMm = 900,
            Dpi = 5,
            ContactRows = 0,
            ContactColumns = 999,
            HorizontalSpacingMm = double.NaN,
        };
        PrintPreferences safe = wild.Normalize();
        Check(
            safe.MarginMm == 50 && safe.Dpi == 72 && safe.ContactRows == 1 &&
                safe.ContactColumns == 20 && safe.HorizontalSpacingMm == 4,
            "print_preferences_clamp_a_hand_edited_file");
        Check(safe.Composition().IsValid, "print_normalized_preferences_make_a_valid_page");

        VerifyPicturePackage(a4);
        VerifyPrintCaptionsAndCropMarks(a4);
        VerifyPrintCaptionText();
        VerifyPrintRuler();
        VerifyCustomPackage(a4);
    }

    /// <summary>
    /// 손으로 놓은 배치입니다. 자리는 비율이라 용지를 바꿔도 배치가 살아남아야 하고, 판 번호에
    /// 구멍이 있으면 빈 장이 인쇄되므로 아예 만들지 않아야 합니다.
    /// </summary>
    private static void VerifyCustomPackage(PrintCompositionSettings a4)
    {
        PrintSizeMm[] sizes = [new(3000, 2000), new(2000, 3000)];
        PrintPackageSettings custom = new()
        {
            Mode = PrintPackageMode.CustomPackage,
            CustomItems =
            [
                new PrintCustomPackageItem(0, new PrintRect(0, 0, 0.5, 0.5)),
                new PrintCustomPackageItem(1, new PrintRect(0.5, 0.5, 0.5, 0.5)),
            ],
        };
        IReadOnlyList<PrintPackagePageLayout> pages =
            PrintPackageLayout.Make(sizes, a4, custom)!;
        Check(pages.Count == 1 && pages[0].Items.Count == 2, "print_custom_places_both");
        // 비율이 실제 자리로 풀립니다.
        PrintRect content = pages[0].ContentRect;
        Check(
            Math.Abs(pages[0].Items[0].CellRect.X - content.MinX) < 0.001 &&
                Math.Abs(pages[0].Items[0].CellRect.Width - (content.Width / 2)) < 0.001,
            "print_custom_rect_is_a_fraction_of_the_content");
        Check(
            Math.Abs(pages[0].Items[1].CellRect.X - (content.MinX + (content.Width / 2))) < 0.001,
            "print_custom_second_cell_is_offset");

        // 용지를 바꿔도 비율은 그대로입니다.
        IReadOnlyList<PrintPackagePageLayout> letter =
            PrintPackageLayout.Make(sizes, a4 with { PaperSize = PrintPaperSize.Letter }, custom)!;
        Check(
            Math.Abs(
                (letter[0].Items[0].CellRect.Width / letter[0].ContentRect.Width) -
                (pages[0].Items[0].CellRect.Width / content.Width)) < 0.001,
            "print_custom_survives_a_paper_change");

        // 겹칠 때는 ZIndex 차례로 쌓고, 같으면 목록 차례입니다.
        IReadOnlyList<PrintPackagePageLayout> stacked = PrintPackageLayout.Make(
            sizes,
            a4,
            custom with
            {
                CustomItems =
                [
                    new PrintCustomPackageItem(0, new PrintRect(0, 0, 1, 1)) { ZIndex = 5 },
                    new PrintCustomPackageItem(1, new PrintRect(0, 0, 0.4, 0.4)) { ZIndex = 1 },
                ],
            })!;
        Check(
            stacked[0].Items[0].SourceIndex == 1 && stacked[0].Items[1].SourceIndex == 0,
            "print_custom_sorts_by_z_index");

        // 판 번호에 구멍이 있으면 빈 장이 인쇄됩니다 — 만들지 않습니다.
        Check(
            PrintPackageLayout.Make(
                sizes,
                a4,
                custom with
                {
                    CustomItems =
                    [
                        new PrintCustomPackageItem(0, new PrintRect(0, 0, 1, 1)) { PageIndex = 1 },
                    ],
                }) is null,
            "print_custom_refuses_a_gap_in_the_page_numbers");

        // 판 밖으로 나가는 칸과 없는 사진을 가리키는 칸은 거절합니다.
        Check(
            PrintPackageLayout.Make(
                sizes,
                a4,
                custom with
                {
                    CustomItems = [new PrintCustomPackageItem(0, new PrintRect(0.8, 0, 0.5, 0.5))],
                }) is null,
            "print_custom_refuses_a_cell_off_the_page");
        Check(
            PrintPackageLayout.Make(
                sizes,
                a4,
                custom with
                {
                    CustomItems = [new PrintCustomPackageItem(9, new PrintRect(0, 0, 0.5, 0.5))],
                }) is null,
            "print_custom_refuses_a_missing_photo");
        Check(
            PrintPackageLayout.Make(sizes, a4, custom with { CustomItems = [] }) is null,
            "print_custom_refuses_an_empty_layout");

        // 칸마다 맞추기·돌리기를 따로 고릅니다.
        IReadOnlyList<PrintPackagePageLayout> mixed = PrintPackageLayout.Make(
            sizes,
            a4,
            custom with
            {
                CustomItems =
                [
                    new PrintCustomPackageItem(0, new PrintRect(0, 0, 0.5, 1))
                    {
                        ContentMode = PrintPackageContentMode.Fill,
                    },
                    new PrintCustomPackageItem(0, new PrintRect(0.5, 0, 0.5, 1)),
                ],
            })!;
        Check(
            mixed[0].Items[0].ImageRect.Height >= mixed[0].Items[0].CellRect.Height - 0.001 &&
                mixed[0].Items[1].ImageRect.Height <= mixed[0].Items[1].CellRect.Height + 0.001,
            "print_custom_content_mode_is_per_cell");
    }

    /// <summary>
    /// 캡션 글자입니다. 별점 0 이 빈칸이면 캡션이 켜졌는지조차 알 수 없습니다.
    /// </summary>
    private static void VerifyPrintCaptionText()
    {
        LibraryFrameSnapshot frame = Frame(null, sourcePath: @"C:\scans\IMG_0007.tif") with
        {
            ScanIndex = 7,
            Rating = 3,
        };
        Check(
            PrintCaptionFormatter.Caption(frame, PrintPackageCaptionMode.None, 1) is null,
            "print_caption_none_writes_nothing");
        // 확장자까지 적습니다 — 같은 이름의 TIFF 와 PNG 를 구별해야 합니다.
        Check(
            PrintCaptionFormatter.Caption(frame, PrintPackageCaptionMode.FileName, 1) ==
                "IMG_0007.tif",
            "print_caption_file_name_keeps_the_extension");
        Check(
            PrintCaptionFormatter.Caption(frame, PrintPackageCaptionMode.FrameNumber, 1) == "7",
            "print_caption_frame_number");
        Check(
            PrintCaptionFormatter.Caption(frame, PrintPackageCaptionMode.SequenceNumber, 4) == "4",
            "print_caption_sequence_number_is_the_slot");
        Check(
            PrintCaptionFormatter.Caption(frame, PrintPackageCaptionMode.Rating, 1) == "★★★",
            "print_caption_rating_draws_stars");
        Check(
            PrintCaptionFormatter.Caption(
                frame with { Rating = 0 },
                PrintPackageCaptionMode.Rating,
                1) == "—",
            "print_caption_zero_rating_is_a_dash_not_a_blank");
    }

    /// <summary>
    /// 눈금자는 용지의 실제 mm 를 따릅니다 — 화면 배율이 아닙니다. 그래야 화면에서 잰 길이가
    /// 인화물에서도 같습니다.
    /// </summary>
    private static void VerifyPrintRuler()
    {
        // A4 세로 297mm: 1cm 눈금이 0…29 로 서른 개, 5mm 눈금이 그 사이에 듭니다.
        IReadOnlyList<PrintRulerTick> metric =
            PrintRuler.Ticks(297, PrintRulerUnit.Centimeters);
        Check(metric.Count == 60, "print_ruler_metric_tick_count");
        Check(
            metric.Count(tick => tick.Label is not null) == 30,
            "print_ruler_metric_labels_every_centimetre");
        Check(metric[0].Label == "0" && metric[2].Label == "1", "print_ruler_metric_numbering");
        Check(
            metric[1].Label is null && metric[1].Length < metric[0].Length,
            "print_ruler_half_centimetre_is_shorter_and_unlabelled");
        // 자리는 0…1 이라 화면이든 판이든 곱하기만 하면 됩니다.
        Check(
            metric.All(tick => tick.Position is >= 0 and <= 1),
            "print_ruler_positions_are_normalized");
        Check(
            Math.Abs(metric[2].Position - (10.0 / 297)) < 1e-9,
            "print_ruler_position_follows_millimetres");

        // 인치는 1/4 마다 눈금, 1인치마다 숫자입니다.
        IReadOnlyList<PrintRulerTick> imperial = PrintRuler.Ticks(254, PrintRulerUnit.Inches);
        Check(
            imperial.Count(tick => tick.Label is not null) == 11,
            "print_ruler_inch_labels");
        Check(
            imperial[2].Length > imperial[1].Length && imperial[4].Length > imperial[2].Length,
            "print_ruler_inch_tick_lengths_step_up");

        Check(PrintRuler.Ticks(0, PrintRulerUnit.Inches).Count == 0, "print_ruler_refuses_zero");
        Check(
            PrintRuler.Ticks(double.NaN, PrintRulerUnit.Inches).Count == 0,
            "print_ruler_refuses_nan");
    }

    /// <summary>
    /// 픽처 패키지는 칸이 템플릿에 매여 있습니다. 사진이 칸보다 적으면 앞에서부터 다시 써야
    /// 합니다 — 빈 칸을 남기면 인화지 한 장이 반만 쓰입니다.
    /// </summary>
    private static void VerifyPicturePackage(PrintCompositionSettings a4)
    {
        PrintPackageSettings twoUp = new()
        {
            Mode = PrintPackageMode.PicturePackage,
            PictureTemplate = PrintPicturePackageTemplate.TwoUp,
        };
        IReadOnlyList<PrintPackagePageLayout> pages = PrintPackageLayout.Make(
            [new PrintSizeMm(3000, 2000), new PrintSizeMm(2000, 3000)],
            a4,
            twoUp)!;
        Check(pages.Count == 1 && pages[0].Items.Count == 2, "print_two_up_holds_two");
        Check(
            pages[0].Items[0].CellRect.X < pages[0].Items[1].CellRect.X,
            "print_two_up_sits_side_by_side");

        // 사진 한 장이면 두 칸 모두 그 사진입니다.
        IReadOnlyList<PrintPackagePageLayout> single = PrintPackageLayout.Make(
            [new PrintSizeMm(3000, 2000)],
            a4,
            twoUp)!;
        Check(
            single[0].Items.Count == 2 && single[0].Items.All(item => item.SourceIndex == 0),
            "print_picture_package_reuses_a_single_photo");

        // 큰 칸 하나에 작은 칸 둘. 큰 칸이 가로의 2/3 를 가집니다.
        IReadOnlyList<PrintPackagePageLayout> mixed = PrintPackageLayout.Make(
            [.. Enumerable.Repeat(new PrintSizeMm(3000, 2000), 3)],
            a4,
            twoUp with { PictureTemplate = PrintPicturePackageTemplate.OneLargeTwoSmall })!;
        Check(mixed[0].Items.Count == 3, "print_one_large_two_small_holds_three");
        Check(
            mixed[0].Items[0].CellRect.Width > mixed[0].Items[1].CellRect.Width * 1.5,
            "print_one_large_two_small_gives_the_large_cell_two_thirds");
        Check(
            mixed[0].Items[1].CellRect.Y < mixed[0].Items[2].CellRect.Y,
            "print_one_large_two_small_stacks_the_small_cells");

        // 넉 장은 2×2 입니다.
        IReadOnlyList<PrintPackagePageLayout> quad = PrintPackageLayout.Make(
            [.. Enumerable.Repeat(new PrintSizeMm(3000, 2000), 4)],
            a4,
            twoUp with { PictureTemplate = PrintPicturePackageTemplate.FourUp })!;
        Check(quad[0].Items.Count == 4, "print_four_up_holds_four");
        Check(
            quad[0].Items[2].CellRect.Y > quad[0].Items[0].CellRect.Y &&
                Math.Abs(quad[0].Items[2].CellRect.X - quad[0].Items[0].CellRect.X) < 0.001,
            "print_four_up_is_two_by_two");

        // 다섯 장이면 판이 둘입니다.
        IReadOnlyList<PrintPackagePageLayout> spill = PrintPackageLayout.Make(
            [.. Enumerable.Repeat(new PrintSizeMm(3000, 2000), 5)],
            a4,
            twoUp with { PictureTemplate = PrintPicturePackageTemplate.FourUp })!;
        Check(spill.Count == 2, "print_picture_package_spills_to_a_second_page");
    }

    /// <summary>
    /// 캡션은 칸 아래를 차지하고 사진은 그만큼 물러납니다. 재단선은 판을 넘지 않습니다 —
    /// 넘은 선은 잘려 반쪽만 남습니다.
    /// </summary>
    private static void VerifyPrintCaptionsAndCropMarks(PrintCompositionSettings a4)
    {
        PrintPackageSettings plain = new() { ContactRows = 2, ContactColumns = 2 };
        PrintPackageSettings captioned = plain with
        {
            CaptionMode = PrintPackageCaptionMode.FileName,
            CaptionHeightMm = 6,
        };
        PrintSizeMm[] four = [.. Enumerable.Repeat(new PrintSizeMm(3000, 2000), 4)];
        PrintPackageItemLayout without = PrintPackageLayout.Make(four, a4, plain)![0].Items[0];
        PrintPackageItemLayout with = PrintPackageLayout.Make(four, a4, captioned)![0].Items[0];

        Check(without.CaptionRect is null, "print_no_caption_leaves_no_room");
        Check(with.CaptionRect is not null, "print_caption_gets_a_rect");
        Check(
            Math.Abs(with.CellRect.Height - without.CellRect.Height) < 0.001,
            "print_caption_does_not_change_the_cell");
        Check(
            with.ImageRect.Height < without.ImageRect.Height,
            "print_caption_pushes_the_photo_up");
        Check(
            with.CaptionRect!.Value.MaxY <= with.CellRect.MaxY + 0.001 &&
                with.CaptionRect.Value.MinY >= with.ImageRect.MaxY - 0.001,
            "print_caption_sits_below_the_photo");

        // 캡션이 칸보다 크면 절반까지만 씁니다 — 사진이 사라지면 안 됩니다.
        PrintPackageItemLayout huge = PrintPackageLayout.Make(
            four,
            a4,
            captioned with { CaptionHeightMm = 40 })![0].Items[0];
        Check(
            huge.CaptionRect!.Value.Height <= (huge.CellRect.Height / 2) + 0.001 &&
                huge.ImageRect.Height > 1,
            "print_caption_never_eats_the_whole_cell");

        // 재단선은 칸마다 여덟 개이되, 판을 넘는 선은 짧아집니다.
        PrintPackagePageLayout marked = PrintPackageLayout.Make(
            four,
            a4,
            plain with { ShowsCropMarks = true, CropMarkLengthMm = 4 })![0];
        Check(marked.CropMarks.Count > 0, "print_crop_marks_appear");
        Check(
            marked.CropMarks.All(segment =>
                segment.StartX >= marked.ContentRect.MinX - 0.001 &&
                segment.EndX <= marked.ContentRect.MaxX + 0.001 &&
                segment.StartY >= marked.ContentRect.MinY - 0.001 &&
                segment.EndY <= marked.ContentRect.MaxY + 0.001),
            "print_crop_marks_stay_inside_the_page");
        Check(
            PrintPackageLayout.Make(four, a4, plain)![0].CropMarks.Count == 0,
            "print_crop_marks_are_off_by_default");
    }


    /// <summary>
    /// 설정의 기본 스캔 회전이 실제로 카탈로그에 적히는지. 적히지 않으면 그 설정은 눌러도
    /// 아무 일이 없는 컨트롤이 됩니다.
    /// </summary>
}
