using Negaflow.Shell;
using Negaflow.Shell.Print;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 사용자 패키지와 여러 장 고르기입니다. macOS
/// <c>AppModel.selectFrame(_:orderedFrameIDs:modifiers:)</c> 와
/// <c>PrintWorkspaceSettingsStore.prepareDefaultCustomPackage(sourceCount:)</c> 를 옮긴
/// 것이므로, 그 규칙을 여기에 고정합니다.
/// </summary>
internal static class PrintCustomPackageTests
{
    private static readonly string[] Order = ["a", "b", "c", "d", "e"];

    public static void Run()
    {
        VerifyPlainClickKeepsOne();
        VerifyToggleAddsAndRemoves();
        VerifyShiftTakesTheRange();
        VerifyShiftWithoutAnchorFallsBackToOne();
        VerifySeedGivesEveryPhotoACell();
        VerifySeedLeavesTouchedLayoutAlone();
        VerifyClampKeepsCellsInsideTheSelection();
        VerifyIccJudgement();
        VerifyRectClamping();
        VerifyPresentationStyles();
        VerifyLayoutTemplates();
        VerifyProofMedia();
        VerifyProofRoundTripKeepsRows();
        VerifyGamutMarkLandsOnTheRightRows();
        VerifyCollapsedFoldersSurviveRestart();
    }

    /// <summary>아무것도 누르지 않으면 그 한 장만 남습니다.</summary>
    private static void VerifyPlainClickKeepsOne()
    {
        LibraryFrameSelectionCommand next = LibraryFrameSelectionCommand.Apply(
            "c", Order, ["a", "b"], "a", "a", LibrarySelectionModifiers.None);
        Check(next.SelectedFrameIds.Count == 1 && next.SelectedFrameIds[0] == "c",
            "selection_plain_click_keeps_one");
        Check(next.ActiveFrameId == "c" && next.AnchorFrameId == "c",
            "selection_plain_click_moves_the_anchor");
    }

    /// <summary>Ctrl 은 누른 칸 하나만 더하고 뺍니다. 기준점은 그 칸이 됩니다.</summary>
    private static void VerifyToggleAddsAndRemoves()
    {
        LibraryFrameSelectionCommand added = LibraryFrameSelectionCommand.Apply(
            "c", Order, ["a"], "a", "a", LibrarySelectionModifiers.Toggle);
        Check(added.SelectedFrameIds.Count == 2 &&
            added.SelectedFrameIds.Contains("a") &&
            added.SelectedFrameIds.Contains("c"),
            "selection_toggle_adds");
        Check(added.ActiveFrameId == "c" && added.AnchorFrameId == "c",
            "selection_toggle_activates_what_it_added");

        LibraryFrameSelectionCommand removed = LibraryFrameSelectionCommand.Apply(
            "c", Order, ["a", "c"], "c", "c", LibrarySelectionModifiers.Toggle);
        Check(removed.SelectedFrameIds.Count == 1 && removed.SelectedFrameIds[0] == "a",
            "selection_toggle_removes");
        // 뺀 칸이 활성이었으므로 남은 것 가운데 화면 차례가 가장 앞선 것으로 옮깁니다.
        Check(removed.ActiveFrameId == "a", "selection_toggle_moves_the_active_frame");
    }

    /// <summary>Shift 는 기준점에서 누른 칸까지를 통째로 고릅니다.</summary>
    private static void VerifyShiftTakesTheRange()
    {
        LibraryFrameSelectionCommand next = LibraryFrameSelectionCommand.Apply(
            "d", Order, ["b"], "b", "b", LibrarySelectionModifiers.Shift);
        Check(next.SelectedFrameIds.Count == 3 &&
            next.SelectedFrameIds[0] == "b" &&
            next.SelectedFrameIds[1] == "c" &&
            next.SelectedFrameIds[2] == "d",
            "selection_shift_takes_the_range");
        // 기준점은 그대로 — 이어서 Shift 를 누르면 같은 자리에서 범위가 자랍니다.
        Check(next.AnchorFrameId == "b" && next.ActiveFrameId == "d",
            "selection_shift_keeps_the_anchor");

        LibraryFrameSelectionCommand backwards = LibraryFrameSelectionCommand.Apply(
            "a", Order, ["d"], "d", "d", LibrarySelectionModifiers.Shift);
        Check(backwards.SelectedFrameIds.Count == 4 && backwards.SelectedFrameIds[0] == "a",
            "selection_shift_works_backwards");
    }

