using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Shell.Print;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 인화 워터마크(촬영 정보 띠)입니다. macOS <c>PrintWatermarkTests</c> · <c>PrintWatermarkSettingsTests</c>
/// 와 같은 사례를 같은 값으로 봅니다. 합성 화소만 씁니다.
/// </summary>
internal static class PrintWatermarkTests
{
    public static void Run()
    {
        VerifyBandsAreAddedOutsideThePhoto();
        VerifyExposureLine();
        VerifyBandLayoutFitsAndCenters();
        VerifyTopPlacementFallsBackWithoutTopBand();
        VerifyHistogramAndBlur();
        VerifyPreferencesTemplatesAndPaper();
    }

    private static readonly PrintWatermarkTextWidth FixedWidth =
        (text, fontSize, bold) => text.Length * fontSize * (bold ? 0.6 : 0.5);

    private static void VerifyBandsAreAddedOutsideThePhoto()
    {
        PrintWatermarkSettings settings = new() { IsEnabled = true, BandHeightRatio = 0.13 };
        PrintWatermarkFrameLayout? bottom = PrintWatermarkFrameLayout.Make(new PrintSizeMm(300, 200), settings);
        Check(bottom is { BandHeight: 26 } &&
              bottom.FrameSize == new PrintSizeMm(300, 226) &&
              bottom.ImageRect == new PrintRect(0, 0, 300, 200) &&
              bottom.BottomBand == new PrintRect(0, 200, 300, 26) &&
              bottom.TopBand is null,
            "watermark_bottom_band_is_added_below_without_cropping");

        PrintWatermarkFrameLayout? both = PrintWatermarkFrameLayout.Make(
            new PrintSizeMm(200, 300), settings with { AddsTopBand = true });
        Check(both is { BandHeight: 26 } &&
              both.FrameSize == new PrintSizeMm(200, 352) &&
              both.TopBand == new PrintRect(0, 0, 200, 26) &&
              both.ImageRect == new PrintRect(0, 26, 200, 300),
            "watermark_top_band_matches_the_bottom_height");

        Check(PrintWatermarkFrameLayout.Make(new PrintSizeMm(300, 200), settings with { BandHeightRatio = 0.5 }) is null,
            "watermark_band_ratio_outside_range_is_refused");
    }

    private static void VerifyExposureLine()
    {
        PrintWatermarkSettings settings = new()
        {
            FocalLength = "100",
            Aperture = "7.1",
            ShutterSpeed = "1/125",
            Iso = "160",
        };
        Check(settings.ExposureLine == "100mm f/7.1 1/125 ISO160", "watermark_exposure_adds_units",
            () => settings.ExposureLine);
        foreach (string speed in new[] { "1/125", "2", "0.5", "B", "" })
        {
            Check(PrintWatermarkFormat.ShutterSpeed(" " + speed + " ") == speed,
                "watermark_shutter_has_no_added_symbol_" + speed);
        }
        PrintWatermarkSettings typed = settings with { FocalLength = "28-75mm", Aperture = "f/2", ShutterSpeed = "B", Iso = "" };
        Check(typed.ExposureLine == "28-75mm f/2 B", "watermark_exposure_keeps_typed_units", () => typed.ExposureLine);
        Check(PrintWatermarkFormat.ExposureTime(1.0 / 125) == "1/125" &&
              PrintWatermarkFormat.ExposureTime(2) == "2" &&
              PrintWatermarkFormat.Number(7.10) == "7.1",
            "watermark_number_formatting_matches_macos");

        PrintWatermarkSettings blank = new() { Aperture = "5.6" };
        PrintWatermarkSettings? prepared = new PrintPreferences
        {
            LayoutMode = PrintLayoutMode.Watermark,
            Watermark = blank,
        }.Composition().ActiveWatermark;
        Check(prepared is not null && prepared.CameraName.Length == 0 && prepared.LensName.Length == 0 &&
              prepared.ExposureLine == "f/5.6" && prepared.CaptureDate.Length == 0,
            "watermark_blank_fields_stay_empty");
    }

