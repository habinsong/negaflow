namespace Negaflow.Shell.Storage;

/// <summary>
/// 설정에서 실제 폴더를 구합니다. macOS <c>DiskStorageStore</c> 의 계산 프로퍼티들
/// (<c>rootURL</c>·<c>thumbnailsURL</c>·…) 이식본입니다.
/// </summary>
/// <remarks>
/// <para>
/// 순수 계산이라 어느 스레드에서 불러도 됩니다. 폴더를 <b>만드는</b> 것은
/// <see cref="EnsureDirectory"/> 로만 합니다 — 값을 읽는 것만으로 디스크를 건드리면
/// 설정창을 열기만 해도 OneDrive 에 빈 폴더가 생깁니다.
/// </para>
/// </remarks>
public sealed class DiskStorageLocations
{
    /// <summary>macOS <c>DiskStorageStore.FolderName</c> 과 같은 ASCII 고정값입니다.</summary>
    public static class FolderName
    {
        public const string Root = "negaflow";
        public const string Thumbnails = "Thumbnails";
        public const string Export = "Export";
        public const string QuickExport = "Quick Export";
        public const string Scans = "Scans";
        public const string ImportedSources = "Imported Originals";
        public const string CleanedRaw = "Cleaned Raw";
        public const string ScanPreviews = "Scan Previews";
    }

    private readonly DiskStorageSettings settings;

    public DiskStorageLocations(DiskStorageSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        this.settings = settings;
    }

    public DiskStorageLocationMode Mode => settings.LocationMode;

    /// <summary>
    /// 기본 루트입니다. OneDrive\negaflow → (OneDrive 없음) 문서\negaflow.
    /// macOS 의 iCloud Drive → Documents 와 같은 갈래입니다.
    /// </summary>
    public static string DefaultRoot()
    {
        if (CloudRoot() is { Length: > 0 } cloud)
        {
            return Path.Combine(cloud, FolderName.Root);
        }
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            FolderName.Root);
    }

    public static string DesktopRoot() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
        FolderName.Root);

    /// <summary>
    /// 이 기계의 OneDrive 폴더입니다. 없으면 빈 문자열입니다.
    /// </summary>
    /// <remarks>
    /// OneDrive 클라이언트는 동기화 루트를 <c>OneDrive</c>(개인) ·
    /// <c>OneDriveCommercial</c>(업무) 환경 변수로 알립니다. 둘 다 없으면
    /// <c>%USERPROFILE%\OneDrive</c> 를 봅니다 — 기본 설치 자리입니다.
    /// </remarks>
    public static string CloudRoot()
    {
        foreach (string name in (string[])["OneDrive", "OneDriveConsumer", "OneDriveCommercial"])
        {
            string? value = Environment.GetEnvironmentVariable(name);
            if (!string.IsNullOrWhiteSpace(value) && Directory.Exists(value))
            {
                return Path.TrimEndingDirectorySeparator(value);
            }
        }
        string fallback = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "OneDrive");
        return Directory.Exists(fallback) ? fallback : string.Empty;
    }

    public string Root => settings.LocationMode switch
    {
        DiskStorageLocationMode.Cloud => DefaultRoot(),
        DiskStorageLocationMode.Desktop => DesktopRoot(),
        DiskStorageLocationMode.SpecificFolder => settings.SpecificFolder.Length != 0
            ? Path.Combine(settings.SpecificFolder, FolderName.Root)
            : DefaultRoot(),
        _ => settings.RootFolder.Length != 0 ? settings.RootFolder : DefaultRoot(),
    };

    public string Thumbnails => Managed(FolderName.Thumbnails, settings.ThumbnailsFolder);

    public string Export => Managed(FolderName.Export, settings.ExportFolder);

    public string QuickExport => Managed(FolderName.QuickExport, settings.QuickExportFolder);

    /// <summary>스캔 원본 TIFF 자리입니다. 캐시가 아니라 원본이라 캐시 지우기 대상이 아닙니다.</summary>
    public string Scans => Managed(FolderName.Scans, settings.ScansFolder);

    public string ImportedSources =>
        Managed(FolderName.ImportedSources, settings.ImportedSourcesFolder);

    public string CleanedRaw => Managed(FolderName.CleanedRaw, settings.CleanedRawFolder);

    public string ScanPreviews => Managed(FolderName.ScanPreviews, settings.ScanPreviewsFolder);

    /// <summary>지금 방식에서 쓰는 여덟 폴더를 모두 만듭니다. macOS <c>ensureCurrentFolders()</c>.</summary>
    public void EnsureAll()
    {
        foreach (string directory in All())
        {
            EnsureDirectory(directory);
        }
    }

    public IReadOnlyList<string> All() =>
    [
        Root, Thumbnails, Export, QuickExport, Scans,
        ImportedSources, CleanedRaw, ScanPreviews,
    ];

    /// <summary>폴더를 보장 생성하고 그대로 돌려줍니다(있으면 아무 것도 하지 않습니다).</summary>
    public static string EnsureDirectory(string path)
    {
        try
        {
            if (path.Length != 0)
            {
                Directory.CreateDirectory(path);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException or PathTooLongException)
        {
            // 쓸 때 다시 실패합니다. 설정창을 여는 것만으로 예외를 던지지는 않습니다.
        }
        return path;
    }

    /// <summary>
    /// 사용자 폴더를 <c>%USERPROFILE%</c> 대신 <c>~</c> 로 줄여 보여 줍니다. macOS
    /// <c>abbreviatingWithTildeInPath</c> 자리입니다 — 설정창에 사용자 이름이 그대로
    /// 박히지 않게 합니다.
    /// </summary>
    public static string Abbreviate(string path)
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (home.Length != 0 &&
            path.StartsWith(home, StringComparison.OrdinalIgnoreCase))
        {
            return string.Concat("~", path.AsSpan(home.Length));
        }
        return path;
    }

    private string Managed(string folderName, string customPath)
    {
        if (settings.LocationMode == DiskStorageLocationMode.Custom && customPath.Length != 0)
        {
            return customPath;
        }
        return Path.Combine(Root, folderName);
    }
}
