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
    // 제품 계약으로 받지 않는 형식입니다. 현재는 SVG 뿐입니다.
    UnsupportedImage,
    // 설치된 어떤 codec 도 이 파일을 읽지 못했습니다. `UnsupportedImage` 와 원인도 사용자
    // 대처도 다르므로 한 값으로 합치지 않습니다 — RAW 은 codec 을 설치하면 열리지만
    // SVG 는 무엇을 설치해도 열리지 않습니다.
    UndecodableImage,
    InvalidImageTransform,
    RouteRejected,
}

public sealed record FrameImportRejection(string Path, FrameImportRefusal Refusal);

public sealed record FrameInfraredAttachment(string FrameId, string InfraredPath);

/// <summary>
/// scanner host가 RGB artifact를 안전하게 publish한 뒤 library에 넘기는 한 프레임입니다.
/// 스캐너 publish 는 RGB/IR 쌍을 이미 알고 넘긴다. 일반 가져오기는
/// macOS <c>InfraredImportPairing</c> 과 같은 파일명 규칙으로만 짝을 붙인다.
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

    /// <summary>
    /// 스캐너 preview에서 이어받아 catalog publication에 원자적으로 넣을 전체 기하 recipe입니다.
    /// 하드웨어 요청과는 별개이며, 없으면 <see cref="Rotation"/>만 초기 recipe로 씁니다.
    /// </summary>
    public ImageTransformRecipe? InitialTransform { get; init; }

    /// <summary>
    /// 평판 프리뷰 스캔입니다. macOS <c>isPreviewScan: preview</c> 와 같은 뜻이며, 이 표시가
    /// 붙은 프레임은 장수 세기와 내보내기에서 빠집니다.
    /// </summary>
    public bool IsPreviewScan { get; init; }
}