    private static void VerifyBandLayoutFitsAndCenters()
    {
        PrintWatermarkSettings settings = new()
        {
            IsEnabled = true,
            CameraName = "Canon EOS R5",
            LensName = "Canon EF 100mm f/2.8L Macro IS USM",
            FocalLength = "100",
            Aperture = "7.1",
            ShutterSpeed = "1/125",
            Iso = "160",
            CaptureDate = "2022/06/07 15:21:39",
            ShowsHistogram = true,
            UserName = "habin song",
        };
        PrintWatermarkBandDrawing wide = PrintWatermarkBandLayout.Bottom(settings, 1800, 156, 4.0, true, FixedWidth);
        Check(wide.Texts.Count == 5 && wide.Logo is not null && wide.Separator is not null && wide.Histogram is not null,
            "watermark_bottom_band_places_every_item", () => wide.Texts.Count.ToString());
        double inset = PrintWatermarkMetrics.HorizontalInset * 156;
        Check(wide.Texts.All(text => text.X >= inset - 1e-6 && text.X + text.Width <= 1800 - inset + 1e-6),
            "watermark_items_stay_inside_the_band_insets");
        PrintRect histogram = wide.Histogram!.Value;
        PrintWatermarkTextItem name = wide.Texts.Single(text => text.Text == "habin song");
        Check(Near(histogram.X + (histogram.Width / 2), 900) && Near(name.X + (name.Width / 2), 900) &&
              histogram.MaxY < name.Y,
            "watermark_center_slot_centers_name_and_histogram_without_overlap");
        Check(!Overlaps(wide), "watermark_wide_band_has_no_overlap");

        // 세로 사진처럼 좁은 띠에서는 전체를 같은 비율로 줄여 겹치지 않게 합니다.
        PrintWatermarkBandDrawing narrow = PrintWatermarkBandLayout.Bottom(settings, 1000, 156, 4.0, true, FixedWidth);
        Check(narrow.Texts[0].FontSize < wide.Texts[0].FontSize && !Overlaps(narrow),
            "watermark_narrow_band_scales_down_without_overlap");
    }

    private static void VerifyTopPlacementFallsBackWithoutTopBand()
    {
        PrintWatermarkSettings settings = new()
        {
            IsEnabled = true,
            AddsTopBand = true,
            ShowsHistogram = true,
            HistogramPlacement = PrintWatermarkPlacement.TopLeading,
            UserName = "Me",
            UserNamePlacement = PrintWatermarkPlacement.TopTrailing,
        };
        Check(PrintWatermarkBandLayout.HasTopItems(settings, hasHistogram: true), "watermark_top_items_present");
        PrintWatermarkBandDrawing top = PrintWatermarkBandLayout.Top(settings, 1200, 100, true, FixedWidth);
        Check(top.Histogram is { } histogram && histogram.X < 600 &&
              top.Texts.Single().X > 600,
            "watermark_top_slots_go_left_and_right");
        PrintWatermarkBandDrawing bottomWithTop = PrintWatermarkBandLayout.Bottom(settings, 1200, 100, null, true, FixedWidth);
        Check(bottomWithTop.Histogram is null && bottomWithTop.Texts.Count == 0,
            "watermark_bottom_band_is_empty_when_items_go_up");

        PrintWatermarkSettings centered = settings with
        {
            HistogramPlacement = PrintWatermarkPlacement.TopCenter,
            UserNamePlacement = PrintWatermarkPlacement.TopCenter,
        };
        PrintWatermarkBandDrawing topCenter = PrintWatermarkBandLayout.Top(centered, 1200, 100, true, FixedWidth);
        Check(topCenter.Histogram is { } centerHistogram &&
              Near(centerHistogram.X + (centerHistogram.Width / 2), 600) &&
              Near(topCenter.Texts.Single().X + (topCenter.Texts.Single().Width / 2), 600) &&
              centerHistogram.MaxY < topCenter.Texts.Single().Y,
            "watermark_top_center_slot_centers_the_name");
        foreach (PrintWatermarkPlacement placement in Enum.GetValues<PrintWatermarkPlacement>())
        {
            PrintWatermarkSettings together = settings with { HistogramPlacement = placement, UserNamePlacement = placement };
            PrintWatermarkBandDrawing drawing = placement == PrintWatermarkPlacement.BottomCenter
                ? PrintWatermarkBandLayout.Bottom(together, 1200, 100, null, true, FixedWidth)
                : PrintWatermarkBandLayout.Top(together, 1200, 100, true, FixedWidth);
            PrintWatermarkTextItem placed = drawing.Texts.Single();
            Check(drawing.Histogram is { } bars && Near(placed.X + (placed.Width / 2), bars.X + (bars.Width / 2)) &&
                  !Overlaps(drawing), "watermark_name_centered_at_" + placement);
        }

        PrintWatermarkSettings noTop = settings with { AddsTopBand = false };
        Check(!PrintWatermarkBandLayout.HasTopItems(noTop, hasHistogram: true) &&
              noTop.EffectivePlacement(PrintWatermarkPlacement.TopLeading) == PrintWatermarkPlacement.BottomCenter &&
              PrintWatermarkBandLayout.Bottom(noTop, 1200, 100, null, true, FixedWidth).Histogram is not null,
            "watermark_top_placement_falls_back_to_bottom_center");

        PrintWatermarkSettings ink = new() { Background = PrintWatermarkBackground.White, BlurTextInk = PrintWatermarkInk.White };
        Check(ink.TextInk == PrintWatermarkInk.Black && ink.HistogramInk == PrintWatermarkInk.Black &&
              (ink with { Background = PrintWatermarkBackground.Black }).TextInk == PrintWatermarkInk.White &&
              (ink with { Background = PrintWatermarkBackground.Blur }).TextInk == PrintWatermarkInk.White,
            "watermark_ink_follows_the_background_rule");
    }

