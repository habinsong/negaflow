using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopPipelineDiagnostics
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 2 && args[0] == "--detect-check")
        {
            exitCode = DetectCheck(args[1]);
            return true;
        }
        if (args.Length == 2 && args[0] == "--detect-matrix")
        {
            exitCode = DetectMatrix(args[1]);
            return true;
        }
        if (args.Length == 3 && args[0] == "--detect-frame-matrix")
        {
            exitCode = DetectFrameMatrix(args[1], args[2]);
            return true;
        }
        if (args.Length == 2 && args[0] == "--probe-open")
        {
            exitCode = ProbeOpen(args[1]);
            return true;
        }
        if (args.Length is 2 or 3 && args[0] == "--export-check")
        {
            exitCode = ExportCheck(args[1], args.Length == 3 ? args[2] : null);
            return true;
        }
        return false;
    }

    private static int ProbeOpen(string sourcePath)
    {
        string full = Path.GetFullPath(sourcePath);
        Console.WriteLine($"path: {full}");
        Console.WriteLine($"exists: {File.Exists(full)}");
        Console.WriteLine($"probe: {NativeTiffSourceProbe.TryRead(full, out TiffSourceMetadata m)} " +
            $"{m.PixelWidth}x{m.PixelHeight}");

        LibraryFrameSnapshot frame = new(
            Guid.NewGuid().ToString("D"),
            full,
            "probe",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                SourceSignalKind.FilmNegativeScan,
                DevelopmentProcess.C41,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            null,
            ToneAdjustment.Neutral);
        DevelopRequestResult built = DevelopRequestFactory.Create(
            frame,
            Path.Combine(Path.GetTempPath(), "probe-open.png"));
        if (built.Request is not { } request)
        {
            Console.WriteLine($"request refused: {built.Refusal}");
            return 1;
        }
        byte[] pixels = new byte[800 * 600 * 4];
        DevelopExportResult preview = new NativeDevelopExporterAdapter()
            .Preview(request, 800, 600, pixels);
        Console.WriteLine(
            $"preview: succeeded={preview.Succeeded} stage={preview.FailedStage} " +
            $"name={preview.FailureName} native=0x{preview.NativeErrorCode:X8} " +
            $"{preview.ImageWidth}x{preview.ImageHeight}");
        return preview.Succeeded ? 0 : 1;
    }

    /// <summary>
    /// 실제 스캔 한 장을 조정값을 걸어 끝까지 내보내 봅니다. preview 와 export 가 같은 요청
    /// 객체를 쓰므로, 여기서 파일이 제대로 나오면 두 경로가 같은 레시피를 쓴다는 계약이
    /// 실물로 확인됩니다.
    /// </summary>
    private static int ExportCheck(string sourcePath, string? destinationPath)
    {
        string source = Path.GetFullPath(sourcePath);
        string destination = destinationPath is null
            ? Path.Combine(Path.GetTempPath(), "negaflow-export-check.png")
            : Path.GetFullPath(destinationPath);

        LibraryFrameSnapshot frame = new(
            Guid.NewGuid().ToString("D"),
            source,
            "export-check",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                SourceSignalKind.FilmNegativeScan,
                DevelopmentProcess.C41,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            null,
            new ToneAdjustment(0.35, 0.2, 0, 0, 0, 0, Density: 0.1, Highlight: -0.2, Shadow: 0.15))
        {
            ColorModel = ColorModelRecipe.Identity with { Warmth = 0.12, Saturation = 0.08 },
            Texture = new TextureRecipe(0.15, 0.3, 0.1, 0.05, -0.1),
        };

        DevelopRequestResult built = DevelopRequestFactory.Create(
            frame,
            destination,
            DevelopExportFormat.Png16);
        if (built.Request is not { } request)
        {
            Console.WriteLine($"request refused: {built.Refusal}");
            return 1;
        }

        NativeDevelopExporterAdapter exporter = new();
        System.Diagnostics.Stopwatch clock = new();
        DevelopExportResult preview = default!;
        // 미리보기 비용이 출력 크기에 비례하는지, 디코드 같은 고정비가 지배하는지를 봅니다.
        // 인터랙티브 프록시를 줄이는 것이 도움이 되는지가 여기서 갈립니다.
        // 조정값을 뺀 요청과 견주면 디코드 같은 고정비와 보정 단계 비용이 갈립니다.
        DevelopExportRequest neutral = DevelopRequestFactory.Create(
            frame with
            {
                Tone = ToneAdjustment.Neutral,
                ColorModel = ColorModelRecipe.Identity,
                Texture = TextureRecipe.Identity,
            },
            destination,
            DevelopExportFormat.Png16).Request!;
        foreach ((string label, DevelopExportRequest candidate) in
            new[] { ("adjusted", request), ("neutral", neutral) })
        {
            foreach ((uint width, uint height) in new[] { (400U, 300U), (1600U, 1200U) })
            {
                byte[] pixels = new byte[(long)width * height * 4];
                clock.Restart();
                preview = exporter.Preview(candidate, width, height, pixels);
                Console.WriteLine(
                    $"preview {label} {width}x{height}: succeeded={preview.Succeeded} " +
                    $"{preview.ImageWidth}x{preview.ImageHeight} {clock.ElapsedMilliseconds}ms");
            }
        }

        if (File.Exists(destination))
        {
            File.Delete(destination);
        }
        clock.Restart();
        DevelopExportResult export = exporter.Run(request);
        long exportMs = clock.ElapsedMilliseconds;
        long bytes = File.Exists(destination) ? new FileInfo(destination).Length : -1;
        Console.WriteLine(
            $"export: succeeded={export.Succeeded} {export.ImageWidth}x{export.ImageHeight} " +
            $"{exportMs}ms bytes={bytes} stage={export.FailedStage} name={export.FailureName}");

        // 원본은 절대 바뀌지 않아야 합니다.
        Console.WriteLine($"source bytes after export: {new FileInfo(source).Length}");
        return preview.Succeeded && export.Succeeded && bytes > 0 ? 0 : 1;
    }

    /// <summary>
    /// 실제 스캔에서 GrainMend 자동 검출을 돌려 봅니다. 크기만 묻는 호출과 마스크를 받는
    /// 호출이 같은 값을 내는지, 그리고 실제로 무언가를 찾는지를 봅니다.
    /// </summary>
    private static int DetectCheck(string sourcePath)
    {
        string source = Path.GetFullPath(sourcePath);
        if (CreateDetectRequest(source) is not { } request)
        {
            Console.WriteLine("request refused");
            return 1;
        }

        System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
        GrainMendDetectionResult detected = NativeDevelopExporter.DetectGrainMend(
            request);
        Console.WriteLine(
            $"v7 review: succeeded={detected.Result.Succeeded} {detected.Width}x{detected.Height} " +
            $"accepted={detected.AcceptedPixels} components={detected.Defects.Count} " +
            $"{clock.ElapsedMilliseconds}ms stage={detected.Result.FailedStage} " +
            $"name={detected.Result.FailureName}");
        if (!detected.Result.Succeeded || detected.ReviewProposal is not { } proposal)
        {
            detected.ReviewProposal?.Dispose();
            return 1;
        }
        GrainMendReviewSession? review = null;
        try
        {
            review = GrainMendReviewSession.TryCreate(proposal, automatic: true);
            DefectEditItem? edit = review?.BuildAcceptedEdit();
            bool exact = edit?.RegionMask is not null &&
                edit.Label.Value == detected.Defects.Count &&
                edit.RegionWidth is > 0 && edit.RegionHeight is > 0 &&
                DefectMaskCodec.TryDecodeRgba8(
                    edit.RegionMask,
                    edit.RegionWidth.Value,
                    edit.RegionHeight.Value,
                    out byte[] rgba) &&
                rgba.Where((_, index) => index % 4 == 0).Any(value => value != 0);
            Console.WriteLine($"singleDetectionExactAccepted={exact}");
            return exact ? 0 : 1;
        }
        finally
        {
            if (review is not null)
            {
                review.Dispose();
            }
            else
            {
                proposal.Dispose();
            }
        }
    }

    /// <summary>
    /// 앱의 자동 검출 옵션을 한 축씩 분리해, 후보가 사라지는 정확한 옵션 조합과 실행 시간을
    /// 실제 스캔에서 기록합니다. CI 기본 경로에는 포함하지 않는 수동 품질 진단입니다.
    /// </summary>
    private static int DetectMatrix(string sourcePath)
    {
        if (CreateDetectRequest(Path.GetFullPath(sourcePath)) is not { } request)
        {
            Console.WriteLine("request refused");
            return 1;
        }
        return RunDetectMatrix(request);
    }

    private static int DetectFrameMatrix(string storageRoot, string frameId)
    {
        if (StorageRootResolver.ResolveForTests(Path.GetFullPath(storageRoot)).Roots is not { } roots)
        {
            Console.WriteLine("storage root refused");
            return 1;
        }
        using LibraryHostService host = new(new FakeDispatcher(accepts: true));
        if (host.Open(roots) != LibraryHostState.Open ||
            host.Frames.SingleOrDefault(frame =>
                string.Equals(frame.Id, frameId, StringComparison.Ordinal)) is not { } frame)
        {
            Console.WriteLine("frame unavailable");
            return 1;
        }
        if (DevelopRequestFactory.Create(
                frame,
                Path.Combine(Path.GetTempPath(), "detect-frame-check.png")).Request
            is not { } request)
        {
            Console.WriteLine("request refused");
            return 1;
        }
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            frame.Id,
            frame.SourcePath,
            defectEditCount = frame.DefectRecipe?.Items.Count ?? 0,
            defectItems = frame.DefectRecipe?.Items.Select(item => new
            {
                item.Id,
                kind = item.Kind.ToString(),
                label = item.Label.Kind.ToString(),
                item.Enabled,
                item.Strength,
            }),
            projected = new
            {
                regions = request.DefectRegions.Count,
                brushes = request.DefectBrushes.Count,
                clones = request.DefectClones.Count,
                infrared = request.DefectInfrared.Count,
                order = request.DefectEditOrder.Select(edit => edit.Kind.ToString()),
            },
            frame.ImageTransform,
            frame.Base,
            frame.Tone,
            frame.ColorModel,
            frame.Texture,
        }));
        DevelopRequestResult baselineBuilt = DevelopRequestFactory.Create(
            frame with { DefectRecipe = null },
            Path.Combine(Path.GetTempPath(), "detect-frame-baseline.png"));
        if (baselineBuilt.Request is not { } baselineRequest)
        {
            Console.WriteLine("baseline request refused");
            return 1;
        }
        byte[] baselinePixels = new byte[900 * 700 * 4];
        byte[] defectPixels = new byte[900 * 700 * 4];
        var exporter = new NativeDevelopExporterAdapter();
        System.Diagnostics.Stopwatch previewClock = System.Diagnostics.Stopwatch.StartNew();
        DevelopExportResult baselinePreview = exporter.Preview(
            baselineRequest, 900, 700, baselinePixels);
        long baselineMilliseconds = previewClock.ElapsedMilliseconds;
        previewClock.Restart();
        DevelopExportResult defectPreview = exporter.Preview(
            request, 900, 700, defectPixels);
        long defectMilliseconds = previewClock.ElapsedMilliseconds;
        long differingBytes = 0;
        int maximumDifference = 0;
        long absoluteDifference = 0;
        for (int index = 0; index < baselinePixels.Length; ++index)
        {
            int difference = Math.Abs(baselinePixels[index] - defectPixels[index]);
            if (difference == 0)
            {
                continue;
            }
            ++differingBytes;
            absoluteDifference += difference;
            maximumDifference = Math.Max(maximumDifference, difference);
        }
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            profile = "persisted-recipe-preview",
            baselinePreview.Succeeded,
            defectSucceeded = defectPreview.Succeeded,
            baselinePreview.ImageWidth,
            baselinePreview.ImageHeight,
            defectWidth = defectPreview.ImageWidth,
            defectHeight = defectPreview.ImageHeight,
            baselineMilliseconds,
            defectMilliseconds,
            differingBytes,
            absoluteDifference,
            maximumDifference,
            defectStage = defectPreview.FailedStage.ToString(),
            defectPreview.FailureName,
        }));
        if (!baselinePreview.Succeeded || !defectPreview.Succeeded || differingBytes == 0)
        {
            return 1;
        }
        return RunDetectMatrix(request);
    }

    private static int RunDetectMatrix(DevelopExportRequest request)
    {

        GrainMendDetectionOptions currentUi = GrainMendSensitivity.ToDetectionOptions(
            GrainMendSensitivity.Default,
            automatic: true,
            detectMicroSpecks: true);
        (string Name, GrainMendDetectionOptions Options)[] profiles =
        [
            ("legacy", GrainMendDetectionOptions.LegacyDefault),
            ("current-ui", currentUi),
            ("without-structure-filter", currentUi with { RejectStructureLines = false }),
            ("without-micro-specks", currentUi with { DetectMicroSpecks = false }),
        ];

        bool succeeded = true;
        foreach ((string name, GrainMendDetectionOptions options) in profiles)
        {
            System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
            GrainMendDetectionResult result = NativeDevelopExporter.DetectGrainMend(
                request,
                detectionOptions: options);
            IGrainMendReviewProposal? proposal = result.ReviewProposal;
            GrainMendReviewSession? review = null;
            try
            {
                Console.WriteLine(JsonSerializer.Serialize(new
                {
                    profile = name,
                    options.DustSensitivity,
                    options.ScratchSensitivity,
                    options.ProtectDetail,
                    options.RejectStructureLines,
                    options.DetectMicroSpecks,
                    result.Result.Succeeded,
                    result.Width,
                    result.Height,
                    result.AcceptedPixels,
                    result.MaskByteCount,
                    components = result.Defects.Count,
                    exactReview = proposal is not null,
                    elapsedMilliseconds = clock.ElapsedMilliseconds,
                    stage = result.Result.FailedStage.ToString(),
                    result.Result.FailureName,
                }));
                succeeded &= result.Result.Succeeded;
                if (name == "current-ui" && result.Result.Succeeded)
                {
                    System.Diagnostics.Stopwatch reviewClock =
                        System.Diagnostics.Stopwatch.StartNew();
                    review = proposal is null
                        ? null
                        : GrainMendReviewSession.TryCreate(proposal, automatic: true);
                    DefectEditItem? edit = review?.BuildAcceptedEdit();
                    long marked = 0L;
                    if (edit?.RegionMask is { } regionMask &&
                        edit.RegionWidth is { } regionWidth &&
                        edit.RegionHeight is { } regionHeight &&
                        DefectMaskCodec.TryDecodeRgba8(
                            regionMask, regionWidth, regionHeight, out byte[] rgba))
                    {
                        for (int pixel = 0; pixel * 4 < rgba.Length; ++pixel)
                        {
                            if (rgba[pixel * 4] != 0)
                            {
                                ++marked;
                            }
                        }
                    }
                    Console.WriteLine(JsonSerializer.Serialize(new
                    {
                        profile = "current-ui-v7-review",
                        editCreated = edit is not null,
                        reviewCreated = review is not null,
                        reviewComponents = review?.ComponentCount ?? 0,
                        marked,
                        reviewElapsedMilliseconds = reviewClock.ElapsedMilliseconds,
                    }));
                    succeeded &= proposal is not null && review is not null &&
                        edit is not null && marked > 0L;
                }
            }
            finally
            {
                if (review is not null)
                {
                    review.Dispose();
                }
                else
                {
                    proposal?.Dispose();
                }
            }
        }
        return succeeded ? 0 : 1;
    }

    private static DevelopExportRequest? CreateDetectRequest(string source)
    {
        LibraryFrameSnapshot frame = new(
            Guid.NewGuid().ToString("D"),
            source,
            "detect-check",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                SourceSignalKind.FilmNegativeScan,
                DevelopmentProcess.C41,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            null,
            ToneAdjustment.Neutral);
        return DevelopRequestFactory.Create(
            frame,
            Path.Combine(Path.GetTempPath(), "detect-check.png")).Request;
    }

}
