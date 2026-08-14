namespace Negaflow.Catalog;

/// <summary>
/// 촬영 기록입니다. 필름 카메라는 EXIF 를 남기지 않고, 스캔 파일에 적힌 카메라·렌즈·노출은
/// 스캐너의 것이지 그 사진을 찍은 카메라의 것이 아닙니다. 사용자가 적어 둔 값은 카탈로그에만
/// 살며 원본 파일은 건드리지 않습니다.
/// </summary>
public readonly record struct FilmShotMetadata(
    string? CameraMake = null,
    string? CameraModel = null,
    string? LensModel = null,
    string? FilmStock = null,
    int? IsoSpeed = null,
    double? ExposureTimeSeconds = null,
    double? FNumber = null,
    double? FocalLengthMm = null)
{
    /// <summary>노출 시간 상한(초)입니다. 이보다 긴 값은 오타로 보고 버립니다.</summary>
    public const double MaximumExposureTimeSeconds = 3600.0;

    public bool IsEmpty =>
        CameraMake is null && CameraModel is null && LensModel is null && FilmStock is null &&
        IsoSpeed is null && ExposureTimeSeconds is null && FNumber is null && FocalLengthMm is null;

    public bool IsValid =>
        this == Normalized();

    public FilmShotMetadata Normalized() => new(
        AppMetadataOverlay.NormalizeText(CameraMake),
        AppMetadataOverlay.NormalizeText(CameraModel),
        AppMetadataOverlay.NormalizeText(LensModel),
        AppMetadataOverlay.NormalizeText(FilmStock),
        IsoSpeed is > 0 ? IsoSpeed : null,
        NormalizeExposureTime(ExposureTimeSeconds),
        NormalizePositive(FNumber),
        NormalizePositive(FocalLengthMm));

    private static double? NormalizeExposureTime(double? value) =>
        value is { } seconds && double.IsFinite(seconds) &&
        seconds > 0 && seconds <= MaximumExposureTimeSeconds
            ? seconds
            : null;

    private static double? NormalizePositive(double? value) =>
        value is { } number && double.IsFinite(number) && number > 0 ? number : null;
}

/// <summary>
/// 사용자가 적어 두는 사진 메타데이터입니다. macOS <c>AppMetadataOverlay</c> 와 같은 키·같은
/// 한계이며, 원본 파일이 아니라 카탈로그에만 삽니다.
/// </summary>
public sealed record AppMetadataOverlay
{
    public const int CurrentVersion = 1;

    public const int MaximumTextBytes = 4096;

    public const int MaximumKeywords = 128;

    public string? Title { get; init; }

    public string? Caption { get; init; }

    public IReadOnlyList<string> Keywords { get; init; } = [];

    public string? Copyright { get; init; }

    public FilmShotMetadata? FilmShot { get; init; }

    /// <summary>쓸 때마다 오릅니다. 0 은 아직 쓴 적이 없다는 뜻입니다.</summary>
    public ulong Revision { get; init; }

    public DateTimeOffset UpdatedAt { get; init; } = DateTimeOffset.UnixEpoch;

    public bool IsEmpty =>
        Title is null && Caption is null && Keywords.Count == 0 && Copyright is null &&
        (FilmShot?.IsEmpty ?? true);

    public bool IsValid =>
        Revision > 0 &&
        Title == NormalizeText(Title) &&
        Caption == NormalizeText(Caption) &&
        Copyright == NormalizeText(Copyright) &&
        Keywords.SequenceEqual(NormalizeKeywords(Keywords), StringComparer.Ordinal) &&
        (FilmShot is not { } shot || (!shot.IsEmpty && shot.IsValid));

    public AppMetadataOverlay Normalized() => this with
    {
        Title = NormalizeText(Title),
        Caption = NormalizeText(Caption),
        Copyright = NormalizeText(Copyright),
        Keywords = NormalizeKeywords(Keywords),
        FilmShot = FilmShot is { } shot && !shot.Normalized().IsEmpty ? shot.Normalized() : null,
    };

    /// <summary>앞뒤 공백을 걷고, 비었거나 너무 길면 값이 없는 것으로 봅니다.</summary>
    public static string? NormalizeText(string? value)
    {
        string trimmed = (value ?? string.Empty).Trim();
        return trimmed.Length == 0 ||
            System.Text.Encoding.UTF8.GetByteCount(trimmed) > MaximumTextBytes
            ? null
            : trimmed;
    }

    /// <summary>중복과 빈 칸을 걷고 macOS 와 같은 개수 상한을 겁니다. 적은 순서는 지킵니다.</summary>
    public static IReadOnlyList<string> NormalizeKeywords(IEnumerable<string>? keywords)
    {
        if (keywords is null)
        {
            return [];
        }
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var result = new List<string>();
        foreach (string keyword in keywords)
        {
            if (NormalizeText(keyword) is { } normalized && seen.Add(normalized))
            {
                result.Add(normalized);
                if (result.Count == MaximumKeywords)
                {
                    break;
                }
            }
        }
        return result;
    }
}