    /// <summary>기준점이 없으면 Shift 도 한 장 고르기로 떨어집니다.</summary>
    private static void VerifyShiftWithoutAnchorFallsBackToOne()
    {
        LibraryFrameSelectionCommand next = LibraryFrameSelectionCommand.Apply(
            "c", Order, [], null, null, LibrarySelectionModifiers.Shift);
        Check(next.SelectedFrameIds.Count == 1 && next.SelectedFrameIds[0] == "c",
            "selection_shift_without_anchor_keeps_one");
    }

    /// <summary>
    /// 사용자 패키지를 켜면 고른 사진마다 칸이 하나씩 생깁니다. macOS 와 같은 열·행 셈입니다.
    /// </summary>
    private static void VerifySeedGivesEveryPhotoACell()
    {
        IReadOnlyList<PrintCustomPackageItem>? seeded =
            PrintCustomPackageSeed.Prepare(PrintCustomPackageSeed.Default, 5);
        Check(seeded is { Count: 5 }, "custom_seed_gives_every_photo_a_cell");
        Check(seeded![0].SourceIndex == 0 && seeded[4].SourceIndex == 4,
            "custom_seed_points_each_cell_at_its_own_photo");
        // ceil(sqrt(5)) = 3 열, ceil(5/3) = 2 행.
        Check(Math.Abs(seeded[0].NormalizedRect.Width - (1.0 / 3)) < 1e-9 &&
            Math.Abs(seeded[0].NormalizedRect.Height - 0.5) < 1e-9,
            "custom_seed_uses_the_mac_grid");
        Check(seeded.All(item => item.NormalizedRect.MaxX <= 1.000_001 &&
            item.NormalizedRect.MaxY <= 1.000_001 && item.IsValid),
            "custom_seed_stays_on_the_page");
    }

    /// <summary>손댄 배치는 덮어쓰지 않습니다.</summary>
    private static void VerifySeedLeavesTouchedLayoutAlone()
    {
        IReadOnlyList<PrintCustomPackageItem> touched =
            [new PrintCustomPackageItem(0, new PrintRect(0.1, 0.1, 0.4, 0.4))];
        Check(PrintCustomPackageSeed.Prepare(touched, 4) is null,
            "custom_seed_leaves_a_touched_layout_alone");
        Check(PrintCustomPackageSeed.Prepare(PrintCustomPackageSeed.Default, 1) is null,
            "custom_seed_does_nothing_for_one_photo");
    }

    /// <summary>
    /// 칸이 없는 사진을 가리키면 배치가 통째로 거절돼 판이 사라집니다. 사진 수 안으로
    /// 당겨야 합니다.
    /// </summary>
    private static void VerifyClampKeepsCellsInsideTheSelection()
    {
        IReadOnlyList<PrintCustomPackageItem> grid = PrintCustomPackageSeed.Grid(4);
        IReadOnlyList<PrintCustomPackageItem>? clamped = PrintCustomPackageSeed.Clamp(grid, 1);
        Check(clamped is { Count: 4 } && clamped.All(item => item.SourceIndex == 0),
            "custom_clamp_pulls_cells_into_range");
        Check(PrintCustomPackageSeed.Clamp(grid, 4) is null,
            "custom_clamp_does_nothing_when_every_cell_fits");
        // 당긴 배치는 그대로 놓을 수 있어야 합니다 - 아니면 판이 또 사라집니다.
        Check(clamped!.All(item => item.IsValid), "custom_clamp_keeps_cells_valid");
    }

    /// <summary>
    /// 인화소 프로파일은 표(LUT) 기반이 대부분입니다. macOS 와 같이 <b>RGB 출력</b>이면
    /// 받아들여야 합니다.
    /// </summary>
    private static void VerifyIccJudgement()
    {
        Check(PrintIccProfile.IsRgbOutput(Header("prtr", "RGB ")),
            "icc_accepts_an_rgb_printer_profile");
        Check(PrintIccProfile.IsRgbOutput(Header("mntr", "RGB ")),
            "icc_accepts_an_rgb_display_profile");
        Check(!PrintIccProfile.IsRgbOutput(Header("prtr", "CMYK")),
            "icc_rejects_cmyk");
        Check(!PrintIccProfile.IsRgbOutput(Header("scnr", "RGB ")),
            "icc_rejects_an_input_only_profile");
        Check(!PrintIccProfile.IsRgbOutput(new byte[64]), "icc_rejects_a_short_header");
    }

