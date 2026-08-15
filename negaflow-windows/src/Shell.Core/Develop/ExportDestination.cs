using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 출력 패널이 들고 있는 내보내기 목적지입니다. 경로를 만드는 규칙을 XAML 이 아니라 여기 두어야
/// 파일명이 어떻게 정해지는지 UI 없이 시험됩니다.
/// </summary>
/// <remarks>
/// 지원 토큰과 그 문법은 <see cref="ExportNamingTemplate"/> 이 정합니다. 여기서는 그 결과를
/// 형식별 확장자와 붙여 실제 경로를 만들 뿐입니다.
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
    public string FileNameFor(string sourcePath, int sequence = 0, string preset = "") =>
        FileNameFor(sourcePath, new ExportNamingContext(string.Empty, preset, sequence));

    /// <summary>롤 토큰까지 채운 파일명입니다. frame 이름은 원본에서 옵니다.</summary>
    public string FileNameFor(string sourcePath, ExportNamingContext context)
    {
        ArgumentException.ThrowIfNullOrEmpty(sourcePath);
        string stem = Path.GetFileNameWithoutExtension(sourcePath);
        // 부르는 쪽이 이름을 정해 두었으면 그것을 씁니다 — macOS 는 카드 이름으로 내보냅니다.
        // 정하지 않은 자리(원본 경로만 아는 짧은 호출)에서는 파일 이름으로 물러납니다.
        string? rendered = ExportNamingTemplate.Render(
            NamePattern,
            context.FrameName.Length == 0 ? context with { FrameName = stem } : context);
        // 패턴이 비었거나 잘못됐으면 원본 이름으로 되돌립니다. 이름 없는 파일은 만들지 않습니다.
        return (rendered ?? ExportNamingTemplate.SanitizeComponent(stem)) + ExtensionFor(Format);
    }

    /// <summary>실제로 쓸 전체 경로입니다. 폴더가 비어 있으면 원본 옆에 씁니다.</summary>
    public string PathFor(string sourcePath, int sequence = 0, string preset = "") =>
        PathFor(sourcePath, new ExportNamingContext(string.Empty, preset, sequence));

    public string PathFor(string sourcePath, ExportNamingContext context)
    {
        ArgumentException.ThrowIfNullOrEmpty(sourcePath);
        string folder = string.IsNullOrWhiteSpace(FolderPath)
            ? Path.GetDirectoryName(sourcePath) ?? Path.GetTempPath()
            : FolderPath;
        return Path.Combine(folder, FileNameFor(sourcePath, context));
    }
}
