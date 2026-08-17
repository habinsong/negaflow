using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// GrainMend 다섯 도구를 하나씩 실제 스캔에 걸어 보고, 각 도구의 recipe 가 화소를 바꾸는지
/// 잽니다. 도구별로 독립된 recipe 를 쓰므로 한 도구가 되는 것을 다른 도구의 결과로 착각하지
/// 않습니다.
/// </summary>
/// <remarks>
/// <code>
/// Negaflow.Shell.UnitTests.exe --defect-tools &lt;storageRoot&gt; &lt;frameId&gt; [irPath]
/// </code>
/// 마지막 인자는 적외선 판입니다. 주지 않으면 IR 경로는 "짝 없음"으로 보고합니다.
/// </remarks>
internal static class DefectToolDiagnostics
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length is < 3 or > 4 || args[0] != "--defect-tools")
        {
            return false;
        }
        exitCode = Run(args[1], args[2], args.Length == 4 ? args[3] : null);
        return true;
    }

    private static int Run(string storageRoot, string frameId, string? infraredPath)
    {
        if (StorageRootResolver.ResolveForTests(Path.GetFullPath(storageRoot)).Roots is not
            { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }
        using LibraryHostService host = new(new FakeDispatcher(accepts: true));
        if (host.Open(roots) != LibraryHostState.Open)
        {
            Console.Error.WriteLine("catalog refused");
            return 2;
        }
        if (host.Frames.SingleOrDefault(frame =>
                string.Equals(frame.Id, frameId, StringComparison.Ordinal)) is not { } subject)
        {
            Console.Error.WriteLine("frame unavailable");
            return 2;
        }

        NativeDevelopExporterAdapter exporter = new();
        // 대조군을 먼저 냅니다. 여기서 0 이 아니면 아래의 어떤 차이도 수리의 증거가 아닙니다.
        long control = DefectPixelProbe.Control(subject, exporter, 900, 700);
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            stage = "control",
            frameId,
            sourceWidth = subject.SourceMetadata?.PixelWidth ?? 0U,
            sourceHeight = subject.SourceMetadata?.PixelHeight ?? 0U,
            differingBytes = control,
        }));

        bool allRepaired = true;
        foreach ((string tool, DefectEditItem? item, string reason) in Build(
                     subject, exporter, infraredPath))
        {
            allRepaired &= Report(subject, exporter, tool, item, reason);
        }
        return control == 0L && allRepaired ? 0 : 1;
    }

    private static IEnumerable<(string Tool, DefectEditItem? Item, string Reason)> Build(
        LibraryFrameSnapshot frame,
        IDevelopExporter exporter,
        string? infraredPath)
    {
        DefectEditItem? automatic = DefectToolRecipes.Automatic(frame, exporter, out string why);
        yield return ("automatic", automatic, why);

        DefectEditItem? guided = DefectToolRecipes.Guided(frame, exporter, out why);
        yield return ("guided", guided, why);

        DefectEditItem? brush = DefectToolRecipes.Brush(frame, out why);
        yield return ("brush", brush, why);

        DefectEditItem? clone = DefectToolRecipes.Clone(frame, out why);
        yield return ("clone", clone, why);

        DefectEditItem? infrared = infraredPath is null
            ? null
            : DefectToolRecipes.Infrared(frame, frame.SourcePath, infraredPath, out why);
        if (infraredPath is null)
        {
            why = "no infrared plane given";
        }
        yield return ("infrared", infrared, why);
    }

    /// <returns>이 도구가 실제로 화소를 바꿨으면 참입니다.</returns>
    private static bool Report(
        LibraryFrameSnapshot frame,
        IDevelopExporter exporter,
        string tool,
        DefectEditItem? item,
        string reason)
    {
        if (item is null)
        {
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                stage = "tool",
                tool,
                built = false,
                reason,
            }));
            return false;
        }

        DefectRecipeSnapshot? recipe = DefectToolRecipes.Wrap(frame, item);
        IReadOnlyList<DefectPixelDelta>? deltas = recipe is null
            ? null
            : DefectPixelProbe.Preview(frame, recipe, exporter);
        // recipe 가 네이티브 요청까지 실렸는지 따로 밝힙니다. 실리지 않았다면 화소가 같은 것은
        // 수리 품질 문제가 아니라 투영이 항목을 버린 것입니다.
        DevelopExportRequest? projected = recipe is null
            ? null
            : DevelopRequestFactory.Create(
                frame with { DefectRecipe = recipe },
                Path.Combine(Path.GetTempPath(), $"defect-tools-{tool}-{Guid.NewGuid():N}.png"))
                .Request;
        // 실패한 렌더는 빈 버퍼를 남기므로 baseline 과 크게 다릅니다. 두 렌더가 모두 성공한
        // 크기에서만 차이를 수리의 증거로 셉니다 — 이 구분이 없으면 거절이 성공으로 읽힙니다.
        bool changed = deltas?.Any(delta =>
            delta.BaselineSucceeded && delta.RepairedSucceeded && delta.DifferingBytes > 0L) == true;
        bool anyRefused = deltas?.Any(delta => !delta.RepairedSucceeded) == true;
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            stage = "tool",
            tool,
            built = true,
            kind = item.Kind.ToString(),
            label = item.Label.Kind.ToString(),
            labelValue = item.Label.Value,
            item.Enabled,
            item.Strength,
            strokes = item.Strokes?.Count ?? 0,
            cloneStrokes = item.CloneStrokes?.Count ?? 0,
            clusters = item.Clusters?.Count ?? 0,
            regionMaskBytes = item.RegionMask?.Data.Length ?? 0,
            projectedRegions = projected?.DefectRegions.Count ?? -1,
            projectedBrushes = projected?.DefectBrushes.Count ?? -1,
            projectedClones = projected?.DefectClones.Count ?? -1,
            projectedInfrared = projected?.DefectInfrared.Count ?? -1,
            projectedOrder = projected?.DefectEditOrder.Count ?? -1,
            changed,
            anyRefused,
            deltas,
        }));
        return changed && !anyRefused;
    }
}
