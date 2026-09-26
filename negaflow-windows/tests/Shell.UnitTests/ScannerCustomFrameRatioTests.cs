using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 35mm 파노라마 두 규격과 수동 비율(가로 : 세로)입니다. macOS
/// <c>FlatbedFrameGridDetectorTests.testCustomFrameRatioIsUnitlessAndSizedByFilmWidth</c>,
/// <c>ScannerWorkflowSafetyTests.testCustomFrameRatioStartsFromPresetAndRejectsRatiosThatCannotBeScanned</c>,
/// <c>testMockFlatbedCustomFrameSizeAutomaticallyDetectsAndFullScans</c>,
/// <c>testMockFlatbedSelectedFilmFormatsAutomaticallyDetectAndFullScan</c> 를 옮겼습니다.
/// </summary>
internal static class ScannerCustomFrameRatioTests
{
    /// <summary>시뮬레이터 평판의 프리뷰 크기입니다(<c>SimulatedScannerGateway.Stage</c>).</summary>
    private const int PreviewWidth = 900;
    private const double PlateWidthMm = 210.0;
    private const double PlateHeightMm = 297.0;

    internal static void Run()
    {
        VerifyRatioIsUnitlessAndSizedByFilmWidth();
        VerifyChoiceStartsFromPresetAndRejectsUnscannableRatios();
        RunIfNativeIsPresent(
            VerifyCustomRatioDetectsAndFullScans,
            nameof(VerifyCustomRatioDetectsAndFullScans));
        RunIfNativeIsPresent(
            VerifyEveryPresetDetectsOnTheSimulatedPlate,
            nameof(VerifyEveryPresetDetectsOnTheSimulatedPlate));
    }

    private static void VerifyRatioIsUnitlessAndSizedByFilmWidth()
    {
        Check(FilmFrameRatio.Create(0, 5) is null, "custom_ratio_rejects_zero");
        Check(FilmFrameRatio.Create(1, 20) is null, "custom_ratio_rejects_extreme_aspect");
        Check(FilmFrameRatio.Create(double.PositiveInfinity, 24) is null,
            "custom_ratio_rejects_infinity");
        Check(FilmFrameRatio.Create(1_001, 500) is null, "custom_ratio_rejects_huge_value");
        FilmFrameRatio? fourByFive = FilmFrameRatio.Create(4, 5);
        Check(fourByFive is { } ratio && Math.Abs(ratio.Aspect - 0.8) < 1e-6,
            "custom_ratio_aspect");
        Check(fourByFive?.DisplayName == "4 : 5", "custom_ratio_display");
        Check(FilmFrameRatio.Create(4.5, 6)?.DisplayName == "4.5 : 6",
            "custom_ratio_display_decimal");
        if (fourByFive is null)
        {
            return;
        }
        IReadOnlyList<FlatbedFrameDimensions> sizes = fourByFive.CandidateSizes;
        Check(sizes.Select(size => size.AcrossMm).SequenceEqual([24.0, 56.0]),
            "custom_ratio_candidate_widths");
        Check(sizes.Select(size => size.Is35mm).SequenceEqual([true, false]),
            "custom_ratio_candidate_classes");
        Check(Math.Abs(sizes[0].AlongMm - 19.2) < 1e-6, "custom_ratio_sized_by_film_width");
        Check(FilmFrameRatio.Create(65, 24)?.SizeAt(24) ==
                FilmFrameFormats.Dimensions(FlatbedFrameFormat.Panorama35mm65x24),
            "custom_ratio_65x24_equals_the_preset");
        // 쉼표 소수점도 받습니다(macOS `ScanCustomFrameSizeRow.number`).
        Check(FilmFrameRatio.Parse(" 4,5 ") == 4.5 && FilmFrameRatio.Parse("x") is null &&
              FilmFrameRatio.Parse("Infinity") is null,
            "custom_ratio_parses_comma_decimal");
    }