    /// <summary>검사에 쓰는 128 바이트 머리말입니다.</summary>
    private static byte[] Header(string deviceClass, string colorSpace)
    {
        byte[] header = new byte[128];
        System.Text.Encoding.ASCII.GetBytes(deviceClass).CopyTo(header, 12);
        System.Text.Encoding.ASCII.GetBytes(colorSpace).CopyTo(header, 16);
        return header;
    }
    /// <summary>
    /// 슬라이더로 칸을 판 밖으로 내보낼 수 없어야 합니다 — 하나라도 나가면 배치가 통째로
    /// 거절돼 미리보기가 빈 종이가 됩니다. macOS `customRectBinding` 규칙입니다.
    /// </summary>
    private static void VerifyRectClamping()
    {
        PrintRect cell = new(0.3, 0.3, 0.4, 0.4);
        PrintRect movedX = PrintCustomRect.UpdateCell(cell, PrintRectComponent.X, 0.95);
        Check(Math.Abs(movedX.X - 0.6) < 1e-9 && movedX.MaxX <= 1.000_001,
            "custom_rect_x_stops_at_the_edge");
        PrintRect movedY = PrintCustomRect.UpdateCell(cell, PrintRectComponent.Y, 0.95);
        Check(Math.Abs(movedY.Y - 0.6) < 1e-9 && movedY.MaxY <= 1.000_001,
            "custom_rect_y_stops_at_the_edge");
        // 100% 는 정말로 용지 전체여야 합니다 — 원점을 밀어 줍니다.
        PrintRect full = PrintCustomRect.UpdateCell(cell, PrintRectComponent.Width, 1);
        Check(Math.Abs(full.Width - 1) < 1e-9 && Math.Abs(full.X) < 1e-9,
            "custom_rect_width_can_reach_the_whole_page");
        PrintRect tall = PrintCustomRect.UpdateCell(cell, PrintRectComponent.Height, 1);
        Check(Math.Abs(tall.Height - 1) < 1e-9 && Math.Abs(tall.Y) < 1e-9,
            "custom_rect_height_can_reach_the_whole_page");
        // 0 으로 줄이면 다시 잡을 수 없습니다.
        PrintRect tiny = PrintCustomRect.UpdateCell(cell, PrintRectComponent.Width, 0);
        Check(Math.Abs(tiny.Width - PrintCustomRect.MinimumCellSize) < 1e-9,
            "custom_rect_keeps_a_minimum_size");
        // 어떤 값을 넣어도 판 안에 있어야 합니다.
        foreach (double value in new[] { -1.0, 0.0, 0.5, 1.0, 2.0 })
        {
            foreach (PrintRectComponent component in Enum.GetValues<PrintRectComponent>())
            {
                PrintRect next = PrintCustomRect.UpdateCell(cell, component, value);
                Check(new PrintCustomPackageItem(0, next).IsValid, "custom_rect_stays_placeable");
            }
        }
        PrintRect caption = new(0.5, 0.5, 0.4, 0.05);
        PrintRect wide = PrintCustomRect.UpdateCaption(caption, PrintRectComponent.Width, 1);
        Check(Math.Abs(wide.Width - 0.5) < 1e-9, "caption_rect_width_stops_at_the_edge");
    }
    /// <summary>
    /// 시아노타입 · 유리건판 · 젤라틴 실버입니다. macOS
    /// <c>PrintPresentationRenderer.apply(to:style:)</c> 와 같은 결과여야 합니다 —
    /// 시아노타입은 흑백 뒤 두 색 사이 보간(<c>CIFalseColor</c>), 유리건판은 흑백 뒤 반전,
    /// 젤라틴 실버는 흑백입니다.
    /// </summary>
    private static void VerifyPresentationStyles()
    {
        Check(!PrintPresentationFilter.Transforms(PrintPresentationStyle.Standard),
            "presentation_standard_touches_nothing");
        // 순빨강 BGRA. 밝기 = 0.2126.
        byte[] gelatin = [0, 0, 255, 255];
        PrintPresentationFilter.Apply(gelatin, PrintPresentationStyle.GelatinSilver);
        Check(gelatin[0] == gelatin[1] && gelatin[1] == gelatin[2],
            "presentation_gelatin_is_grey");
        Check(Math.Abs(gelatin[2] - Math.Round(0.2126 * 255)) <= 1,
            "presentation_gelatin_uses_rec709_luma");

        byte[] plate = [0, 0, 255, 255];
        PrintPresentationFilter.Apply(plate, PrintPresentationStyle.GlassPlate);
        Check(Math.Abs(plate[2] - Math.Round((1 - 0.2126) * 255)) <= 1,
            "presentation_glass_plate_inverts");

        // 검정과 흰색은 시아노타입의 두 끝 색이 되어야 합니다.
        byte[] shadow = [0, 0, 0, 255];
        PrintPresentationFilter.Apply(shadow, PrintPresentationStyle.Cyanotype);
        Check(Math.Abs(shadow[2] - Math.Round(0.02 * 255)) <= 1 &&
            Math.Abs(shadow[1] - Math.Round(0.10 * 255)) <= 1 &&
            Math.Abs(shadow[0] - Math.Round(0.36 * 255)) <= 1,
            "presentation_cyanotype_shadow_matches_mac");
        byte[] highlight = [255, 255, 255, 255];
        PrintPresentationFilter.Apply(highlight, PrintPresentationStyle.Cyanotype);
        Check(Math.Abs(highlight[2] - Math.Round(0.96 * 255)) <= 1 &&
            Math.Abs(highlight[1] - Math.Round(0.98 * 255)) <= 1 &&
            highlight[0] == 255,
            "presentation_cyanotype_highlight_matches_mac");
        // 시아노타입은 늘 파랑이 가장 큽니다 — 철염 단색 관계입니다.
        byte[] middle = [128, 60, 200, 255];
        PrintPresentationFilter.Apply(middle, PrintPresentationStyle.Cyanotype);
        Check(middle[0] > middle[1] && middle[1] > middle[2],
            "presentation_cyanotype_stays_blue");
    }
    /// <summary>
    /// 레이아웃 템플릿입니다. macOS <c>PrintLayoutTemplateStore</c> 와 같이 한 파일에 담고,
    /// 이름이 겹치면(대소문자 무시) 받지 않으며, 100 개를 넘지 않습니다.
    /// </summary>
    private static void VerifyLayoutTemplates()
    {
        string file = Path.Combine(
            Path.GetTempPath(),
            "negaflow-print-templates-" + Guid.NewGuid().ToString("N") + ".json");
        try
        {
            PrintPreferences print = new() { LayoutMode = PrintLayoutMode.ContactSheet };
            PrintLayoutTemplateSettings settings = PrintLayoutTemplateSettings.From(print);
            PrintLayoutTemplateStore store = new(file);
            Check(store.CanModify && store.Templates.Count == 0,
                "template_store_starts_empty");
            Check(store.Add("스튜디오 A", settings) is not null, "template_store_adds");
            // 이름이 겹치면 받지 않습니다 — 대소문자는 무시합니다.
            Check(store.Add("스튜디오 A", settings) is null, "template_store_rejects_duplicates");
            Check(store.Add("  ", settings) is null, "template_store_rejects_blank_names");

            // 다시 읽어도 그대로 있어야 합니다.
            PrintLayoutTemplateStore reopened = new(file);
            Check(reopened.Templates.Count == 1 && reopened.Templates[0].Name == "스튜디오 A",
                "template_store_round_trips");
            Check(reopened.Delete(reopened.Templates[0].Id), "template_store_deletes");
            Check(new PrintLayoutTemplateStore(file).Templates.Count == 0,
                "template_store_delete_survives_reload");
        }
        finally
        {
            try
            {
                File.Delete(file);
            }
            catch (IOException)
            {
            }
        }
    }
    /// <summary>
    /// 인화소 프로파일의 용지 흰색·잉크 검정입니다. macOS
    /// <c>SoftProof.mediaTags(fromICCData:)</c> 와 같은 태그 판독이어야 합니다 — 표(LUT) 기반
    /// 프로파일에서도 값이 나와야 용지와 사진이 실제로 바뀝니다.
    /// </summary>
    private static void VerifyProofMedia()
    {
        // wtpt · bkpt 만 있는 최소 프로파일을 만듭니다.
        byte[] icc = BuildProfile(
            white: [0.8593, 0.8916, 0.7114],
            black: [0.0217, 0.0222, 0.0178]);
        (double[] White, double[] Black)? media = PrintIccProfile.ReadMedia(icc);
        Check(media is not null, "proof_media_reads_lut_profiles");
        // macOS: `clamp(XYZ / D50, 0, 1.2)` — D50 = (0.9642, 1, 0.8249).
        // s15Fixed16 로 담았다 꺼내므로 1/65536 만큼의 반올림이 남습니다.
        Check(Math.Abs(media!.Value.White[0] - (0.8593 / 0.9642)) < 1e-4 &&
            Math.Abs(media.Value.White[1] - 0.8916) < 1e-4 &&
            Math.Abs(media.Value.White[2] - (0.7114 / 0.8249)) < 1e-4,
            "proof_media_paper_white_matches_mac");
        Check(Math.Abs(media.Value.Black[1] - 0.0222) < 1e-4,
            "proof_media_black_ink_matches_mac");
        Check(PrintIccProfile.ReadMedia(new byte[64]) is null, "proof_media_rejects_a_stub");

        // 이 값이면 화소가 실제로 눌려야 합니다.
        Negaflow.Interop.SoftProofSettings proof = new(
            true,
            Negaflow.Interop.SoftProofSimulation.PaperAndBlackInk,
            new Negaflow.Interop.SoftProofRgb(
                media.Value.White[0], media.Value.White[1], media.Value.White[2]),
            new Negaflow.Interop.SoftProofRgb(
                media.Value.Black[0], media.Value.Black[1], media.Value.Black[2]));
        Check(PrintSoftProofFilter.Transforms(proof), "proof_filter_changes_pixels");
        byte[] pixels = [255, 255, 255, 255];
        PrintSoftProofFilter.Apply(pixels, proof);
        Check(pixels[0] < 250 && pixels[1] < 250 && pixels[2] < 250,
            "proof_filter_pulls_white_down");
        byte[] shadow = [0, 0, 0, 255];
        PrintSoftProofFilter.Apply(shadow, proof);
        Check(shadow[0] > 2 && shadow[1] > 2 && shadow[2] > 2,
            "proof_filter_lifts_black_to_the_ink");
        // 순백 프로파일이면 아무것도 바꾸지 않습니다.
        Negaflow.Interop.SoftProofSettings neutral = new(
            true,
            Negaflow.Interop.SoftProofSimulation.PaperAndBlackInk,
            Negaflow.Interop.SoftProofRgb.White,
            Negaflow.Interop.SoftProofRgb.Black);
        Check(!PrintSoftProofFilter.Transforms(neutral), "proof_filter_skips_a_neutral_profile");
    }

