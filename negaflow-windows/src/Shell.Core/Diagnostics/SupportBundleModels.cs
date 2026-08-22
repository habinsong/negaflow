namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 지원 번들 문서입니다. macOS <c>Services/Diagnostics/SupportBundleModels.swift</c> 이식본이며
/// <b>필드 이름과 차례가 같습니다</b> — 두 판이 같은 JSON 을 내야 받는 쪽이 하나로 읽습니다.
/// </summary>
/// <remarks>
/// <b>개인 정보가 들어가면 안 됩니다.</b> 경로·플러그인 식별자는
/// <see cref="SupportBundlePrivacyHasher"/> 로 해시해 넣습니다. 사진 이름, 폴더 이름,
/// 사용자 이름을 그대로 담지 마십시오.
/// </remarks>
public sealed record SupportBundleDocument(
    int SchemaVersion,
    DateTimeOffset GeneratedAt,
    string RedactionPolicy,
    SupportBundleAppSummary App,
    SupportBundleLocationSummary Locations,
    SupportBundleCatalogSummary Catalog,
    SupportBundleBackupSummary Backup,
    SupportBundleCacheSummary Cache,
    IReadOnlyList<SupportBundlePluginSummary> Plugins,
    SupportBundleScannerSummary? Scanner,
    IReadOnlyList<SupportBundleErrorEvent> RecentErrors)
{
    public const int CurrentSchemaVersion = 1;

    /// <summary>macOS <c>redactionPolicy</c> 와 같은 문구입니다.</summary>
    public const string DefaultRedactionPolicy =
        "omit_paths_names_metadata; salted_sha256_identifiers";
}

public sealed record SupportBundleAppSummary(
    string Version,
    string OsVersion,
    string Architecture,
    int ActiveProcessorCount,
    ulong PhysicalMemoryBytes);

public sealed record SupportBundleLocationSummary(
    string CatalogHash,
    string ScanOriginalsHash,
    string ThumbnailCacheHash,
    string ScanStorageKind);

public sealed record SupportBundleCatalogIssueCount(string Code, string Severity, int Count);

public sealed record SupportBundleCatalogSummary(
    string Lifecycle,
    string? BlockReason,
    bool SnapshotAvailable,
    int CatalogVersion,
    int FrameCount,
    int RollCount,
    int FolderCount,
    int WarningCount,
    int ErrorCount,
    IReadOnlyList<SupportBundleCatalogIssueCount> Issues);

public sealed record SupportBundleBackupGeneration(
    ulong? Sequence,
    DateTimeOffset? CreatedAt,
    string State,
    int? FrameCount,
    int? DefectRecipeCount,
    int? CatalogVersion);

public sealed record SupportBundleBackupSummary(
    string Schedule,
    bool ExternalDestinationConfigured,
    DateTimeOffset? LastAttemptAt,
    DateTimeOffset? LastSuccessAt,
    bool? LastRestoreDrillSucceeded,
    IReadOnlyList<SupportBundleBackupGeneration> Generations);

public sealed record SupportBundleCacheSummary(
    long ThumbnailBytes,
    long CleanedRawBytes,
    int ResidentCleanedRawCount,
    int ResidentDevelopedCount,
    int MaxResidentCleanedRaw,
    int MaxResidentDeveloped);

public sealed record SupportBundlePluginSummary(
    string PluginIdHash,
    string? PluginVersion,
    int SchemaVersion,
    int ProtocolVersion,
    bool SupportedByHost,
    string ApprovalState,
    string? ManifestSha256,
    string? ExecutableSha256);

public sealed record SupportBundleScannerSummary(
    IReadOnlyList<int> ResolutionsDpi,
    IReadOnlyList<string> Modes,
    IReadOnlyList<int> BitDepths,
    bool SupportsPreview,
    bool SupportsTransparency,
    bool SupportsInfrared,
    bool SupportsMultiExposure,
    bool SupportsScanArea);

/// <summary>
/// macOS <c>AppDiagnosticEvent</c> 자리입니다. Windows 는 진단 이벤트 버스가 없으므로
/// 스캐너 진단 로그가 남긴 오류 줄을 그대로 담습니다.
/// </summary>
public sealed record SupportBundleErrorEvent(
    DateTimeOffset At,
    string Source,
    string Message);
