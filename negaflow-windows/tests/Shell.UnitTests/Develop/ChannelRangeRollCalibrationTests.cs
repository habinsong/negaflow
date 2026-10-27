using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 채널 범위 롤 교정: 묶음 규칙, 찍기 규칙, 요청 공장이 싣는 것, 캐시 식별에 들어가는 것을 확인합니다.
/// macOS <c>ChannelRangeCalibratorTests</c> 와 같은 사례입니다.
/// </summary>
internal static class ChannelRangeRollCalibrationTests
{
    public static void Run()
    {
        VerifyResolve();
        VerifyHostCalibration();
        VerifyRequestFactory();
    }

    private static ChannelRangeRollCalibrator.Member Member(
        ChannelRangeRgb? shape = null, ChannelRangeRgb? stamped = null, bool contributes = true) =>
        new(shape, stamped, contributes);

    private static void VerifyResolve()
    {
        ChannelRangeRgb shape = new(0.86, 0.97, 1.2);
        Check(ChannelRangeRollCalibrator.Resolve([Member(shape), Member(shape)]) is null,
            "roll_resolve_needs_three_measured_frames");
        Check(ChannelRangeRollCalibrator.Resolve([Member(shape), Member(shape), Member(shape, contributes: false)]) is null,
            "roll_resolve_ignores_virtual_copies");
        ChannelRangeRgb? resolved = ChannelRangeRollCalibrator.Resolve(
            [Member(shape), Member(shape), Member(shape), Member()]);
        Check(resolved is { } r && Math.Abs(r.Red * r.Green * r.Blue - 1.0) < 1.0e-9, "roll_resolve_median_of_shapes");

        ChannelRangeRgb stamped = new(0.9, 1.0, 1.0 / 0.9);
        ChannelRangeRgb late = new(0.7, 1.0, 1.0 / 0.7);
        Check(ChannelRangeRollCalibrator.Resolve(
            [Member(stamped: stamped), Member(stamped: stamped), Member(late), Member(late), Member(late), Member(late)]) == stamped,
            "roll_resolve_follows_the_stamped_value");
        ChannelRangeRgb second = new(0.8, 1.0, 1.25);
        Check(ChannelRangeRollCalibrator.Resolve([Member(stamped: stamped), Member(stamped: second)]) == stamped,
            "roll_resolve_tie_keeps_the_earlier_value");

        Check(ChannelRangeRollCalibrator.GroupOf(null, @"C:\scans\a\x.tif", FrameSourceKind.ScannerTiff) ==
              ChannelRangeRollCalibrator.GroupOf(null, @"c:\SCANS\A\y.tif", FrameSourceKind.ScannerTiff),
            "roll_group_same_folder_ignores_case");
        Check(ChannelRangeRollCalibrator.GroupOf(null, @"C:\scans\a\x.tif", FrameSourceKind.ScannerTiff) !=
              ChannelRangeRollCalibrator.GroupOf(null, @"C:\scans\b\x.tif", FrameSourceKind.ScannerTiff),
            "roll_group_different_folders");
        Check(ChannelRangeRollCalibrator.GroupOf("roll-1", @"C:\scans\a\x.tif", FrameSourceKind.ScannerTiff) ==
              ChannelRangeRollCalibrator.GroupOf("roll-1", @"D:\elsewhere\y.tif", FrameSourceKind.ScannerTiff),
            "roll_group_physical_roll_beats_folder");
        Check(ChannelRangeRollCalibrator.GroupOf(null, @"C:\scans\a\x.tif", FrameSourceKind.ScannerTiff) !=
              ChannelRangeRollCalibrator.GroupOf(null, @"C:\scans\a\x.tif", FrameSourceKind.ImportedFile),
            "roll_group_separates_capture_sources");
    }

    private static JsonObject Frame(string id, string folder, ChannelRangeRgb? shape, bool autoBalance = false)
    {
        JsonObject record = FrameRecord(id, id + ".tif", 0.0);
        record["rawScanPath"] = $@"C:\scans\{folder}\{id}.tif";
        record["params"]!.AsObject()["autoBalance"] = autoBalance;
        return shape is { } s ? RangeShapeWriter.Apply(record, s).FrameRecord! : record;
    }

