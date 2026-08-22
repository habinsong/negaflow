namespace Negaflow.Shell.Storage;

/// <summary>
/// 저장 위치 방식입니다. macOS <c>DiskStorageLocationMode</c> 이식본입니다.
/// </summary>
/// <remarks>
/// macOS 의 <c>iCloud</c> 자리는 Windows 에서 <b>OneDrive</b> 입니다 — 둘 다 "OS 가 관리하는
/// 클라우드 폴더" 라는 같은 뜻이고, 없으면 문서 폴더로 물러나는 것도 같습니다.
/// </remarks>
public enum DiskStorageLocationMode
{
    /// <summary>OneDrive\negaflow (없으면 문서\negaflow).</summary>
    Cloud,

    /// <summary>바탕 화면\negaflow.</summary>
    Desktop,

    /// <summary>사용자가 고른 부모 폴더\negaflow.</summary>
    SpecificFolder,

    /// <summary>폴더마다 따로 고른 자리.</summary>
    Custom,
}

/// <summary>
/// 썸네일·내보내기·빠른 내보내기·스캔 원본이 놓일 자리입니다. macOS
/// <c>Services/Storage/DiskStorageStore.swift</c> 이식본이며, macOS 가 <c>UserDefaults</c> 에
/// 두는 것을 Windows 는 <see cref="ShellPreferences"/> 에 둡니다.
/// </summary>
/// <remarks>
/// <b>빈 문자열은 "고른 적 없음"</b>입니다. macOS <c>defaults.string(forKey:)</c> 가 nil 을
/// 내는 자리와 같습니다. 빈 값을 경로로 오해해 루트에 쓰지 마십시오.
/// </remarks>
public sealed record DiskStorageSettings
{
    /// <summary>
    /// 기본은 <b>데스크탑</b>입니다. 클라우드 폴더를 기본으로 두면 스캔 원본 수십 GB 가
    /// 사용자가 고르지도 않은 채 동기화 대상이 됩니다.
    /// </summary>
    public DiskStorageLocationMode LocationMode { get; init; } = DiskStorageLocationMode.Desktop;

    /// <summary><see cref="DiskStorageLocationMode.SpecificFolder"/> 에서 고른 <b>부모</b> 폴더입니다.</summary>
    public string SpecificFolder { get; init; } = string.Empty;

    public string RootFolder { get; init; } = string.Empty;

    public string ThumbnailsFolder { get; init; } = string.Empty;

    public string ExportFolder { get; init; } = string.Empty;

    public string QuickExportFolder { get; init; } = string.Empty;

    public string ScansFolder { get; init; } = string.Empty;

    public string ImportedSourcesFolder { get; init; } = string.Empty;

    public string CleanedRawFolder { get; init; } = string.Empty;

    public string ScanPreviewsFolder { get; init; } = string.Empty;

    /// <summary>macOS <c>resetToDefaults()</c> — 고른 자리를 모두 지웁니다.</summary>
    public DiskStorageSettings ResetPaths() => this with
    {
        RootFolder = string.Empty,
        ThumbnailsFolder = string.Empty,
        ExportFolder = string.Empty,
        QuickExportFolder = string.Empty,
        ScansFolder = string.Empty,
        ImportedSourcesFolder = string.Empty,
        CleanedRawFolder = string.Empty,
        ScanPreviewsFolder = string.Empty,
    };

    public DiskStorageSettings Normalize() => this with
    {
        LocationMode = Enum.IsDefined(LocationMode)
            ? LocationMode
            : DiskStorageLocationMode.Desktop,
        SpecificFolder = Clean(SpecificFolder),
        RootFolder = Clean(RootFolder),
        ThumbnailsFolder = Clean(ThumbnailsFolder),
        ExportFolder = Clean(ExportFolder),
        QuickExportFolder = Clean(QuickExportFolder),
        ScansFolder = Clean(ScansFolder),
        ImportedSourcesFolder = Clean(ImportedSourcesFolder),
        CleanedRawFolder = Clean(CleanedRawFolder),
        ScanPreviewsFolder = Clean(ScanPreviewsFolder),
    };

    /// <summary>
    /// 절대 경로만 남깁니다. 상대 경로는 실행할 때마다 다른 곳을 가리키므로 "고른 적 없음"
    /// 으로 되돌립니다 — 엉뚱한 폴더에 원본을 쓰지 않기 위해서입니다.
    /// </summary>
    private static string Clean(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || !Path.IsPathFullyQualified(value))
        {
            return string.Empty;
        }
        try
        {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(value));
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException
            or PathTooLongException)
        {
            return string.Empty;
        }
    }
}
