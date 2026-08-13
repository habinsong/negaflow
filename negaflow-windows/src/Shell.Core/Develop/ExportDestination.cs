using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 출력 패널이 들고 있는 내보내기 목적지입니다. 경로를 만드는 규칙을 XAML 이 아니라 여기 두어야
/// 파일명이 어떻게 정해지는지 UI 없이 시험됩니다.
/// </summary>
/// <remarks>
/// macOS 의 파일명 패턴 중 지금 지원하는 토큰은 <c>{name}</c> 하나입니다. 나머지 토큰은
/// 카탈로그가 아직 읽지 않는 값(촬영 일시, 순번, 스캐너)을 필요로 하므로 넣지 않았습니다 —
/// 무엇으로도 치환되지 않는 토큰을 내놓으면 사용자가 빈 파일명을 만들게 됩니다.
/// </remarks>
public sealed record ExportDestination(string FolderPath, string NamePattern, DevelopExportFormat Format)
{
    public const string NameToken = "{name}";

    public static string ExtensionFor(DevelopExportFormat format) =>
        format switch
        {
            DevelopExportFormat.Tiff16 => ".tif",
            DevelopExportFormat.Jpeg8 => ".jpg",
            _ => ".png",
        };

    /// <summary>패턴을 원본 이름으로 채운 파일명입니다. 확장자는 형식이 정합니다.</summary>
    public string FileNameFor(string sourcePath)
    {
        ArgumentException.ThrowIfNullOrEmpty(sourcePath);
        string stem = Path.GetFileNameWithoutExtension(sourcePath);
        string replaced = NamePattern.Replace(NameToken, stem, StringComparison.Ordinal).Trim();
        // 패턴이 비었거나 공백뿐이면 원본 이름으로 되돌립니다. 이름 없는 파일은 만들지 않습니다.
        string safe = Sanitize(string.IsNullOrEmpty(replaced) ? stem : replaced);
        return safe + ExtensionFor(Format);
    }

    /// <summary>실제로 쓸 전체 경로입니다. 폴더가 비어 있으면 원본 옆에 씁니다.</summary>
    public string PathFor(string sourcePath)
    {
        ArgumentException.ThrowIfNullOrEmpty(sourcePath);
        string folder = string.IsNullOrWhiteSpace(FolderPath)
            ? Path.GetDirectoryName(sourcePath) ?? Path.GetTempPath()
            : FolderPath;
        return Path.Combine(folder, FileNameFor(sourcePath));
    }

    private static string Sanitize(string value)
    {
        Span<char> buffer = value.Length <= 260 ? stackalloc char[value.Length] : new char[value.Length];
        ReadOnlySpan<char> invalid = Path.GetInvalidFileNameChars();
        for (int index = 0; index < value.Length; ++index)
        {
            buffer[index] = invalid.Contains(value[index]) ? '_' : value[index];
        }
        return new string(buffer).Trim();
    }
}
