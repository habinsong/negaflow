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

internal static class ScannerWorkflowTests
{
    public static void Run()
    {
        VerifyScannerSimulator();
        VerifyPreviewPersistenceBoundary();
        VerifyFlatbedRegions();
    }

    private static void VerifyScannerSimulator()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "scan-simulator-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        var dispatcher = new ImmediateUiDispatcher();
        try
        {
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.ReadOrCreate().IsSuccess, "simulator_catalog_create");
            }

            var trust = new ScannerPluginTrustStore(Path.Combine(isolatedBase, "trust.json"));
            // 이 시험 프로세스는 네이티브를 띄우지 않으므로 TIFF probe 만 관리 코드로 읽습니다.
            // 합성 TIFF 가 실제 디코더로도 읽히는지는 네이티브 하네스가 따로 확인했습니다.
            var session2 = new ScanSessionController(
                new FakeScannerGateway(Path.Combine(isolatedBase, "no-plugins")),
                trust,
                dispatcher,
                new SimulatedScannerGateway(ReadTiffHeader));
            Check(session2.State == ScanSessionState.NoPlugin, "simulator_off_has_no_plugin");

            session2.SetSimulatorEnabled(true);
            // 시뮬레이터는 이 앱의 코드이므로 승인을 묻지 않습니다.
            Check(
                session2.State == ScanSessionState.NoDevice &&
                session2.PluginsRequiringApproval.Count == 0,
                "simulator_needs_no_approval");

            session2.RefreshDevicesAsync().GetAwaiter().GetResult();
            Check(session2.State == ScanSessionState.Ready, "simulator_finds_devices");
            Check(session2.Devices.Count == 2, "simulator_offers_film_and_flatbed");
            Check(
                session2.Resolutions.SequenceEqual([900, 1800, 3600, 7200]),
                "simulator_film_resolutions");
            Check(session2.CanScan && session2.CanPreview, "simulator_can_scan");

            using var library = new LibraryHostService(
                dispatcher,
                new ThrowingDevelopExporter(),
                ReadTiffHeader);
            Check(library.Open(roots) == LibraryHostState.Open, "simulator_library_open");
            Check(library.Frames.Count == 0, "simulator_library_starts_empty");

            string rollDirectory = ScanStorageLayout.EnsureRollDirectory(
                Path.Combine(roots.LibraryRoot, "Scans"),
                FilmType.ColorNegative,
                "Simulated",
                DateTime.Now);
            session2.UpdateOptions(options => options with { ResolutionDpi = 1800, BatchCount = 2 });
            ScanRunOutcome outcome = session2.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Simulator"),
                preview: false).GetAwaiter().GetResult();

            Check(outcome.IsSuccess, "simulator_scan_publishes");
            Check(outcome.Published == 2, "simulator_scan_publishes_the_whole_batch");
            Check(library.Frames.Count == 2, "simulator_frames_reach_the_catalog");

            if (library.Frames.Count == 0)
            {
                Check(false, "simulator_scan_publishes_nothing");
                return;
            }
            // 게시된 원본은 실제 디코더가 읽는 TIFF 여야 합니다.
            LibraryFrameSnapshot published = library.Frames[0];
            Check(File.Exists(published.SourcePath), "simulator_source_exists");
            Check(
                published.SourceMetadata is { IsValid: true, SamplesPerPixel: 3, BitsPerSample: 16 },
                "simulator_source_metadata_is_readable");
            Check(
                published.Route.FilmType == FilmType.ColorNegative &&
                published.Route.SourceTransport == FrameSourceTransport.Scanner,
                "simulator_frame_route_says_scanner");
            // 두 장이 서로 다른 파일이어야 합니다 — 배치가 같은 자리를 덮으면 안 됩니다.
            // 프리뷰는 Develop에서 보이지만 catalog에는 저장되지 않는 세션 frame입니다.
            int beforePreview = library.Frames.Count;
            ScanRunOutcome previewRun = session2.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Preview"),
                preview: true).GetAwaiter().GetResult();
            Check(previewRun.IsSuccess, "simulator_preview_runs");
            Check(library.Frames.Count == beforePreview + 1,
                "simulator_preview_is_visible_in_memory");
            LibraryFrameSnapshot previewFrame = library.Frames[^1];
            Check(previewFrame.IsPreviewScan, "simulator_preview_has_ephemeral_marker");
            Check(session2.PreviewFrameId == previewFrame.Id,
                "simulator_preview_session_tracks_frame");
            Check(library.ActiveFrameId == previewFrame.Id,
                "simulator_preview_is_selected");
            Check(
                session2.LastPreviewPath is { } previewPath && File.Exists(previewPath),
                "simulator_preview_leaves_a_file");

            var previewTransform = new ImageTransformRecipe(
                ImageRotation.Degrees90,
                true,
                false,
                new ImageCropRect(0.05, 0.08, 0.80, 0.75),
                1.25,
                4.0 / 3.0);
            Check(
                library.Edit(
                    previewFrame.Id,
                    new LibraryFrameEdit(
                        previewFrame.Tone,
                        previewFrame.ManualBase,
                        ImageTransform: previewTransform)) == LibraryFrameError.None,
                "simulator_preview_transform_is_editable");
            LibraryFrameSnapshot selectedPreview = library.Frames.First(
                frame => frame.Id == previewFrame.Id);
            DefectRect previewRawRoi = new(0.12, 0.18, 0.31, 0.27);
            GrainMendGuidedCarryover? expectedCarryover = GrainMendGuidedCarryover.Capture(
                selectedPreview,
                previewRawRoi,
                0.72);
            GrainMendGuidedCarryover? transformOnlyCarryover = GrainMendGuidedCarryover.Capture(
                selectedPreview,
                null,
                0.72);
            Check(
                transformOnlyCarryover is { DisplayRoi: null } &&
                transformOnlyCarryover.Transform == previewTransform,
                "scanner_carryover_keeps_transform_without_guided_roi");
            var carried = new List<(string FrameId, GrainMendGuidedCarryover Carryover)>();
            session2.GuidedCarryoverProvider = () => expectedCarryover;
            session2.GuidedCarryoverPublished = (frameId, carryover) =>
                carried.Add((frameId, carryover));
            ScanRunOutcome carryoverRun = session2.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Carryover"),
                preview: false).GetAwaiter().GetResult();
            LibraryFrameSnapshot carriedFrame = library.Frames.First(frame =>
                carried.Count == 1 && frame.Id == carried[0].FrameId);
            Check(
                carryoverRun.Published == 2 && carried.Count == 1 &&
                carried[0].Carryover == expectedCarryover,
                "guided_carryover_reaches_only_the_first_full_scan");
            Check(carriedFrame.ImageTransform == previewTransform,
                "scanner_carryover_publishes_preview_transform");
            Check(
                carried[0].Carryover.TryMapToRaw(carriedFrame, out DefectRect carriedRawRoi) &&
                double.IsFinite(carriedRawRoi.X) && double.IsFinite(carriedRawRoi.Y) &&
                double.IsFinite(carriedRawRoi.Width) && double.IsFinite(carriedRawRoi.Height) &&
                carriedRawRoi.Width > 0.0 && carriedRawRoi.Height > 0.0,
                "guided_carryover_maps_display_roi_to_full_scan");
            Check(
                library.Frames.Count == beforePreview + 2 &&
                library.Frames.All(frame => !frame.IsPreviewScan),
                "successful_full_scan_removes_ephemeral_preview");

            Check(
                library.Frames.Count == 4 && !string.Equals(
                    library.Frames[0].SourcePath,
                    library.Frames[1].SourcePath,
                    StringComparison.OrdinalIgnoreCase),
                "simulator_batch_never_overwrites");

            session2.SelectDeviceAsync(SimulatedScannerGateway.FlatbedScannerId)
                .GetAwaiter().GetResult();
            string? flatbedRegionId = session2.AddRegion();
            int flatbedCarryoverCaptureCount = 0;
            int flatbedCarryoverPublishCount = 0;
            session2.GuidedCarryoverProvider = () =>
            {
                flatbedCarryoverCaptureCount++;
                return expectedCarryover;
            };
            session2.GuidedCarryoverPublished = (_, _) => flatbedCarryoverPublishCount++;
            ScanRunOutcome flatbedRun = session2.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Flatbed"),
                preview: false).GetAwaiter().GetResult();
            Check(flatbedRegionId is not null && flatbedRun.Published == 1,
                "flatbed_region_scan_publishes");
            Check(flatbedCarryoverCaptureCount == 0 && flatbedCarryoverPublishCount == 0,
                "guided_carryover_excludes_flatbed_region_scan");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                try
                {
                    Directory.Delete(isolatedBase, true);
                }
                catch (IOException)
                {
                    // 시험 뒤처리 실패는 시험 결과가 아닙니다.
                }
            }
        }
    }

    private static void VerifyPreviewPersistenceBoundary()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "scan-preview-persistence-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        string previewPath = Path.Combine(isolatedBase, "preview.tif");
        try
        {
            Directory.CreateDirectory(isolatedBase);
            File.WriteAllBytes(previewPath, [1, 2, 3, 4]);
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.ReadOrCreate().IsSuccess, "preview_persistence_catalog_create");
            }
            LibrarySourceMetadata metadata = new(4, 64, 48, 3, 16, 1, 1);
            using (var library = new LibraryHostService(
                       new ImmediateUiDispatcher(),
                       new ThrowingDevelopExporter(),
                       _ => metadata))
            {
                Check(library.Open(roots) == LibraryHostState.Open,
                    "preview_persistence_library_open");
                ScannerFramePublishResult published = library.PublishScannerPreviewFrame(
                    new ScannerFrameImport(previewPath, null, DevelopmentProcess.C41)
                    {
                        IsPreviewScan = true,
                    });
                Check(published.Frame is { IsPreviewScan: true } && library.Frames.Count == 1,
                    "preview_persistence_frame_is_visible_in_memory");
                Check(library.Save() == CatalogStoreError.None,
                    "preview_persistence_save_succeeds");
            }
            using var reopened = new LibraryHostService(
                new ImmediateUiDispatcher(),
                new ThrowingDevelopExporter(),
                _ => metadata);
            Check(reopened.Open(roots) == LibraryHostState.Open && reopened.Frames.Count == 0,
                "preview_persistence_frame_is_not_in_catalog");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                try
                {
                    Directory.Delete(isolatedBase, true);
                }
                catch (IOException)
                {
                    // 시험 뒤처리 실패는 시험 결과가 아닙니다.
                }
            }
        }
    }

    /// <summary>
    /// 합성 TIFF 의 첫 IFD 만 읽습니다. 관리 코드로 충분한 이유는 이 시험이 확인하려는 것이
    /// 디코더가 아니라 스캔→커밋→게시의 연결이기 때문입니다.
    /// </summary>
    /// <summary>같은 TIFF 머리글 읽기를 다른 스캐너 시험도 씁니다.</summary>
    internal static LibrarySourceMetadata? ReadTiffHeaderForTests(string path) =>
        ReadTiffHeader(path);

    private static LibrarySourceMetadata? ReadTiffHeader(string path)
    {
        using FileStream stream = File.OpenRead(path);
        Span<byte> header = stackalloc byte[8];
        stream.ReadExactly(header);
        if (header[0] != (byte)'I' || header[1] != (byte)'I')
        {
            return null;
        }
        stream.Position = BitConverter.ToUInt32(header[4..]);
        Span<byte> countBytes = stackalloc byte[2];
        stream.ReadExactly(countBytes);
        int entries = BitConverter.ToUInt16(countBytes);
        var tags = new Dictionary<ushort, uint>();
        byte[] entry = new byte[12];
        for (int index = 0; index < entries; ++index)
        {
            stream.ReadExactly(entry);
            tags[BitConverter.ToUInt16(entry)] = BitConverter.ToUInt32(entry, 8);
        }
        if (!tags.TryGetValue(256, out uint width) || !tags.TryGetValue(257, out uint height))
        {
            return null;
        }
        return new LibrarySourceMetadata(
            (ulong)new FileInfo(path).Length,
            width,
            height,
            (ushort)(tags.TryGetValue(277, out uint spp) ? spp : 3U),
            16,
            1,
            (ushort)(tags.TryGetValue(274, out uint orient) ? orient : 1U));
    }

    /// <summary>이 시험은 현상을 부르지 않습니다. 불리면 그것 자체가 실패입니다.</summary>
    internal sealed class ThrowingDevelopExporter : IDevelopExporter
    {
        public DevelopExportResult Run(DevelopExportRequest request) =>
            throw new NotSupportedException();

        public DevelopExportResult Preview(
            DevelopExportRequest request,
            uint maximumWidth,
            uint maximumHeight,
            byte[] pixels,
            DevelopRun? run = null,
            SoftProofSettings? softProof = null,
            bool clippingOverlay = false) =>
            throw new NotSupportedException();

        public GrainMendDetectionResult DetectGrainMend(
            DevelopExportRequest request,
            DefectRect rawRoi,
            GrainMendDetectionOptions options,
            DevelopRun? run = null) =>
            throw new NotSupportedException();
    }

    /// <summary>
    /// 평판 프레임 자리입니다. 규격 목록이 장치 크기로 좁혀지는지, 프레임이 서로 겹치지 않게
    /// 쌓이는지, 그리고 고른 프레임 자리가 실제 요청에 실리는지를 봅니다.
    /// </summary>
    private static void VerifyFlatbedRegions()
    {
        // 필름 스캐너(36×24)에는 35mm 세 규격만 올라갑니다.
        Check(
            FilmFrameFormats.Available(36.0, 24.0).SequenceEqual([
                FlatbedFrameFormat.FullFrame35mm,
                FlatbedFrameFormat.Square35mm,
                FlatbedFrameFormat.HalfFrame35mm,
            ]),
            "frame_formats_narrow_to_the_device");
        // A4 평판에는 열 규격이 모두 올라갑니다 — 617 도 눕히면 들어갑니다.
        Check(
            FilmFrameFormats.Available(210.0, 297.0).Count == 10,
            "frame_formats_fit_a_flatbed");
        // 크기를 모르면 좁히지 않습니다.
        Check(FilmFrameFormats.Available(null, null).Count == 10, "frame_formats_unknown_bounds");

        var overhang = new FlatbedFrameDetection(
            0.016, 0.857, 0.161, 0.1463, 0.9, 0, 5, StraightenAngle: 0.12);
        FlatbedFrameDetection? clamped = FlatbedRegionEditor.UsableDetection(overhang);
        Check(clamped is { } accepted &&
              Math.Abs((accepted.Y + accepted.Height) - 1.0) < 1e-9 &&
              Math.Abs(accepted.StraightenAngle - overhang.StraightenAngle) < 1e-12 &&
              accepted.Row == overhang.Row && accepted.Column == overhang.Column,
            "flatbed_edge_frame_is_clamped_not_dropped");
        Check(FlatbedRegionEditor.UsableDetection(
                  new FlatbedFrameDetection(0.02, 0.95, 0.16, 0.146, 0.9, 0, 0)) is null &&
              FlatbedRegionEditor.UsableDetection(
                  new FlatbedFrameDetection(double.NaN, 0.1, 0.16, 0.146, 0.9, 0, 0)) is null &&
              FlatbedRegionEditor.UsableDetection(
                  new FlatbedFrameDetection(0.02, 0.1, 0.16, 0.146, 1.4, 0, 0)) is null &&
              FlatbedRegionEditor.UsableDetection(
                  new FlatbedFrameDetection(
                      0.02, 0.1, 0.16, 0.146, 0.9, 0, 0,
                      StraightenAngle: double.NaN)) is null,
            "flatbed_unusable_detections_are_rejected");

        var automaticRegion = FlatbedScanRegion.Create(0.1, 0.2, 0.3, 0.4, 1.25);
        var previewOrientation = new ImageTransformRecipe(
            ImageRotation.Degrees90,
            true,
            false,
            new ImageCropRect(0.05, 0.08, 0.80, 0.75),
            3.5,
            4.0 / 3.0);
        ImageTransformRecipe regionTransform = ScanSessionController.FlatbedInitialTransform(
            previewOrientation,
            ImageRotation.Degrees180,
            automaticRegion);
        Check(
            regionTransform.Rotation == ImageRotation.Degrees90 &&
            regionTransform.FlipHorizontal && !regionTransform.FlipVertical &&
            regionTransform.Crop is null && regionTransform.CropAspect is null &&
            Math.Abs(regionTransform.StraightenAngle + 1.25) < 1e-12,
            "flatbed_initial_transform_keeps_orientation_and_applies_detected_angle");
        ImageTransformRecipe defaultTransform = ScanSessionController.FlatbedInitialTransform(
            null,
            ImageRotation.Degrees180,
            automaticRegion);
        Check(
            defaultTransform.Rotation == ImageRotation.Degrees180 &&
            Math.Abs(defaultTransform.StraightenAngle - 1.25) < 1e-12,
            "flatbed_initial_transform_uses_default_rotation_without_preview_orientation");

        FlatbedOverlayRect imageFrame = new(10.0, 20.0, 200.0, 300.0);
        FlatbedScanRegion rawRegion = FlatbedScanRegion.Create(0.1, 0.2, 0.3, 0.4);
        ImageTransformRecipe quarterTurn = ImageTransformRecipe.Identity with
        {
            Rotation = ImageRotation.Degrees90,
        };
        FlatbedOverlayRect turnedRect = FlatbedOverlayGeometry.ScreenRect(
            rawRegion, imageFrame, quarterTurn, 4000U, 3000U);
        Check(
            Math.Abs(turnedRect.X - 90.0) < 1e-9 &&
            Math.Abs(turnedRect.Y - 50.0) < 1e-9 &&
            Math.Abs(turnedRect.Width - 80.0) < 1e-9 &&
            Math.Abs(turnedRect.Height - 90.0) < 1e-9,
            "flatbed_overlay_region_follows_preview_rotation");
        (double rawX, double rawY, double rawWidth, double rawHeight) =
            FlatbedOverlayGeometry.UnitRect(
                turnedRect, imageFrame, quarterTurn, 4000U, 3000U);
        Check(
            Math.Abs(rawX - rawRegion.UnitX) < 1e-9 &&
            Math.Abs(rawY - rawRegion.UnitY) < 1e-9 &&
            Math.Abs(rawWidth - rawRegion.UnitWidth) < 1e-9 &&
            Math.Abs(rawHeight - rawRegion.UnitHeight) < 1e-9,
            "flatbed_overlay_drag_maps_back_to_base_region");

        // 끌고 있는 중에 사진 자리가 바뀌어도 스캔 영역은 사진 위에서 그대로여야 합니다.
        // 기준을 옛 자리에 남겨 두면, 손가락이 가만히 있어도 다음 이동에서 옛 화면 좌표를
        // 새 자리에 대고 재게 되어 영역이 줌 배율만큼 커지거나 작아집니다(휠 확대·축소).
        FlatbedOverlayRect zoomedFrame = new(-90.0, -130.0, 400.0, 600.0);
        FlatbedOverlayRect anchor = FlatbedOverlayGeometry.ScreenRect(rawRegion, imageFrame);
        FlatbedOverlayRect rebased =
            FlatbedOverlayGeometry.Rebased(anchor, imageFrame, zoomedFrame);
        (double keptX, double keptY, double keptWidth, double keptHeight) =
            FlatbedOverlayGeometry.UnitRect(rebased, zoomedFrame);
        Check(
            Math.Abs(keptX - rawRegion.UnitX) < 1e-9 &&
            Math.Abs(keptY - rawRegion.UnitY) < 1e-9 &&
            Math.Abs(keptWidth - rawRegion.UnitWidth) < 1e-9 &&
            Math.Abs(keptHeight - rawRegion.UnitHeight) < 1e-9,
            "flatbed_overlay_drag_anchor_survives_zoom");
        // 기준을 안 옮겼을 때 실제로 어긋난다는 것도 함께 고정합니다 — 안 그러면 이 시험이
        // 무엇을 막고 있는지 다음 사람이 알 수 없습니다.
        (_, _, double staleWidth, double staleHeight) =
            FlatbedOverlayGeometry.UnitRect(anchor, zoomedFrame);
        Check(
            Math.Abs(staleWidth - rawRegion.UnitWidth) > 1e-6 ||
            Math.Abs(staleHeight - rawRegion.UnitHeight) > 1e-6,
            "flatbed_overlay_stale_anchor_would_resize_the_region");

        (double pointX, double pointY) = FlatbedOverlayGeometry.RebasedPoint(
            imageFrame.X + (imageFrame.Width * 0.25),
            imageFrame.Y + (imageFrame.Height * 0.75),
            imageFrame,
            zoomedFrame);
        Check(
            Math.Abs(pointX - (zoomedFrame.X + (zoomedFrame.Width * 0.25))) < 1e-9 &&
            Math.Abs(pointY - (zoomedFrame.Y + (zoomedFrame.Height * 0.75))) < 1e-9,
            "flatbed_overlay_drag_point_survives_zoom");

        ImageTransformRecipe combinedTransform = new(
            ImageRotation.Degrees270,
            true,
            false,
            new ImageCropRect(0.1, 0.15, 0.75, 0.7),
            2.0,
            null);
        Check(
            DevelopDisplayGeometry.TryMapRawToDisplay(
                combinedTransform, 4000U, 3000U, 0.45, 0.55,
                out double displayX, out double displayY),
            "flatbed_overlay_combined_transform_maps_forward");
        (double restoredX, double restoredY) = FlatbedOverlayGeometry.UnitPoint(
            imageFrame.X + displayX * imageFrame.Width,
            imageFrame.Y + displayY * imageFrame.Height,
            imageFrame,
            combinedTransform,
            4000U,
            3000U);
        Check(
            Math.Abs(restoredX - 0.45) < 1e-9 && Math.Abs(restoredY - 0.55) < 1e-9,
            "flatbed_overlay_crop_straighten_point_round_trip");

        (double nudgeX, double nudgeY) = FlatbedOverlayGeometry.BaseNudgeDelta(
            quarterTurn, 4000U, 3000U, -1.0, 0.0, 0.01, 0.02);
        Check(
            Math.Abs(nudgeX) < 1e-9 && Math.Abs(nudgeY - 0.02) < 1e-9,
            "flatbed_overlay_left_arrow_stays_screen_left_after_rotation");
        ImageTransformRecipe mirrored = ImageTransformRecipe.Identity with
        {
            FlipHorizontal = true,
        };
        (nudgeX, nudgeY) = FlatbedOverlayGeometry.BaseNudgeDelta(
            mirrored, 4000U, 3000U, -1.0, 0.0, 0.01, 0.02);
        Check(
            Math.Abs(nudgeX - 0.01) < 1e-9 && Math.Abs(nudgeY) < 1e-9,
            "flatbed_overlay_left_arrow_stays_screen_left_after_flip");

        string parent = Path.Combine(AppContext.BaseDirectory, "flatbed-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        var trust = new ScannerPluginTrustStore(Path.Combine(isolatedBase, "trust.json"));
        var session = new ScanSessionController(
            new FakeScannerGateway(Path.Combine(isolatedBase, "none")),
            trust,
            new ImmediateUiDispatcher());
        session.SetSimulatorEnabled(true);
        session.RefreshDevicesAsync().GetAwaiter().GetResult();
        // 시뮬레이터의 첫 장치는 필름 스캐너입니다 — 평판 흐름이 아닙니다.
        Check(!session.UsesFlatbedRegionWorkflow, "film_scanner_is_not_a_flatbed");

        session.SelectDeviceAsync(SimulatedScannerGateway.FlatbedScannerId)
            .GetAwaiter().GetResult();
        Check(session.UsesFlatbedRegionWorkflow, "flatbed_uses_the_region_workflow");

        // 프레임은 아래로 쌓이고 서로 겹치지 않습니다.
        string? first = session.AddRegion();
        string? second = session.AddRegion();
        Check(first is not null && second is not null, "flatbed_adds_frames");
        Check(session.Regions.Count == 2, "flatbed_frame_count");
        if (session.Regions.Count < 2)
        {
            // 앞 단언이 이미 실패를 적었습니다. 여기서 색인을 그대로 밀면 예외가 나서
            // **뒤에 오는 시험 무리가 통째로 돌지 못합니다** — 실패 하나가 보고서를 지웁니다.
            return;
        }
        // 좌표는 프리뷰 안의 비율입니다(macOS `unitRect`). 시뮬레이터 평판은 세로가 길어
        // 스트립이 아래로 진행하므로 두 번째 프레임은 첫 번째 아래에 붙습니다.
        Check(
            session.Regions[1].UnitY >= session.Regions[0].UnitMaxY,
            "flatbed_frames_do_not_overlap");
        FlatbedScanRegion manuallyMoved = session.Regions[0] with
        {
            UnitX = session.Regions[0].UnitX + 0.001,
            StraightenAngle = 2.0,
        };
        Check(
            session.UpdateRegion(session.Regions[0].Id, manuallyMoved) &&
            session.Regions[0].StraightenAngle == 0.0,
            "flatbed_manual_edit_clears_automatic_straighten");

        Check(session.CopySelectedRegion() && session.PasteRegion(), "flatbed_copy_paste");
        Check(session.Regions.Count == 3, "flatbed_paste_adds_a_frame");
        string nextAfterFirst = session.Regions[1].Id;
        session.SelectRegion(session.Regions[0].Id);
        Check(session.DeleteSelectedRegion() && session.Regions.Count == 2 &&
              session.SelectedRegionId == nextAfterFirst,
            "flatbed_delete_selects_the_next_frame");
        string previousAfterLast = session.Regions[0].Id;
        session.SelectRegion(session.Regions[^1].Id);
        Check(session.DeleteSelectedRegion() && session.Regions.Count == 1 &&
              session.SelectedRegionId == previousAfterLast,
            "flatbed_delete_last_selects_the_previous_frame");
        Check(session.AddRegion() is not null && session.Regions.Count == 2,
            "flatbed_delete_test_restores_a_second_frame");

        // 고른 프레임 자리가 요청에 실려야 그 자리만 스캔합니다.
        ScannerPluginScanRequest? request = session.BuildRequest(
            false,
            Path.Combine(isolatedBase, "a.tif"),
            1);
        // 요청에는 비율이 아니라 밀리미터가 실립니다. 프리뷰가 담은 영역이 그 자입니다.
        ScannerPluginScanArea? expected = session.Regions[1].ToScanArea(session.PreviewArea);
        Check(
            request?.ScanArea is { } area && expected is { } want &&
            Math.Abs(area.HeightMm - want.HeightMm) < 1e-9 &&
            Math.Abs(area.OriginYmm - want.OriginYmm) < 1e-9,
            "flatbed_request_carries_the_region");
        // 프리뷰는 판 전체를 훑습니다 — 프레임을 찾으려면 판이 다 보여야 합니다.
        ScannerPluginScanRequest? previewRequest = session.BuildRequest(
            true,
            Path.Combine(isolatedBase, "p.tif"),
            0);
        Check(
            previewRequest?.ScanArea is { } previewArea &&
            Math.Abs(previewArea.OriginXmm - session.PreviewArea.OriginXmm) < 1e-9 &&
            Math.Abs(previewArea.OriginYmm - session.PreviewArea.OriginYmm) < 1e-9 &&
            Math.Abs(previewArea.WidthMm - session.PreviewArea.WidthMm) < 1e-9 &&
            Math.Abs(previewArea.HeightMm - session.PreviewArea.HeightMm) < 1e-9,
            "flatbed_preview_scans_the_whole_plate");

        // 프리뷰 픽셀이 없으면 자동으로 찾은 척하지 않습니다.
        Check(
            session.RefreshRegions([], 0U, 0U) == FlatbedFrameGridStatus.InvalidInput,
            "flatbed_automatic_needs_a_preview");
        // 수동은 지우고 규격 프레임 하나를 놓아 다시 시작할 자리를 만듭니다.
        session.UpdateOptions(options => options with
        {
            FrameDetectionMode = FlatbedFrameDetectionMode.Manual,
        });
        Check(
            session.RefreshRegions([], 0U, 0U) == FlatbedFrameGridStatus.Ok &&
            session.Regions.Count == 1,
            "flatbed_manual_refresh_starts_over");
    }

    /// <summary>
    /// MAIN 무보정본입니다. 그림으로 만들기 위해 반드시 있어야 하는 것만 남고 나머지 조정은
    /// 전부 걷혀야 합니다 — 걷지 않으면 "무보정본" 이 아니고, 기하를 걷으면 사용자가 보던 것과
    /// 다른 화면이 됩니다.
    /// </summary>
}
