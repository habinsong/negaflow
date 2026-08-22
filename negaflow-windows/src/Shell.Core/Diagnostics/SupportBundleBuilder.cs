using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Negaflow.Catalog;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.Diagnostics;

/// <summary>지원 번들이 문서를 만들 때 셸에서 받아 오는 값들입니다.</summary>
public sealed record SupportBundleInputs
{
    public required StorageRootSet Roots { get; init; }

    public required string ScanOriginalsDirectory { get; init; }

    public required string ThumbnailDirectory { get; init; }

    /// <summary>macOS <c>ScanStorageLocationInspector</c> 판정 — "cloudManaged" 또는 "local".</summary>
    public required string ScanStorageKind { get; init; }

    public string Lifecycle { get; init; } = "unknown";

    public string? BlockReason { get; init; }

    public int FrameCount { get; init; }

    public int RollCount { get; init; }

    public int FolderCount { get; init; }

    public IReadOnlyList<SupportBundleIssue> Issues { get; init; } = [];

    public FrameCacheLimits Limits { get; init; } = new(0, 0);

    public int ResidentDevelopedCount { get; init; }

    public IReadOnlyList<InstalledScannerPlugin> Plugins { get; init; } = [];

    public IReadOnlyDictionary<string, ScannerPluginApprovalState> PluginApprovals { get; init; } =
        new Dictionary<string, ScannerPluginApprovalState>(StringComparer.Ordinal);
}

/// <summary>카탈로그가 낸 문제 하나입니다. 사진 이름은 들어가지 않습니다.</summary>
public sealed record SupportBundleIssue(string Code, string Severity);

/// <summary>
/// macOS <c>AppModel.makeSupportBundleDocument()</c> 이식본입니다.
/// </summary>
/// <remarks>
/// 디스크를 읽는 부분(<see cref="ThumbnailDiskCache.DirectorySize"/>, 백업 세대 훑기)은
/// 파일 수에 비례하는 IO 라 <b>UI 스레드에서 부르면 안 됩니다</b>. macOS 도 같은 이유로
/// <c>Task.detached(priority: .utility)</c> 에 넘깁니다.
/// </remarks>
public static partial class SupportBundleBuilder
{
    public static SupportBundleDocument Build(SupportBundleInputs inputs, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(inputs);
        SupportBundlePrivacyHasher hasher = new();
        return new SupportBundleDocument(
            SupportBundleDocument.CurrentSchemaVersion,
            now,
            SupportBundleDocument.DefaultRedactionPolicy,
            AppSummary(),
            new SupportBundleLocationSummary(
                hasher.Hash(Normalize(inputs.Roots.CatalogPath)),
                hasher.Hash(Normalize(inputs.ScanOriginalsDirectory)),
                hasher.Hash(Normalize(inputs.ThumbnailDirectory)),
                inputs.ScanStorageKind),
            CatalogSummary(inputs),
            BackupSummary(inputs.Roots.BackupRoot),
            CacheSummary(inputs),
            [.. inputs.Plugins.Select(plugin => PluginSummary(plugin, inputs, hasher))],
            Scanner: null,
            RecentErrors(inputs.Roots.LogRoot, hasher));
    }

    private static SupportBundleAppSummary AppSummary() => new(
        typeof(SupportBundleBuilder).Assembly.GetName().Version?.ToString() ?? "0.0.0",
        RuntimeInformation.OSDescription,
        RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant(),
        Environment.ProcessorCount,
        InstalledMemoryBytes());

    private static SupportBundleCatalogSummary CatalogSummary(SupportBundleInputs inputs)
    {
        List<SupportBundleCatalogIssueCount> issues = [.. inputs.Issues
            .GroupBy(issue => issue)
            .Select(group => new SupportBundleCatalogIssueCount(
                group.Key.Code, group.Key.Severity, group.Count()))
            .OrderBy(issue => issue.Code, StringComparer.Ordinal)];
        return new SupportBundleCatalogSummary(
            inputs.Lifecycle,
            inputs.BlockReason,
            File.Exists(inputs.Roots.CatalogPath),
            CatalogVersion: 0,
            inputs.FrameCount,
            inputs.RollCount,
            inputs.FolderCount,
            issues.Where(issue => issue.Severity != "error").Sum(issue => issue.Count),
            issues.Where(issue => issue.Severity == "error").Sum(issue => issue.Count),
            issues);
    }