    private static void VerifyHistogramAndBlur()
    {
        // 왼쪽 1/4 검정, 나머지 흰색.
        const int width = 40;
        const int height = 10;
        byte[] bgra = new byte[width * height * 4];
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                int at = ((y * width) + x) * 4;
                byte level = x < 10 ? (byte)0 : (byte)255;
                bgra[at] = level;
                bgra[at + 1] = level;
                bgra[at + 2] = level;
                bgra[at + 3] = 255;
            }
        }
        double[] columns = PrintWatermarkPixels.HistogramColumns(bgra, width, height);
        Check(columns.Length == 32 && Near(columns[31], 1) && Near(columns[0], 1.0 / 3.0) &&
              columns[1..31].Sum() < 1e-9,
            "watermark_histogram_counts_display_brightness");

        byte[] red = new byte[16 * 8 * 4];
        for (int index = 0; index < red.Length; index += 4)
        {
            red[index + 2] = 230;
            red[index + 3] = 255;
        }
        PrintWatermarkPixels.BlurField? blur = PrintWatermarkPixels.Blur(red, 16, 8);
        (double r, double g, double b) = blur!.SampleFill(160, 120, 80, 115);
        Check(r > 0.85 && g < 0.05 && b < 0.05, "watermark_blur_fill_keeps_the_photo_color",
            () => $"{r:F3} {g:F3} {b:F3}");

        (byte[] small, int smallWidth, int smallHeight) = PrintWatermarkPixels.Downscale(new byte[1000 * 500 * 4], 1000, 500, 256);
        Check(smallWidth == 256 && smallHeight == 128 && small.Length == 256 * 128 * 4, "watermark_reference_downscales_to_256");
    }

    private static void VerifyPreferencesTemplatesAndPaper()
    {
        PrintWatermarkSettings watermark = new()
        {
            IsEnabled = true,
            Background = PrintWatermarkBackground.Blur,
            BlurTextInk = PrintWatermarkInk.Black,
            AddsTopBand = true,
            CameraName = "Body",
            LensName = "Lens",
            FocalLength = "50",
            Aperture = "2",
            ShutterSpeed = "1/60",
            Iso = "400",
            CaptureDate = "2026/10/27",
            ShowsLogo = true,
            LogoSourcePath = @"C:\Logos\brand.png",
            ShowsHistogram = true,
            HistogramPlacement = PrintWatermarkPlacement.TopCenter,
            UserName = "Me",
            UserNamePlacement = PrintWatermarkPlacement.TopTrailing,
        };
        PrintPreferences print = new() { LayoutMode = PrintLayoutMode.Watermark, Watermark = watermark };
        Check(print.Composition().Watermark == watermark, "watermark_reaches_its_own_layout");
        Check((print with { LayoutMode = PrintLayoutMode.ContactSheet }).Composition().Watermark is null,
            "watermark_never_reaches_package_layouts");
        Check((print with { Watermark = watermark with { IsEnabled = false } }).Composition().ActiveWatermark is not null,
            "watermark_layout_is_the_enable_control");
        foreach (PrintLayoutMode mode in Enum.GetValues<PrintLayoutMode>().Where(mode => mode != PrintLayoutMode.Watermark))
        {
            Check((print with { LayoutMode = mode }).Composition().Watermark is null,
                "watermark_absent_in_" + mode);
        }
        Check((print with { Watermark = watermark with { BandHeightRatio = 9 } }).Normalize().Watermark == new PrintWatermarkSettings(),
            "watermark_out_of_range_file_value_resets");

        // 템플릿: 종이 색과 워터마크(로고 포함)를 담고, 예전 템플릿은 지금 값을 둡니다.
        PrintPreferences saved = print with { SheetBackground = PrintSheetBackground.Black };
        PrintLayoutTemplateSettings template = PrintLayoutTemplateSettings.From(saved);
        string json = JsonSerializer.Serialize(template);
        PrintLayoutTemplateSettings restored = JsonSerializer.Deserialize<PrintLayoutTemplateSettings>(json)!;
        Check(restored.Watermark == watermark && restored.SheetBackground == PrintSheetBackground.Black && restored.IsValid,
            "watermark_template_round_trip_keeps_logo_and_sheet");
        // 글·로고 켜짐·로고 경로·자리까지 그대로 다시 씁니다. 로고 그림 바이트는 저장하지 않습니다
        // (그릴 때마다 경로에서 읽고, 지워졌으면 로고만 빠집니다).
        Check(restored.Watermark is { CameraName: "Body", CaptureDate: "2026/10/27", Iso: "400", ShowsLogo: true } w &&
              w.LogoSourcePath == @"C:\Logos\brand.png" && w.LogoPng is null &&
              w.HistogramPlacement == PrintWatermarkPlacement.TopCenter &&
              !json.Contains("LogoPng", StringComparison.Ordinal),
            "watermark_template_keeps_every_component_but_not_logo_bytes");
        Check((watermark with { LogoPng = [9, 9] }) == watermark, "watermark_logo_bytes_do_not_change_equality");
        PrintPreferences applied = restored.ApplyTo(new PrintPreferences());
        Check(applied.LayoutMode == PrintLayoutMode.Watermark && applied.Watermark == watermark && applied.SheetBackground == PrintSheetBackground.Black,
            "watermark_template_apply_sets_sheet_and_watermark");
        PrintLayoutTemplateSettings legacy = template with { SheetBackground = null, Watermark = null };
        PrintPreferences current = new() { SheetBackground = PrintSheetBackground.Gray, Watermark = watermark };
        PrintPreferences keep = legacy.ApplyTo(current);
        Check(keep.SheetBackground == PrintSheetBackground.Gray && keep.Watermark == watermark,
            "watermark_legacy_template_keeps_current_values");

        // "사진 비율" 용지는 띠까지 더한 한 장의 비율을 따릅니다.
        PrintCompositionSettings paper = new()
        {
            PaperSize = PrintPaperSize.PhotoRatio,
            MarginMm = 0,
            Dpi = 72,
            PhotoAspectRatio = 1.5,
            Watermark = new PrintWatermarkSettings { IsEnabled = true, BandHeightRatio = 0.1 },
        };
        (PrintSizeMm unit, PrintWatermarkFrameLayout? frame, PrintCompositionSettings page) =
            paper.PlaceUnit(new PrintSizeMm(1000, 800));
        Check(frame is not null && unit == new PrintSizeMm(1000, 880) &&
              Near(page.PhotoAspectRatio ?? 0, 1000.0 / 880.0),
            "watermark_photo_ratio_paper_follows_framed_photo");
        PrintCompositionLayout? layout = PrintCompositionLayout.Make(unit, page);
        Check(layout is not null && Math.Abs((layout.CanvasSize.Width / layout.CanvasSize.Height) - (1000.0 / 880.0)) < 0.01,
            "watermark_photo_ratio_canvas_matches_unit");
    }

    private static bool Overlaps(PrintWatermarkBandDrawing drawing)
    {
        List<PrintRect> rectangles = [.. drawing.Texts.Select(text => new PrintRect(
            text.X, text.Y, text.Width, text.FontSize * PrintWatermarkMetrics.LineHeightFactor))];
        if (drawing.Logo is { } logo) { rectangles.Add(logo); }
        if (drawing.Histogram is { } histogram) { rectangles.Add(histogram); }
        if (drawing.Separator is { } separator) { rectangles.Add(separator); }
        for (int first = 0; first < rectangles.Count; ++first)
        {
            for (int second = first + 1; second < rectangles.Count; ++second)
            {
                PrintRect a = rectangles[first];
                PrintRect b = rectangles[second];
                if (Math.Min(a.MaxX, b.MaxX) - Math.Max(a.X, b.X) > 1e-6 &&
                    Math.Min(a.MaxY, b.MaxY) - Math.Max(a.Y, b.Y) > 1e-6)
                {
                    return true;
                }
            }
        }
        return false;
    }

}