    private static void VerifyHostCalibration()
    {
        string isolatedBase = Path.Combine(
            AppContext.BaseDirectory, "channel-range-tests", $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        ChannelRangeRgb blue = new(0.80, 0.97, 1.29);
        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("a1", Frame("a1", "rollA", blue)),
                            new("a2", Frame("a2", "rollA", blue)),
                            new("a3", Frame("a3", "rollA", null)),
                            new("a4", Frame("a4", "rollA", null, autoBalance: true)),
                            new("b1", Frame("b1", "rollB", new ChannelRangeRgb(1, 1, 1))),
                            new("b2", Frame("b2", "rollB", new ChannelRangeRgb(1, 1, 1))),
                        ],
                    }));
            }

            using LibraryHostService host = new(new FakeDispatcher(accepts: true), new FakeExporter(_ => DevelopTestResults.OkResult()));
            host.Open(roots);
            LibraryFrameSnapshot Find(string id) => host.Frames.First(frame => frame.Id == id);

            Check(ChannelRangeRollCalibrator.Calibrate(host, "a1") == 0 &&
                host.Frames.All(frame => frame.ChannelRange is null),
                "roll_calibration_waits_for_three_measured_frames");

            host.EditFrameRecord("a3", record => RangeShapeWriter.Apply(record, blue));
            int stamped = ChannelRangeRollCalibrator.Calibrate(host, "a1");
            ChannelRangeRgb? expected = ChannelRangeCalibration.Combine([blue, blue, blue]);
            Check(stamped == 4, "roll_calibration_stamps_every_member_of_the_group");
            Check(new[] { "a1", "a2", "a3", "a4" }.All(id => Find(id).ChannelRange == expected),
                "roll_calibration_gives_one_value_to_the_group");
            Check(Find("b1").ChannelRange is null && Find("b2").ChannelRange is null,
                "roll_calibration_leaves_other_folders_alone");

            // 찍힌 뒤 표본이 크게 달라져도 값이 움직이지 않는다.
            host.EditFrameRecord("a1", record => RangeShapeWriter.Apply(record, new ChannelRangeRgb(1.2, 1.0, 0.83)));
            Check(ChannelRangeRollCalibrator.Calibrate(host, "a2") == 0 && Find("a2").ChannelRange == expected,
                "roll_calibration_is_frozen_after_stamping");

            // 같은 물리 롤에 묶으면 폴더와 무관하게 한 묶음이다.
            string? rollId = host.CreateRoll("Roll", FilmType.ColorNegative, ["b1", "b2", "a1"]);
            Check(rollId is not null, "roll_created_for_the_test");
            host.EditFrameRecord("b1", record => RangeShapeWriter.Apply(record, blue));
            host.EditFrameRecord("b2", record => RangeShapeWriter.Apply(record, blue));
            Check(ChannelRangeRollCalibrator.Calibrate(host, "b1") == 2 &&
                Find("b1").ChannelRange == expected && Find("b2").ChannelRange == expected,
                "roll_calibration_follows_the_physical_roll");
        }
        finally
        {
            try { Directory.Delete(isolatedBase, recursive: true); } catch (IOException) { }
        }
    }

    private static void VerifyRequestFactory()
    {
        ChannelRangeRgb range = new(0.9, 1.0, 1.0 / 0.9);
        LibraryFrameSnapshot Read(bool autoBalance, bool withRange, bool withShape)
        {
            JsonObject record = FrameRecord("f1", "f1.tif", 0.0);
            record["params"]!.AsObject()["autoBalance"] = autoBalance;
            if (withRange) { record = ChannelRangeWriter.Apply(record, range).FrameRecord!; }
            if (withShape) { record = RangeShapeWriter.Apply(record, range).FrameRecord!; }
            return LibraryFrameReader.Read(JsonSerializer.SerializeToElement(record)).Frame!;
        }
        string dest = Path.Combine(Path.GetTempPath(), "channel-range-request.png");

        DevelopExportRequest off = DevelopRequestFactory.Create(Read(false, true, false), dest).Request!;
        Check(off.ChannelRange is { } sent && Math.Abs(sent.Red - 0.9F) < 1.0e-6F, "request_sends_channel_range_when_off");
        Check(DevelopRequestFactory.Create(Read(true, true, false), dest).Request!.ChannelRange is null,
            "request_omits_channel_range_when_auto_balance_measures");
        Check(DevelopRequestFactory.Create(Read(false, false, false), dest).Request!.ChannelRange is null,
            "request_omits_channel_range_without_calibration");
        // 스캐너 타깃과 EXPIRED 는 자기 반전 도메인이 있어 롤 교정을 읽지 않는다(macOS 와 같다).
        foreach (DevelopTarget target in new[] { DevelopTarget.Rescue, DevelopTarget.Noritsu, DevelopTarget.Sp3000 })
        {
            Check(DevelopRequestFactory.Create(Read(false, true, false) with { DevelopTarget = target }, dest)
                    .Request!.ChannelRange is null,
                "request_omits_channel_range_for_" + target);
        }
        Check(DevelopRequestFactory.Create(Read(false, true, false) with { DevelopTarget = DevelopTarget.Print }, dest)
                .Request!.ChannelRange is not null,
            "request_sends_channel_range_for_print_when_off");

        Check(!DevelopRequestFactory.Create(Read(false, false, false), dest).Request!.MeasureRangeShape,
            "request_does_not_measure_unless_asked");
        Check(DevelopRequestFactory.Create(Read(false, false, false), dest, measureRangeShape: true).Request!.MeasureRangeShape,
            "request_measures_the_shape_when_the_frame_has_none");
        Check(!DevelopRequestFactory.Create(Read(false, false, true), dest, measureRangeShape: true).Request!.MeasureRangeShape,
            "request_skips_the_measurement_when_the_shape_is_known");

        // 측정 요청 표시는 캐시 식별(= 그림)에 들어가지 않는다. 교정값은 OFF 에서만 들어간다.
        DevelopExportRequest measureOn = DevelopRequestFactory.Create(Read(false, false, false), dest, measureRangeShape: true).Request!;
        DevelopExportRequest measureOff = DevelopRequestFactory.Create(Read(false, false, false), dest).Request!;
        Check(DevelopedPreviewCacheRecipeCodec.Compose(measureOn, null).AsSpan()
                .SequenceEqual(DevelopedPreviewCacheRecipeCodec.Compose(measureOff, null)),
            "cache_identity_ignores_the_measurement_flag");
        Check(!DevelopedPreviewCacheRecipeCodec.Compose(off, null).AsSpan()
                .SequenceEqual(DevelopedPreviewCacheRecipeCodec.Compose(measureOff, null)),
            "cache_identity_changes_with_the_channel_range_when_off");
        DevelopExportRequest onWith = DevelopRequestFactory.Create(Read(true, true, false), dest).Request!;
        DevelopExportRequest onWithout = DevelopRequestFactory.Create(Read(true, false, false), dest).Request!;
        Check(DevelopedPreviewCacheRecipeCodec.Compose(onWith, null).AsSpan()
                .SequenceEqual(DevelopedPreviewCacheRecipeCodec.Compose(onWithout, null)),
            "cache_identity_ignores_the_channel_range_when_on");
    }
}
