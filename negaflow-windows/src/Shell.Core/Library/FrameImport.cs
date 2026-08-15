using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

public enum FrameImportRefusal
{
    None,
    NoFiles,
    InvalidPath,
    FileNotFound,
    InfraredFileNotFound,
    InvalidInfraredPath,
    InfraredMatchesVisible,
    AlreadyInLibrary,
    UnsupportedImage,
    RouteRejected,
}

public sealed record FrameImportRejection(string Path, FrameImportRefusal Refusal);

/// <summary>
/// scanner host가 RGB artifact를 안전하게 publish한 뒤 library에 넘기는 한 프레임입니다.
/// IR은 scanner 결과에만 붙으며, 일반 import와 섞어 추측하지 않습니다.
/// </summary>
public sealed record ScannerFrameImport(
    string VisiblePath,
    string? InfraredPath,
    DevelopmentProcess Process)
{
    /// <summary>
    /// 가져올 때 걸어 둘 회전입니다. 홀더에 필름을 늘 같은 방향으로 넣는 사용자가 매번 돌리지
    /// 않도록 설정에서 정합니다. <b>원본은 건드리지 않습니다</b> — recipe 에만 적힙니다.
    /// </summary>
    public ImageRotation Rotation { get; init; } = ImageRotation.Degrees0;
}

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
        Func<string>? newId = null,
        Func<string, LibrarySourceMetadata?>? sourceMetadataReader = null)
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
            LibrarySourceMetadata? sourceMetadata = sourceMetadataReader?.Invoke(path);
            if (sourceMetadataReader is not null && sourceMetadata is null)
            {
                rejected.Add(new FrameImportRejection(path, FrameImportRefusal.UnsupportedImage));
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
            if (sourceMetadata is { } metadata)
            {
                record[LibraryFrameReader.SourceMetadataName] = WriteSourceMetadata(metadata);
            }

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
    /// 이미 host artifact transaction을 통과한 scanner RGB/IR 쌍을 catalog record로 만듭니다.
    /// 두 경로가 같은 파일이거나 한 쪽이 없으면 RGB만 넣어 반쪽 IR 상태를 만들지 않습니다.
    /// </summary>
    public static FrameImportPlan PlanScanner(
        ScannerFrameImport scan,
        IReadOnlyList<LibraryFrameSnapshot> existingFrames,
        Func<string, bool>? fileExists = null,
        Func<string>? newId = null,
        Func<string, LibrarySourceMetadata?>? sourceMetadataReader = null)
    {
        ArgumentNullException.ThrowIfNull(scan);
        ArgumentNullException.ThrowIfNull(existingFrames);
        Func<string, bool> exists = fileExists ?? File.Exists;
        Func<string> nextId = newId ?? (() => Guid.NewGuid().ToString("D"));

        if (!IsFullPath(scan.VisiblePath))
        {
            return Rejected(scan.VisiblePath, FrameImportRefusal.InvalidPath);
        }
        if (!exists(scan.VisiblePath))
        {
            return Rejected(scan.VisiblePath, FrameImportRefusal.FileNotFound);
        }
        if (scan.InfraredPath is { } infraredPath)
        {
            if (!IsFullPath(infraredPath))
            {
                return Rejected(infraredPath, FrameImportRefusal.InvalidInfraredPath);
            }
            if (!exists(infraredPath))
            {
                return Rejected(infraredPath, FrameImportRefusal.InfraredFileNotFound);
            }
            if (string.Equals(NormalizePath(scan.VisiblePath), NormalizePath(infraredPath),
                    StringComparison.OrdinalIgnoreCase))
            {
                return Rejected(infraredPath, FrameImportRefusal.InfraredMatchesVisible);
            }
        }

        HashSet<string> taken = new(StringComparer.OrdinalIgnoreCase);
        int nextScanIndex = 0;
        foreach (LibraryFrameSnapshot frame in existingFrames)
        {
            taken.Add(NormalizePath(frame.SourcePath));
            if (frame.InfraredPath is { } existingInfrared)
            {
                taken.Add(NormalizePath(existingInfrared));
            }
            ++nextScanIndex;
        }
        if (!taken.Add(NormalizePath(scan.VisiblePath)) ||
            scan.InfraredPath is { } candidateInfrared && !taken.Add(NormalizePath(candidateInfrared)))
        {
            return Rejected(scan.VisiblePath, FrameImportRefusal.AlreadyInLibrary);
        }

        JsonObject record = new()
        {
            ["id"] = nextId(),
            ["rawScanPath"] = scan.VisiblePath,
            ["customDisplayName"] = Path.GetFileName(scan.VisiblePath),
            ["scanIndex"] = nextScanIndex,
            ["sourceKind"] = "scanner",
            ["params"] = RotationParameters(scan.Rotation),
        };
        if (scan.InfraredPath is { } validInfrared)
        {
            record[LibraryFrameReader.InfraredPathName] = validInfrared;
        }
        // 스캔한 frame 도 가져온 frame 과 같은 원본 성질을 적습니다. 이 값이 없으면 relink 가
        // 다른 사진을 같은 자리에 연결하는 것을 막지 못합니다.
        if (sourceMetadataReader?.Invoke(scan.VisiblePath) is { IsValid: true } scannedMetadata)
        {
            record[LibraryFrameReader.SourceMetadataName] = WriteSourceMetadata(scannedMetadata);
        }
        DevelopRouteWriteResult written = DevelopRouteWriter.Apply(
            record,
            DevelopRouteSelection.FromProcess(scan.Process));
        return written.FrameRecord is { } routed
            ? new FrameImportPlan([new CatalogEntityRow(routed["id"]!.GetValue<string>(), routed)], [])
            : Rejected(scan.VisiblePath, FrameImportRefusal.RouteRejected);
    }

    /// <summary>
    /// 설정의 기본 회전을 recipe 로 만듭니다. 회전이 없으면 빈 params 이며, 그때 결과는 이
    /// 기능이 없던 때와 바이트 단위로 같습니다.
    /// </summary>
    private static JsonObject RotationParameters(ImageRotation rotation) =>
        rotation == ImageRotation.Degrees0
            ? []
            : new JsonObject
            {
                // 회전은 params 바로 밑이 아니라 imageTransform 안에 삽니다 — reader 가 거기서
                // 찾습니다.
                ["imageTransform"] = new JsonObject { ["rotation"] = (int)rotation },
            };

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
            FrameImportRefusal.InfraredFileNotFound => "infrared companion not found",
            FrameImportRefusal.InvalidInfraredPath => "infrared companion path is invalid",
            FrameImportRefusal.InfraredMatchesVisible => "infrared companion is the RGB source",
            FrameImportRefusal.InvalidPath => "not a full path",
            FrameImportRefusal.UnsupportedImage => "not a supported TIFF image",
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

    private static bool IsFullPath(string? path) =>
        !string.IsNullOrWhiteSpace(path) && Path.IsPathFullyQualified(path);

    private static FrameImportPlan Rejected(string path, FrameImportRefusal refusal) =>
        new([], [new FrameImportRejection(path, refusal)]);

    private static JsonObject WriteSourceMetadata(LibrarySourceMetadata metadata) => new()
    {
        [LibraryFrameReader.SourceFileBytesName] = metadata.FileBytes,
        [LibraryFrameReader.SourcePixelWidthName] = metadata.PixelWidth,
        [LibraryFrameReader.SourcePixelHeightName] = metadata.PixelHeight,
        [LibraryFrameReader.SourceSamplesPerPixelName] = metadata.SamplesPerPixel,
        [LibraryFrameReader.SourceBitsPerSampleName] = metadata.BitsPerSample,
        [LibraryFrameReader.SourceSampleFormatName] = metadata.SampleFormat,
        [LibraryFrameReader.SourceOrientationName] = metadata.Orientation,
    };
}
