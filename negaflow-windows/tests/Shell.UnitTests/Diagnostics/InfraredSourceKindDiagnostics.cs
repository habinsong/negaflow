using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 같은 쌍을 <b>가져온 파일</b>과 <b>스캐너 TIFF</b> 두 갈래로 검출해 나란히 냅니다.
/// </summary>
/// <remarks>
/// 스캔으로 만든 프레임은 <c>FrameSourceKind.ScannerTiff</c> 이고, 폴더로 가져온 프레임은
/// <c>ImportedFile</c> 입니다. <c>InfraredDefectRecipeCoordinator.RunFiles</c> 가 그 값을
/// 그대로 네이티브에 넘기므로 <b>같은 파일이어도 검출 경로가 다릅니다.</b>
///
/// 실기에서 방금 스캔한 쌍이 스캔 경로에서는 IR 이 안 붙었는데, 같은 파일을 폴더로 가져와
/// 돌리면 결함 315개로 `Applied` 였습니다. 그 차이가 갈래 때문인지 이 진단이 가릅니다 —
/// 추측으로 가를 수 있는 자리가 아닙니다.
/// </remarks>
internal static class InfraredSourceKindDiagnostics
{
    internal static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        // 스캔이 사진을 게시하는 길을 **그대로** 지나 IR 적용 결과를 냅니다. 검출만 따로
        // 돌리면 `Ok` 가 나오는데 스캔에서는 IR 이 안 붙었으므로, 갈라지는 자리는 게시
        // 경로 안입니다.
        if (args.Length is 3 && args[0] == "--ir-scan-publish-check")
        {
            exitCode = RunScanPublish(
                Path.GetFullPath(args[1]), Path.GetFullPath(args[2]));
            return true;
        }
        if (args.Length is not 3 || args[0] != "--ir-source-kind-check")
        {
            return false;
        }
        string visible = Path.GetFullPath(args[1]);
        string infrared = Path.GetFullPath(args[2]);
        if (!File.Exists(visible) || !File.Exists(infrared))
        {
            Console.Error.WriteLine("visible or infrared file missing");
            exitCode = 2;
            return true;
        }

        var samples = new List<object>();
        foreach (InfraredVisibleSourceKind kind in
            (InfraredVisibleSourceKind[])Enum.GetValues(typeof(InfraredVisibleSourceKind)))
        {
            try
            {
                InfraredDetectionResult result =
                    NativeInfraredDefectDetector.DetectFiles(visible, infrared, kind);
                samples.Add(new
                {
                    sourceKind = kind.ToString(),
                    status = result.Status.ToString(),
                    components = result.Components.Count,
                    clusters = result.Clusters.Count,
                    confirmed = result.ConfirmedCount,
                    candidates = result.CandidateCount,
                    coverage = result.Coverage,
                    alignment = result.AlignmentStatus.ToString(),
                    failure = (string?)null,
                });
            }
            catch (Exception error)
            {
                samples.Add(new
                {
                    sourceKind = kind.ToString(),
                    status = "threw",
                    components = 0,
                    clusters = 0,
                    confirmed = 0UL,
                    candidates = 0UL,
                    coverage = 0.0,
                    alignment = "none",
                    failure = $"{error.GetType().Name}: {error.Message}",
                });
            }
        }

        Console.WriteLine(JsonSerializer.Serialize(
            new
            {
                status = "ok",
                operation = "ir_source_kind_check",
                visible,
                infrared,
                samples,
            },
            new JsonSerializerOptions { WriteIndented = true }));
        return true;
    }

    private static int RunScanPublish(string visible, string infrared)
    {
        if (!File.Exists(visible) || !File.Exists(infrared))
        {
            Console.Error.WriteLine("visible or infrared file missing");
            return 2;
        }
        string root = Path.Combine(
            Path.GetTempPath(), "negaflow-ir-publish-" + Guid.NewGuid().ToString("N"));
        if (StorageRootResolver.ResolveForTests(root).Roots is not { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }
        try
        {
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                if (!session.ReadOrCreate().IsSuccess)
                {
                    Console.Error.WriteLine("catalog create failed");
                    return 2;
                }
            }
            using PumpDispatcher dispatcher = new();
            using LibraryHostService host = new(
                dispatcher,
                new NativeDevelopExporterAdapter(),
                sourceMetadataReader: null,
                token => Task.Delay(Timeout.Infinite, token));
            if (host.Open(roots) != LibraryHostState.Open)
            {
                Console.Error.WriteLine("catalog open refused");
                return 2;
            }
            ScannerFramePublishResult published = host.PublishScannerFrame(
                new ScannerFrameImport(visible, infrared, DevelopmentProcess.C41)
                {
                    Rotation = Negaflow.Catalog.ImageRotation.Degrees0,
                    IsPreviewScan = false,
                });
            Console.WriteLine(JsonSerializer.Serialize(
                new
                {
                    status = "ok",
                    operation = "ir_scan_publish_check",
                    publish = published.Status.ToString(),
                    frame = published.Frame?.Id,
                    framePairedInfrared = published.Frame?.InfraredPath,
                    frameSourceKind = published.Frame?.SourceKind.ToString(),
                    filmType = published.Frame?.Route.FilmType.ToString(),
                    irApply = published.Infrared?.Status.ToString() ?? "none",
                    irSidecar = published.Infrared?.SidecarError.ToString() ?? "none",
                    irCatalog = published.Infrared?.CatalogError.ToString() ?? "none",
                    irComponents = published.Infrared?.Detection?.Components.Count ?? 0,
                    irRecipeWritten = published.Infrared?.Recipe is not null,
                    catalogError = published.CatalogError.ToString(),
                },
                new JsonSerializerOptions { WriteIndented = true }));
            return 0;
        }
        finally
        {
            try
            {
                if (Directory.Exists(root))
                {
                    Directory.Delete(root, recursive: true);
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
            }
        }
    }

}