    private static void VerifyChoiceStartsFromPresetAndRejectsUnscannableRatios()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "custom-ratio-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        var session = new ScanSessionController(
            new FakeScannerGateway(Path.Combine(isolatedBase, "none")),
            new ScannerPluginTrustStore(Path.Combine(isolatedBase, "trust.json")),
            new ImmediateUiDispatcher());
        session.SetSimulatorEnabled(true);
        session.RefreshDevicesAsync().GetAwaiter().GetResult();
        session.SelectDeviceAsync(SimulatedScannerGateway.FlatbedScannerId)
            .GetAwaiter().GetResult();

        Check(session.SelectFrameFormat(FlatbedFrameFormat.Panorama35mm65x24),
            "custom_choice_selects_the_panorama");
        Check(session.SelectCustomFrameRatio(), "custom_choice_turns_on");
        Check(session.Options.CustomFrameRatio == FilmFrameRatio.Create(65, 24) &&
              session.FrameSize == FilmFrameFormats.Dimensions(FlatbedFrameFormat.Panorama35mm65x24),
            "custom_choice_starts_from_the_preset");
        Check(!session.SelectCustomFrameRatio(), "custom_choice_twice_is_no_change");

        Check(session.UpdateCustomFrameRatio(0, 24) == CustomFrameRatioUpdate.Rejected &&
              session.UpdateCustomFrameRatio(double.NaN, 24) == CustomFrameRatioUpdate.Rejected &&
              session.UpdateCustomFrameRatio(1, 20) == CustomFrameRatioUpdate.Rejected,
            "custom_choice_rejects_unusable_values");
        Check(session.Options.CustomFrameRatio == FilmFrameRatio.Create(65, 24),
            "custom_choice_keeps_the_applied_ratio");
        Check(session.UpdateCustomFrameRatio(65, 24) == CustomFrameRatioUpdate.Unchanged,
            "custom_choice_same_ratio_is_unchanged");

        // 단위 없는 비율: 4 : 5 는 4mm × 5mm 가 아닙니다.
        Check(session.UpdateCustomFrameRatio(4, 5) == CustomFrameRatioUpdate.Changed,
            "custom_choice_accepts_four_by_five");
        Check(Math.Abs(session.FrameSize.StripFrameAspect - 0.8) < 1e-6 &&
              session.FrameSize.AcrossMm > 5,
            "custom_choice_is_unitless");

        Check(session.SelectFrameFormat(FlatbedFrameFormat.Medium66) &&
              !session.Options.UsesCustomFrameRatio &&
              session.FrameSize == FilmFrameFormats.Dimensions(FlatbedFrameFormat.Medium66),
            "custom_choice_returns_to_a_preset");
        // 다시 켜면 마지막으로 넣은 비율이 돌아옵니다.
        Check(session.SelectCustomFrameRatio() &&
              session.Options.CustomFrameRatio == FilmFrameRatio.Create(4, 5),
            "custom_choice_remembers_the_last_ratio");

        // 좁은 스캐너로 바꾸면 들어가지 않는 수동 비율은 규격으로 돌아갑니다.
        Check(session.UpdateCustomFrameRatio(3, 1) == CustomFrameRatioUpdate.Changed,
            "custom_choice_accepts_a_long_panorama");
        session.SelectDeviceAsync(SimulatedScannerGateway.FilmScannerId)
            .GetAwaiter().GetResult();
        Check(!session.Options.UsesCustomFrameRatio &&
              FilmFrameFormats.Available(36, 24).Contains(session.Options.FrameFormat),
            "custom_choice_falls_back_on_a_narrow_scanner");
        // 필름 스캐너(36×24)에는 어떤 필름 폭으로도 들어가지 않는 비율을 받지 않습니다.
        Check(session.UpdateCustomFrameRatio(65, 24) == CustomFrameRatioUpdate.Rejected,
            "custom_choice_rejects_what_the_scanner_cannot_hold");
    }

    /// <summary>
    /// 규격 목록에 없는 파노라마(58×24)를 수동 비율로 넣어도 자동 검출과 본 스캔이 이어져야
    /// 합니다. 58 : 24 는 35mm(24mm 폭)로 맞아야 하고, 맞은 폭을 기억해야 합니다.
    /// </summary>
    private static void VerifyCustomRatioDetectsAndFullScans()
    {
        using Fixture fixture = Fixture.Open("custom-ratio-scan");
        ScanSessionController session = fixture.Session;
        _ = session.SelectCustomFrameRatio();
        Check(session.UpdateCustomFrameRatio(58, 24) is not CustomFrameRatioUpdate.Rejected,
            "custom_scan_accepts_58x24");
        // 56mm 폭으로 기억해 두었어도 검출이 24mm 로 맞춰야 합니다.
        session.UpdateOptions(options => options with { CustomFrameAcrossMm = 56 });
        FlatbedFrameDimensions drawn = FilmFrameRatio.Create(58, 24)!.SizeAt(24);
        fixture.Gateway.FrameSize = drawn;

        int found = fixture.PreviewAndDetect(drawn);
        Check(found == 3, "custom_scan_finds_three_frames", () => found.ToString());
        Check(session.Options.CustomFrameAcrossMm == 24, "custom_scan_remembers_the_film_width",
            () => session.Options.CustomFrameAcrossMm.ToString());
        foreach (FlatbedScanRegion region in session.Regions)
        {
            double widthMm = region.UnitWidth * PlateWidthMm;
            double heightMm = region.UnitHeight * PlateHeightMm;
            Check(Math.Abs(Math.Max(widthMm, heightMm) - 58) < 3 &&
                  Math.Abs(Math.Min(widthMm, heightMm) - 24) < 3,
                "custom_scan_region_is_58x24",
                () => $"{widthMm:F1}x{heightMm:F1}");
        }
        ScanRunOutcome full = fixture.FullScan();
        Check(full.Published == 3, "custom_scan_publishes_every_frame",
            () => full.Published.ToString());
    }

    /// <summary>
    /// 규격마다 시뮬레이터가 그 치수로 그리고, 자동 검출이 그 컷을 모두 찾아야 합니다. 35mm
    /// 파노라마는 35mm 간격(고정 피치)으로 찾아야 합니다 — 120 으로 잘못 분류되면 여기서 걸립니다.
    /// </summary>
    /// <summary>macOS 시험과 같은 규격별 컷 수입니다. 표가 규격을 하나도 빠뜨리면 안 됩니다.</summary>
    private static readonly (FlatbedFrameFormat Format, int Frames)[] PresetFrameCounts =
    [
        (FlatbedFrameFormat.FullFrame35mm, 6),
        (FlatbedFrameFormat.Square35mm, 8),
        (FlatbedFrameFormat.HalfFrame35mm, 11),
        (FlatbedFrameFormat.Panorama35mm56x24, 3),
        (FlatbedFrameFormat.Panorama35mm65x24, 3),
        (FlatbedFrameFormat.Medium645, 4),
        (FlatbedFrameFormat.Medium66, 3),
        (FlatbedFrameFormat.Medium67, 2),
        (FlatbedFrameFormat.Medium68, 2),
        (FlatbedFrameFormat.Medium69, 2),
        (FlatbedFrameFormat.Medium612, 1),
        (FlatbedFrameFormat.Medium617, 1),
    ];

    private static void VerifyEveryPresetDetectsOnTheSimulatedPlate()
    {
        Check(PresetFrameCounts.Select(entry => entry.Format).SequenceEqual(FilmFrameFormats.All),
            "preset_frame_count_table_covers_every_format");
        using Fixture fixture = Fixture.Open("preset-scan");
        foreach ((FlatbedFrameFormat format, int frames) in PresetFrameCounts)
        {
            _ = fixture.Session.SelectFrameFormat(format);
            FlatbedFrameDimensions size = FilmFrameFormats.Dimensions(format);
            Check(fixture.Gateway.FrameSize == size, $"preset_simulator_draws_{format}");
            fixture.Gateway.FrameCount = frames;
            int found = fixture.PreviewAndDetect(size);
            Check(found == frames, $"preset_detects_every_frame_{format}",
                () => $"expected={frames} found={found}");
            if (FilmFrameFormats.Is35mm(format) && size.AlongMm > 36)
            {
                // 35mm 파노라마는 본 스캔까지 돌립니다 - 맥 시험이 그렇게 봅니다.
                ScanRunOutcome full = fixture.FullScan();
                Check(full.Published == frames, $"preset_publishes_every_frame_{format}",
                    () => full.Published.ToString());
            }
        }
    }

    /// <summary>시뮬레이터 평판, 격리된 라이브러리, 3컷 스트립입니다.</summary>
    private sealed class Fixture : IDisposable
    {
        private readonly string parent;
        private readonly string isolatedBase;
        private readonly LibraryHostService library;
        private readonly string rollDirectory;

        private Fixture(
            string parent,
            string isolatedBase,
            SimulatedScannerGateway gateway,
            ScanSessionController session,
            LibraryHostService library,
            string rollDirectory)
        {
            this.parent = parent;
            this.isolatedBase = isolatedBase;
            Gateway = gateway;
            Session = session;
            this.library = library;
            this.rollDirectory = rollDirectory;
        }

        internal SimulatedScannerGateway Gateway { get; }

        internal ScanSessionController Session { get; }

        internal static Fixture Open(string name)
        {
            string parent = Path.Combine(AppContext.BaseDirectory, name + "-tests");
            string isolatedBase = Path.Combine(
                parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
            StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
            using (CatalogSession catalog = CatalogSession.Open(roots).Session!)
            {
                Check(catalog.ReadOrCreate().IsSuccess, name + "_catalog_create");
            }
            var dispatcher = new ImmediateUiDispatcher();
            var gateway = new SimulatedScannerGateway(ScannerWorkflowTests.ReadTiffHeaderForTests)
            {
                // macOS 시험과 같은 3컷입니다.
                FrameCount = 3,
            };
            var session = new ScanSessionController(
                new FakeScannerGateway(Path.Combine(isolatedBase, "no-plugins")),
                new ScannerPluginTrustStore(Path.Combine(isolatedBase, "trust.json")),
                dispatcher,
                gateway);
            session.SetSimulatorEnabled(true);
            session.RefreshDevicesAsync().GetAwaiter().GetResult();
            session.SelectDeviceAsync(SimulatedScannerGateway.FlatbedScannerId)
                .GetAwaiter().GetResult();
            var library = new LibraryHostService(
                dispatcher,
                new ScannerWorkflowTests.ThrowingDevelopExporter(),
                ScannerWorkflowTests.ReadTiffHeaderForTests);
            Check(library.Open(roots) == LibraryHostState.Open, name + "_library_open");
            string rollDirectory = ScanStorageLayout.EnsureRollDirectory(
                Path.Combine(roots.LibraryRoot, "Scans"),
                FilmType.ColorNegative,
                name,
                DateTime.Now);
            return new Fixture(parent, isolatedBase, gateway, session, library, rollDirectory);
        }

        /// <summary>
        /// 프리뷰를 찍고 시뮬레이터가 그린 것과 같은 밝기로 프레임을 찾습니다. 앱은 프리뷰 파일을
        /// 다시 읽지만 그 읽기는 WinUI 쪽이라, 여기서는 같은 그림을 같은 함수로 만듭니다.
        /// </summary>
        internal int PreviewAndDetect(FlatbedFrameDimensions size)
        {
            ScanRunOutcome preview = Session.RunAsync(
                library,
                _ => ScanStorageLayout.NewPreviewPath(rollDirectory),
                preview: true).GetAwaiter().GetResult();
            Check(preview.IsSuccess, "fixture_preview_runs");
            // 시뮬레이터가 판 스트립을 그렸는지 봅니다. 평판 프리뷰는 300dpi 본 스캔으로 나가므로
            // 예전 판은 여기서 색막대 한 장(600x400)을 냈습니다.
            LibrarySourceMetadata? drawn = Session.LastPreviewPath is { } path
                ? ScannerWorkflowTests.ReadTiffHeaderForTests(path)
                : null;
            int expectedHeight = (int)Math.Round(PreviewWidth * PlateHeightMm / PlateWidthMm);
            Check(drawn is { PixelWidth: PreviewWidth } header && header.PixelHeight == expectedHeight,
                "fixture_preview_draws_the_plate",
                () => drawn is { } value ? $"{value.PixelWidth}x{value.PixelHeight}" : "none");
            int height = (int)Math.Round(PreviewWidth * PlateHeightMm / PlateWidthMm);
            float[] luminance = SyntheticFilmStrip.Luminance(
                PreviewWidth,
                height,
                PlateWidthMm,
                PlateHeightMm,
                size,
                SyntheticFilmStrip.FittingFrameCount(PlateHeightMm, size, Gateway.FrameCount));
            FlatbedFrameGridStatus status = Session.RefreshRegions(
                luminance, PreviewWidth, (uint)height);
            return status == FlatbedFrameGridStatus.Ok ? Session.Regions.Count : -1;
        }

        internal ScanRunOutcome FullScan() =>
            Session.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Custom"),
                preview: false).GetAwaiter().GetResult();

        public void Dispose()
        {
            library.Dispose();
            try
            {
                if (Directory.Exists(isolatedBase) &&
                    StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
                {
                    Directory.Delete(isolatedBase, recursive: true);
                }
            }
            catch (IOException)
            {
            }
        }
    }
}
