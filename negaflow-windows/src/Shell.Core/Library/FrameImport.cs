using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

public enum FrameImportRefusal
{
    None,
    NoFiles,
    InvalidPath,
    FileNotFound,
    AlreadyInLibrary,
    RouteRejected,
}

public sealed record FrameImportRejection(string Path, FrameImportRefusal Refusal);

public sealed record FrameImportPlan(
    IReadOnlyList<CatalogEntityRow> Rows,
    IReadOnlyList<FrameImportRejection> Rejected)
{
    public bool HasAnything => Rows.Count > 0;
}

/// <summary>
/// 고른 파일을 catalog frame record 로 바꿉니다. 실제 쓰기는 하지 않고 계획만 만들므로 UI 없이
/// 전부 시험됩니다.
/// </summary>
/// <remarks>
/// key 이름은 macOS 와 같습니다 — <c>rawScanPath</c>, <c>scanIndex</c>, <c>sourceKind</c>,
/// top-level <c>filmType</c>. route 부분은 직접 쓰지 않고 <see cref="DevelopRouteWriter"/> 에
/// 맡깁니다. 그쪽이 legacy marker 와 강도 규칙을 소유하기 때문입니다.
/// </remarks>
public static class FrameImport
{
    public static FrameImportPlan Plan(
        IReadOnlyList<string> filePaths,
        IReadOnlyList<LibraryFrameSnapshot> existingFrames,
        DevelopmentProcess process,
        Func<string, bool>? fileExists = null,
        Func<string>? newId = null)
    {
        ArgumentNullException.ThrowIfNull(filePaths);
        ArgumentNullException.ThrowIfNull(existingFrames);

        Func<string, bool> exists = fileExists ?? File.Exists;
        Func<string> nextId = newId ?? (() => Guid.NewGuid().ToString("D"));

        HashSet<string> taken = new(StringComparer.OrdinalIgnoreCase);
        int nextScanIndex = 0;
        foreach (LibraryFrameSnapshot frame in existingFrames)
        {
            taken.Add(NormalizePath(frame.SourcePath));
            ++nextScanIndex;
        }

        List<CatalogEntityRow> rows = [];
        List<FrameImportRejection> rejected = [];
        DevelopRouteSelection selection = DevelopRouteSelection.FromProcess(process);

        foreach (string path in filePaths)
        {
            if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
            {
                rejected.Add(new FrameImportRejection(path ?? string.Empty,
                    FrameImportRefusal.InvalidPath));
                continue;
            }
            if (!exists(path))
            {
                rejected.Add(new FrameImportRejection(path, FrameImportRefusal.FileNotFound));
                continue;
            }
            // 같은 파일을 두 번 넣으면 편집이 둘로 갈라져 사용자가 어느 쪽을 고쳤는지 알 수
            // 없게 됩니다. 한 번 고르든 두 번 고르든 한 건입니다.
            if (!taken.Add(NormalizePath(path)))
            {
                rejected.Add(new FrameImportRejection(path, FrameImportRefusal.AlreadyInLibrary));
                continue;
            }

            JsonObject record = new()
            {
                ["id"] = nextId(),
                ["rawScanPath"] = path,
                ["customDisplayName"] = Path.GetFileName(path),
                ["scanIndex"] = nextScanIndex,
                ["sourceKind"] = "imported",
                ["params"] = new JsonObject(),
            };

            DevelopRouteWriteResult written = DevelopRouteWriter.Apply(record, selection);
            if (written.FrameRecord is not { } routed)
            {
                rejected.Add(new FrameImportRejection(path, FrameImportRefusal.RouteRejected));
                taken.Remove(NormalizePath(path));
                continue;
            }

            rows.Add(new CatalogEntityRow(routed["id"]!.GetValue<string>(), routed));
            ++nextScanIndex;
        }

        if (rows.Count == 0 && rejected.Count == 0)
        {
            rejected.Add(new FrameImportRejection(string.Empty, FrameImportRefusal.NoFiles));
        }
        return new FrameImportPlan(rows, rejected);
    }

    /// <summary>
    /// 결과를 한 줄로 만듭니다. 거부된 것이 있으면 몇 건이고 왜인지 말합니다 — 고른 파일 다섯 개
    /// 중 셋만 들어왔는데 아무 말이 없으면 사용자는 나머지가 어디 갔는지 알 수 없습니다.
    /// </summary>
    public static string Describe(FrameImportPlan plan)
    {
        ArgumentNullException.ThrowIfNull(plan);
        if (plan.Rows.Count == 0 && plan.Rejected.Count == 1 &&
            plan.Rejected[0].Refusal == FrameImportRefusal.NoFiles)
        {
            return "No files were chosen.";
        }

        string added = plan.Rows.Count == 1 ? "Imported 1 frame" : $"Imported {plan.Rows.Count} frames";
        if (plan.Rejected.Count == 0)
        {
            return $"{added}. Set the film base (Dmin) before developing.";
        }

        FrameImportRefusal first = plan.Rejected[0].Refusal;
        string reason = first switch
        {
            FrameImportRefusal.AlreadyInLibrary => "already in the library",
            FrameImportRefusal.FileNotFound => "not found",
            FrameImportRefusal.InvalidPath => "not a full path",
            FrameImportRefusal.RouteRejected => "rejected by the develop route",
            _ => "skipped",
        };
        string skipped = plan.Rejected.Count == 1
            ? $"1 file was skipped ({reason})"
            : $"{plan.Rejected.Count} files were skipped";
        return plan.Rows.Count == 0
            ? $"Nothing imported: {skipped}."
            : $"{added}; {skipped}.";
    }

    private static string NormalizePath(string path)
    {
        try
        {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException
            or PathTooLongException)
        {
            return path;
        }
    }
}