    private static SupportBundleBackupSummary BackupSummary(string backupRoot)
    {
        List<SupportBundleBackupGeneration> generations = [];
        DateTimeOffset? lastSuccess = null;
        try
        {
            if (Directory.Exists(backupRoot))
            {
                foreach (string directory in Directory
                    .EnumerateDirectories(backupRoot)
                    .OrderBy(path => path, StringComparer.Ordinal))
                {
                    string name = Path.GetFileName(directory);
                    DateTimeOffset created = Directory.GetCreationTimeUtc(directory);
                    bool complete = File.Exists(Path.Combine(directory, "library.sqlite"));
                    generations.Add(new SupportBundleBackupGeneration(
                        ulong.TryParse(name, out ulong sequence) ? sequence : null,
                        created,
                        complete ? "complete" : "staging",
                        FrameCount: null,
                        DefectRecipeCount: null,
                        CatalogVersion: null));
                    if (complete && (lastSuccess is null || created > lastSuccess))
                    {
                        lastSuccess = created;
                    }
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 백업 폴더를 못 읽어도 나머지 진단은 그대로 냅니다.
        }
        return new SupportBundleBackupSummary(
            "manual",
            ExternalDestinationConfigured: false,
            LastAttemptAt: lastSuccess,
            LastSuccessAt: lastSuccess,
            LastRestoreDrillSucceeded: null,
            generations);
    }

    private static SupportBundleCacheSummary CacheSummary(SupportBundleInputs inputs) => new(
        ThumbnailDiskCache.DirectorySize(inputs.ThumbnailDirectory),
        ThumbnailDiskCache.DirectorySize(
            Path.Combine(inputs.Roots.CacheRoot, "DevelopedPreviews")),
        ResidentCleanedRawCount: 0,
        inputs.ResidentDevelopedCount,
        inputs.Limits.CleanedRaw,
        inputs.Limits.Developed);

    private static SupportBundlePluginSummary PluginSummary(
        InstalledScannerPlugin plugin,
        SupportBundleInputs inputs,
        SupportBundlePrivacyHasher hasher) => new(
            hasher.Hash(plugin.Manifest.Id),
            plugin.Manifest.PluginVersion,
            plugin.Manifest.SchemaVersion,
            plugin.Manifest.ResolvedProtocolVersion,
            plugin.Manifest.IsSupported,
            ScannerPluginApprovalCodes.Code(
                inputs.PluginApprovals.TryGetValue(
                    plugin.Manifest.Id,
                    out ScannerPluginApprovalState state)
                    ? state
                    : ScannerPluginApprovalState.Unapproved),
            plugin.TrustIdentity.ManifestSha256,
            plugin.TrustIdentity.ExecutableSha256);

    /// <summary>
    /// 스캔 실패 로그의 마지막 줄들입니다. <b>경로가 통째로 들어가면 안 되므로</b> 절대 경로처럼
    /// 보이는 것은 해시로 바꿔 담습니다 — 번들의 공개 정책이 그렇게 적혀 있습니다.
    /// </summary>
    private static IReadOnlyList<SupportBundleErrorEvent> RecentErrors(
        string logRoot,
        SupportBundlePrivacyHasher hasher)
    {
        string path = Path.Combine(logRoot, "scanner-failure.txt");
        try
        {
            if (!File.Exists(path))
            {
                return [];
            }
            string[] lines = File.ReadAllLines(path);
            return [.. lines
                .Skip(Math.Max(0, lines.Length - 100))
                .Where(line => line.Length != 0)
                .Select(line => new SupportBundleErrorEvent(
                    ParseStamp(line),
                    "scanner",
                    RedactPaths(line, hasher)))];
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    private static DateTimeOffset ParseStamp(string line) =>
        line.Length >= 23 &&
        DateTimeOffset.TryParse(
            line[..23],
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeLocal,
            out DateTimeOffset stamp)
            ? stamp
            : DateTimeOffset.MinValue;

    private static string RedactPaths(string line, SupportBundlePrivacyHasher hasher) =>
        AbsolutePath().Replace(line, match => "<path:" + hasher.Hash(match.Value) + ">");

    [GeneratedRegex(@"[A-Za-z]:\\[^\s""]+", RegexOptions.CultureInvariant)]
    private static partial Regex AbsolutePath();

    private static string Normalize(string path)
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

    /// <summary>
    /// 설치 메모리입니다. <c>ThumbnailService.InstalledMemoryBytes()</c> 와 <b>같은 출처</b>를
    /// 씁니다 — 번들에 적히는 값과 캐시 한도를 정한 값이 달라서는 안 됩니다.
    /// </summary>
    private static ulong InstalledMemoryBytes()
    {
        long installed = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes;
        return installed > 0 ? (ulong)installed : 0UL;
    }
}