    /// <summary>
    /// 색역 판정에 쓸 수 있는 인화소 프로파일입니다. 없으면 그 검사는 건너뜁니다 — 시스템
    /// 기본 프로파일은 sRGB 보다 넓어 색역 밖 화소가 나오지 않아 판별력이 없습니다.
    /// </summary>
    private static byte[]? LabProfile()
    {
        string[] candidates =
        [
            @"C:\Users\habin\Downloads\20070_PG_Color.icm",
            @"C:\Users\habin\Downloads\20070_Canvas_Color.icm",
        ];
        foreach (string path in candidates)
        {
            if (File.Exists(path) && PrintIccProfile.IsRgbOutput(path))
            {
                return File.ReadAllBytes(path);
            }
        }
        return null;
    }

    /// <summary>wtpt · bkpt 두 태그만 담은 최소 ICC 입니다.</summary>
    private static byte[] BuildProfile(double[] white, double[] black)
    {
        const int header = 128;
        const int tableStart = header + 4;
        const int entries = 2;
        int dataStart = tableStart + (entries * 12);
        byte[] icc = new byte[dataStart + 40];
        System.Text.Encoding.ASCII.GetBytes("prtr").CopyTo(icc, 12);
        System.Text.Encoding.ASCII.GetBytes("RGB ").CopyTo(icc, 16);
        WriteUInt32(icc, header, entries);
        WriteTag(icc, tableStart, "wtpt", dataStart, 20);
        WriteTag(icc, tableStart + 12, "bkpt", dataStart + 20, 20);
        WriteXyz(icc, dataStart, white);
        WriteXyz(icc, dataStart + 20, black);
        return icc;
    }

