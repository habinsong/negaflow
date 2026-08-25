using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class CatalogInspectionDiagnostics
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length != 2 || args[0] != "--diagnose")
        {
            return false;
        }
        exitCode = DiagnoseCatalog(args[1]);
        return true;
    }

    private static int DiagnoseCatalog(string storageRoot)
    {
        if (StorageRootResolver.ResolveForTests(storageRoot).Roots is not { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }
        using LibraryHostService host = new(new FakeDispatcher(accepts: true));
        Console.WriteLine($"state: {host.Open(roots)}");
        Console.WriteLine($"frames: {host.Frames.Count}");
        foreach (LibraryFrameSnapshot frame in host.Frames)
        {
            bool exists = File.Exists(frame.SourcePath);
            host.SourceAvailabilityByFrameId.TryGetValue(
                frame.Id, out LibrarySourceAvailability availability);
            DevelopRequestResult request = DevelopRequestFactory.Create(
                frame,
                Path.Combine(Path.GetTempPath(), "diagnose.png"));
            Console.WriteLine(
                $"  {frame.Id} exists={exists} availability={availability} " +
                $"metadata={(frame.SourceMetadata is null ? "none" : "present")} " +
                $"request={(request.IsSuccess ? "ok" : request.Refusal.ToString())} " +
                $"kind={frame.SourceKind} preview={frame.IsPreviewScan} " +
                // IR 쌍이 실제로 어디를 가리키는지 - 카탈로그를 문자열로 훑으면 경계가 안 맞아
                // 엉뚱한 기록을 읽습니다. 여기서 바로 냅니다.
                $"ir={(frame.InfraredPath is { Length: > 0 } infrared
                    ? (File.Exists(infrared) ? infrared : infrared + " (없음)")
                    : "none")} " +
                $"defects={frame.DefectRecipe?.Items.Count.ToString() ?? "none"} " +
                $"path={frame.SourcePath}");
        }
        return 0;
    }

    /// <summary>
    /// 같은 경로를 두 네이티브 진입점에 넣어 봅니다. 하나는 되고 하나는 안 되면 문제가
    /// 어느 쪽인지가 바로 드러납니다.
    /// </summary>
}