public sealed record FrameImportPlan(
    IReadOnlyList<CatalogEntityRow> Rows,
    IReadOnlyList<FrameImportRejection> Rejected)
{
    public IReadOnlyList<FrameInfraredAttachment> InfraredAttachments { get; init; } = [];

    public IReadOnlyList<string> RemovedStrayInfraredFrameIds { get; init; } = [];

    public bool HasAnything => Rows.Count > 0 || InfraredAttachments.Count > 0 ||
        RemovedStrayInfraredFrameIds.Count > 0;
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
        // macOS `nextScanIndex` — **장수가 아니라 가장 큰 번호 + 1** 입니다. 장수를 세면 사진을
        // 지운 뒤 가져올 때 이미 쓰인 번호가 다시 나옵니다.
        int nextScanIndex = 1;
        foreach (LibraryFrameSnapshot frame in existingFrames)
        {
            taken.Add(NormalizePath(frame.SourcePath));
            if (!frame.IsPreviewScan && frame.ScanIndex >= nextScanIndex)
            {
                nextScanIndex = frame.ScanIndex + 1;
            }
        }

        // 경로 풀이는 이 계획 하나 안에서 나눠 씁니다. 같은 폴더의 파일은 앞 조각이 전부
        // 같으므로, 따로 풀면 파일 수만큼 같은 디렉터리를 다시 따라가게 됩니다.
        InfraredImportPairing.IdentityScope identities = new();
        InfraredImportPairing.Resolution pairing = InfraredImportPairing.Resolve(
            filePaths,
            [.. existingFrames.Select(frame => frame.SourcePath)],
            identities);
        HashSet<string> pairedInfrared = new(
            pairing.PairedInfraredPaths.Select(identities.Identity),
            StringComparer.OrdinalIgnoreCase);
        Dictionary<string, string> pendingInfrared = new(
            pairing.InfraredByBaseIdentity,
            StringComparer.OrdinalIgnoreCase);

        List<CatalogEntityRow> rows = [];
        List<FrameImportRejection> rejected = [];
        List<FrameInfraredAttachment> infraredAttachments = [];
        DevelopRouteSelection selection = DevelopRouteSelection.FromProcess(process);

        foreach (LibraryFrameSnapshot frame in existingFrames)
        {
            string baseIdentity = identities.Identity(frame.SourcePath);
            if (!pendingInfrared.Remove(baseIdentity, out string? infraredPath) ||
                frame.InfraredPath is not null)
            {
                continue;
            }
            if (!IsFullPath(infraredPath))
            {
                rejected.Add(new FrameImportRejection(
                    infraredPath,
                    FrameImportRefusal.InvalidInfraredPath));
                continue;
            }
            if (!exists(infraredPath))
            {
                rejected.Add(new FrameImportRejection(
                    infraredPath,
                    FrameImportRefusal.InfraredFileNotFound));
                continue;
            }
            if (string.Equals(
                    NormalizePath(frame.SourcePath),
                    NormalizePath(infraredPath),
                    StringComparison.OrdinalIgnoreCase))
            {
                rejected.Add(new FrameImportRejection(
                    infraredPath,
                    FrameImportRefusal.InfraredMatchesVisible));
                continue;
            }
            infraredAttachments.Add(new FrameInfraredAttachment(frame.Id, infraredPath));
        }

        foreach (string path in filePaths)
        {
            if (pairedInfrared.Contains(identities.Identity(path)))
            {
                continue;
            }

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
            if (!ImageSourcePaths.IsSupportedImportPath(path))
            {
                rejected.Add(new FrameImportRejection(path, FrameImportRefusal.UnsupportedImage));
                continue;
            }
            string normalizedPath = NormalizePath(path);
            // 등록 폴더의 변경을 다시 확인할 때 기존 대형 TIFF/RAW를 매번 디코딩하지 않습니다.
            // 중복 여부는 경로만으로 확정할 수 있으므로 메타데이터 읽기보다 먼저 끝냅니다.
            if (taken.Contains(normalizedPath))
            {
                rejected.Add(new FrameImportRejection(path, FrameImportRefusal.AlreadyInLibrary));
                continue;
            }
            LibrarySourceMetadata? sourceMetadata = sourceMetadataReader?.Invoke(path);
            if (sourceMetadataReader is not null && sourceMetadata is null)
            {
                rejected.Add(new FrameImportRejection(path, FrameImportRefusal.UndecodableImage));
                continue;
            }
            // 같은 파일을 두 번 넣으면 편집이 둘로 갈라져 사용자가 어느 쪽을 고쳤는지 알 수
            // 없게 됩니다. 한 번 고르든 두 번 고르든 한 건입니다.
            if (!taken.Add(normalizedPath))
            {
                rejected.Add(new FrameImportRejection(path, FrameImportRefusal.AlreadyInLibrary));
                continue;
            }

            JsonObject record = new()
            {
                ["id"] = nextId(),
                ["rawScanPath"] = path,
                // macOS 는 가져오기에서 `customDisplayName` 을 **쓰지 않습니다**. 비워 두면
                // `sourceFileBaseName`(확장자 뗀 파일 이름)으로 물러납니다.
                // 여기에 `Path.GetFileName` 을 박아 두면 카드·필름스트립·창 제목이 모두
                // `이름.tiff` 가 되고, 내보내기 파일명까지 `이름.tiff.jpg` 로 나옵니다.
                ["scanIndex"] = nextScanIndex,
                ["sourceKind"] = "imported",
                ["params"] = new JsonObject(),
            };
            if (sourceMetadata is { } metadata)
            {
                record[LibraryFrameReader.SourceMetadataName] = LibrarySourceMetadataJson.Write(metadata);
            }
            if (pendingInfrared.TryGetValue(
                    identities.Identity(path),
                    out string? infraredPath))
            {
                record[LibraryFrameReader.InfraredPathName] = infraredPath;
            }

            DevelopRouteWriteResult written = DevelopRouteWriter.Apply(record, selection);
            if (written.FrameRecord is not { } routed)
            {
                rejected.Add(new FrameImportRejection(path, FrameImportRefusal.RouteRejected));
                taken.Remove(normalizedPath);
                continue;
            }

            rows.Add(new CatalogEntityRow(routed["id"]!.GetValue<string>(), routed));
            ++nextScanIndex;
        }

        if (rows.Count == 0 && infraredAttachments.Count == 0 && rejected.Count == 0)
        {
            rejected.Add(new FrameImportRejection(string.Empty, FrameImportRefusal.NoFiles));
        }
        return new FrameImportPlan(rows, rejected)
        {
            InfraredAttachments = infraredAttachments,
        };
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
        foreach (LibraryFrameSnapshot frame in existingFrames)
        {
            taken.Add(NormalizePath(frame.SourcePath));
            if (frame.InfraredPath is { } existingInfrared)
            {
                taken.Add(NormalizePath(existingInfrared));
            }
        }
        int nextScanIndex = NextScanIndexInFolder(existingFrames, scan.VisiblePath, scan.IsPreviewScan);
        if (!taken.Add(NormalizePath(scan.VisiblePath)) ||
            scan.InfraredPath is { } candidateInfrared && !taken.Add(NormalizePath(candidateInfrared)))
        {
            return Rejected(scan.VisiblePath, FrameImportRefusal.AlreadyInLibrary);
        }

        ImageTransformRecipe initialTransform = scan.InitialTransform ?? new ImageTransformRecipe(
            scan.Rotation,
            false,
            false,
            null,
            0.0,
            null);
        if (!initialTransform.IsValid)
        {
            return Rejected(scan.VisiblePath, FrameImportRefusal.InvalidImageTransform);
        }

        JsonObject record = new()
        {
            ["id"] = nextId(),
            ["rawScanPath"] = scan.VisiblePath,
            // 스캐너로 들어온 것도 같습니다 — 이름은 파일 이름에서 파생합니다.
            ["scanIndex"] = nextScanIndex,
            ["sourceKind"] = "scanner",
            ["params"] = TransformParameters(initialTransform),
        };
        if (scan.IsPreviewScan)
        {
            // 프리뷰는 프레임 찾기용 임시 그림입니다. 장수 세기와 내보내기에서 빠집니다.
            record[LibraryFrameReader.IsPreviewScanName] = true;
        }
        if (scan.InfraredPath is { } validInfrared)
        {
            record[LibraryFrameReader.InfraredPathName] = validInfrared;
        }
        // 스캔한 frame 도 가져온 frame 과 같은 원본 성질을 적습니다. 이 값이 없으면 relink 가
        // 다른 사진을 같은 자리에 연결하는 것을 막지 못합니다.
        if (sourceMetadataReader?.Invoke(scan.VisiblePath) is { IsValid: true } scannedMetadata)
        {
            record[LibraryFrameReader.SourceMetadataName] =
                LibrarySourceMetadataJson.Write(scannedMetadata);
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
    private static JsonObject TransformParameters(ImageTransformRecipe transform)
    {
        if (transform == ImageTransformRecipe.Identity)
        {
            return [];
        }

        JsonObject imageTransform = new()
        {
            ["rotation"] = (int)transform.Rotation,
            ["flipHorizontal"] = transform.FlipHorizontal,
            ["flipVertical"] = transform.FlipVertical,
            ["straightenAngle"] = transform.StraightenAngle,
        };
        if (transform.Crop is { } crop)
        {
            imageTransform["cropRect"] = new JsonArray(
                crop.X,
                crop.Y,
                crop.Width,
                crop.Height);
        }
        if (transform.CropAspect is { } cropAspect)
        {
            imageTransform["cropAspect"] = cropAspect;
        }
        return new JsonObject { ["imageTransform"] = imageTransform };
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
            FrameImportRefusal.InfraredFileNotFound => "infrared companion not found",
            FrameImportRefusal.InvalidInfraredPath => "infrared companion path is invalid",
            FrameImportRefusal.InfraredMatchesVisible => "infrared companion is the RGB source",
            FrameImportRefusal.InvalidPath => "not a full path",
            // 예전 문구는 "not a supported TIFF image" 였습니다. 확장자 allowlist 를 걷어낸
            // 뒤로는 틀린 말입니다 — CR2 를 골라도 "TIFF 가 아니다" 라고 말했습니다.
            FrameImportRefusal.UnsupportedImage => "vector images are not imported",
            // Windows 내장 WIC codec 도, 함께 배포하는 RAW 디코더도 이 파일을 읽지 못했습니다.
            // 추가 설치를 안내하지 않습니다 — RAW 디코더는 우리가 같이 넣기 때문입니다.
            FrameImportRefusal.UndecodableImage => "no available decoder could read it",
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

    /// <summary>
    /// 이 폴더에서 다음에 붙일 번호입니다. <b>폴더마다 1 부터</b> 셉니다.
    /// </summary>
    /// <remarks>
    /// macOS <c>AppModel+FullScanPlan</c> 이 그렇게 셉니다 — 목적지 폴더 안의 프레임만 골라
    /// 최대 <c>scanIndex</c> 를 찾고 거기에 1 을 더합니다:
    /// <code>
    /// let existingFrameMaximum = frames.lazy
    ///     .filter { !$0.isPreviewScan &amp;&amp; $0.sourceFrameID == nil
    ///         &amp;&amp; $0.sourceKind == .scannerTIFF
    ///         &amp;&amp; $0.rawScanURL.deletingLastPathComponent() == standardizedOutputFolder }
    ///     .map(\.scanIndex).max() ?? 0
    /// let firstScanIndex = max(existingFrameMaximum, reservedMaximum) + 1
    /// </code>
    /// 앞 판은 <b>폴더를 가리지 않고 카탈로그 전체 장수</b>를 셌습니다. 그래서 새 롤을 만들어도
    /// "사진 1" 이 아니라 "사진 58" 부터 시작했고, 폴더가 늘수록 번호가 끝없이 이어졌습니다.
    ///
    /// 프리뷰는 사진과 <b>따로</b> 셉니다 - 섞어 세면 프리뷰가 사진 번호를 밀어 올립니다.
    /// </remarks>
    private static int NextScanIndexInFolder(
        IReadOnlyList<LibraryFrameSnapshot> existingFrames,
        string destinationPath,
        bool preview)
    {
        string folder = FolderOf(destinationPath);
        int maximum = 0;
        foreach (LibraryFrameSnapshot frame in existingFrames)
        {
            if (frame.IsVirtualCopy ||
                frame.IsPreviewScan != preview ||
                !string.Equals(FolderOf(frame.SourcePath), folder, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (frame.ScanIndex > maximum)
            {
                maximum = frame.ScanIndex;
            }
        }
        return maximum + 1;
    }

    private static string FolderOf(string path) =>
        NormalizePath(Path.GetDirectoryName(path) ?? string.Empty);

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

}