    private static void WriteTag(byte[] icc, int at, string signature, int offset, int size)
    {
        System.Text.Encoding.ASCII.GetBytes(signature).CopyTo(icc, at);
        WriteUInt32(icc, at + 4, (uint)offset);
        WriteUInt32(icc, at + 8, (uint)size);
    }

    private static void WriteXyz(byte[] icc, int at, double[] xyz)
    {
        System.Text.Encoding.ASCII.GetBytes("XYZ ").CopyTo(icc, at);
        for (int channel = 0; channel < 3; ++channel)
        {
            WriteUInt32(icc, at + 8 + (channel * 4), (uint)Math.Round(xyz[channel] * 65536.0));
        }
    }

    private static void WriteUInt32(byte[] icc, int at, uint value)
    {
        icc[at] = (byte)(value >> 24);
        icc[at + 1] = (byte)(value >> 16);
        icc[at + 2] = (byte)(value >> 8);
        icc[at + 3] = (byte)value;
    }
    /// <summary>
    /// 프루프 왕복이 <b>행을 밀지 않는지</b> 봅니다.
    /// </summary>
    /// <remarks>
    /// ICM 의 비트맵 함수는 행마다 4바이트 경계를 요구합니다. <c>너비 × 3</c> 을 그대로 주면
    /// 너비가 4의 배수가 아닐 때 행이 조금씩 밀려, 사진 위쪽만 맞고 아래로 갈수록 엉뚱한
    /// 화소가 나옵니다. 같은 프로파일로 왕복하면 화소가 그대로여야 하므로, 어긋나면 정렬이
    /// 깨진 것입니다.
    /// </remarks>
    private static void VerifyProofRoundTripKeepsRows()
    {
        // 목적지가 원본과 <b>다른</b> 프로파일이어야 판별력이 있습니다. 같은 프로파일로
        // 왕복하면 ICM 이 화소를 그대로 통과시켜 정렬이 깨져도 티가 나지 않습니다.
        string[] candidates =
        [
            @"C:\Windows\System32\spool\drivers\color\AdobeRGB1998.icc",
            @"C:\Windows\System32\spool\drivers\color\WideGamutRGB.icc",
            @"C:\Windows\System32\spool\drivers\color\RSWOP.icm",
        ];
        string? found = candidates.FirstOrDefault(File.Exists);
        if (found is null)
        {
            return;
        }
        byte[] icc = File.ReadAllBytes(found);
        // 너비 13 은 4의 배수가 아닙니다 — 정렬이 틀리면 여기서 어긋납니다.
        const int width = 13;
        const int height = 7;
        byte[] pixels = new byte[width * height * 4];
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                int at = ((y * width) + x) * 4;
                pixels[at] = (byte)((x * 17) + 3);
                pixels[at + 1] = (byte)((y * 29) + 11);
                pixels[at + 2] = (byte)((x * 7) + (y * 13) + 5);
                pixels[at + 3] = 255;
            }
        }
        byte[] original = (byte[])pixels.Clone();
        if (!Negaflow.Interop.NativeGamutMask.Proof(pixels, width, height, icc))
        {
            // 이 기계에서 변환을 못 만들면 아무것도 바꾸지 않는 것이 계약입니다.
            Check(pixels.AsSpan().SequenceEqual(original), "proof_round_trip_leaves_pixels_alone");
            return;
        }
        // 한 줄씩 변환한 결과와 같아야 합니다. 한 줄짜리는 행이 밀릴 수 없으므로, 두 결과가
        // 다르면 여러 줄을 한 번에 넘길 때 행 정렬이 깨진 것입니다.
        byte[] rowByRow = (byte[])original.Clone();
        for (int y = 0; y < height; ++y)
        {
            Span<byte> row = rowByRow.AsSpan(y * width * 4, width * 4);
            if (!Negaflow.Interop.NativeGamutMask.Proof(row, width, 1, icc))
            {
                return;
            }
        }
        int worst = 0;
        for (int index = 0; index < pixels.Length; ++index)
        {
            if (index % 4 == 3)
            {
                continue;
            }
            worst = Math.Max(worst, Math.Abs(pixels[index] - rowByRow[index]));
        }
        Check(worst <= 1, "proof_round_trip_keeps_rows_aligned");
    }
    /// <summary>
    /// 색역 표시가 <b>맞는 행</b>에 찍히는지 봅니다.
    /// </summary>
    /// <remarks>
    /// 위 절반은 무채색(어떤 프로파일도 낼 수 있는 색), 아래 절반은 원색으로 채웁니다.
    /// 표시가 아래 절반에만 있어야 합니다. 위쪽에 번지면 행 매핑이 깨진 것입니다 —
    /// "사진 윗부분만 빨갛다" 는 증상을 이 검사가 잡습니다.
    /// </remarks>
    private static void VerifyGamutMarkLandsOnTheRightRows()
    {
        if (LabProfile() is not { } icc)
        {
            return;
        }
        // 잘림은 행 수가 아니라 <b>화소 수</b>에서 옵니다 — 실측(900x602)에서 대량 호출이
        // 341행(≈307k 화소)에서 멈췄습니다. 그 문턱을 넘는 크기여야 이 검사가 잡습니다.
        const int width = 900;
        const int height = 700;
        const int split = height / 2;
        byte[] pixels = new byte[width * height * 4];
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                int at = ((y * width) + x) * 4;
                // 위 절반은 중간 회색, 아래 절반은 형광에 가까운 원색.
                bool below = y >= split;
                pixels[at] = below ? (byte)0 : (byte)128;
                pixels[at + 1] = below ? (byte)255 : (byte)128;
                pixels[at + 2] = below ? (byte)0 : (byte)128;
                pixels[at + 3] = 255;
            }
        }
        long? marked = Negaflow.Interop.NativeGamutMask.Mark(pixels, width, height, icc);
        // 프로파일이 있는데 판정이 안 되면 그것이 곧 고장입니다 — 조용히 건너뛰면 통과처럼
        // 보입니다. 큰 그림에서 한 번에 넘기면 ICM 이 실패하거나 도중에 멈춥니다.
        Check(marked is > 0, "gamut_mark_runs_on_a_large_image");
        if (marked is null or 0)
        {
            return;
        }
        int first = Negaflow.Interop.NativeGamutMask.FirstMarkedRow;
        int last = Negaflow.Interop.NativeGamutMask.LastMarkedRow;
        Check(first >= split, "gamut_mark_starts_below_the_split");
        // 여러 줄을 한 번에 넘기면 ICM 이 도중에 멈추고도 성공을 돌려줍니다. 마지막 행까지
        // 표시가 닿아야 "사진 윗부분만 빨갛다" 가 되지 않습니다.
        Check(last == height - 1, "gamut_mark_reaches_the_last_row");
        Check(marked == (long)width * (height - split), "gamut_mark_covers_the_whole_half");
    }
    /// <summary>
    /// 좌측 "파일" 탭에서 접어 둔 폴더는 앱을 다시 켜도 그대로여야 합니다.
    /// </summary>
    /// <remarks>
    /// 세 화면이 같은 목록을 보므로 접기 상태도 한 벌입니다 — 설정에 담기지 않으면 다시 켤
    /// 때마다 모두 펼쳐집니다.
    /// </remarks>
    private static void VerifyCollapsedFoldersSurviveRestart()
    {
        ShellPreferences saved = new()
        {
            CollapsedFolders = [@"C:\photos\roll-01", @"C:\photos\roll-02"],
        };
        // 저장했다 불러오는 길을 그대로 지납니다.
        string json = System.Text.Json.JsonSerializer.Serialize(saved);
        ShellPreferences? restored =
            System.Text.Json.JsonSerializer.Deserialize<ShellPreferences>(json);
        Check(restored is not null, "collapsed_folders_round_trip_parses");
        Check(restored!.CollapsedFolders.Count == 2, "collapsed_folders_survive_a_restart");
        Check(restored.CollapsedFolders[0] == @"C:\photos\roll-01",
            "collapsed_folders_keep_their_order");
        // 정규화가 값을 버리지 않아야 합니다.
        Check(restored.Normalize().CollapsedFolders.Count == 2,
            "collapsed_folders_survive_normalize");
        // 기본값은 비어 있습니다 — 처음 켜면 모두 펼쳐집니다.
        Check(new ShellPreferences().CollapsedFolders.Count == 0,
            "collapsed_folders_start_empty");
    }
}
