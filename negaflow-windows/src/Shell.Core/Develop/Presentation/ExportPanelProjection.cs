using System.Globalization;
using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 출력 패널이 한 번에 내는 값입니다. 뷰는 이 값을 컨트롤에 얹기만 합니다.
/// </summary>
public sealed record ExportPanelView(
    string ExportFolderPath,
    string QuickExportFolderPath,
    string ExportFileNamePreview,
    string QuickExportFileName,
    string SourceSummary,
    string ExportButtonText,
    bool CanExport);

/// <summary>
/// 출력 패널에 무엇을 낼지 정합니다. 화면 배치·이벤트와 다른 이유로 바뀌고(이름 패턴, 요약
/// 표기, 여러 장 선택 표시), 창을 띄우지 않고 확인할 수 있어야 하므로 뷰 밖에 둡니다.
/// 번역된 문구는 밖에서 받습니다.
/// </summary>
public static class ExportPanelProjection
{
    public static ExportPanelView Create(
        LibraryFrameSnapshot? frame,
        ExportSettings exportSettings,
        QuickExportSettings quickExportSettings,
        ExportNamingContext? namingContext,
        bool canExport,
        int selectedFrameCount,
        string besideSourceText,
        string exportTitle)
    {
        string exportFolder = FolderDisplay(exportSettings.FolderPath, besideSourceText);
        string quickFolder = FolderDisplay(quickExportSettings.FolderPath, besideSourceText);
        string preview = string.Empty;
        string quickName = string.Empty;
        string summary = string.Empty;
        if (frame is not null)
        {
            preview = namingContext is { } context
                ? exportSettings.Destination.FileNameFor(frame.SourcePath, context)
                : exportSettings.Destination.FileNameFor(frame.SourcePath);
            quickName = quickExportSettings.Destination.FileNameFor(frame.SourcePath);
            summary = DescribeSource(frame);
        }

        return new ExportPanelView(
            exportFolder,
            quickFolder,
            preview,
            quickName,
            summary,
            // 여러 장을 고르면 macOS 처럼 몇 장인지 단추에 적습니다.
            selectedFrameCount > 1
                ? string.Create(CultureInfo.CurrentCulture, $"{exportTitle} ({selectedFrameCount})")
                : exportTitle,
            canExport);
    }

    /// <summary>
    /// 소스 탭의 한 줄 요약입니다. macOS 는 여기에 스캔 DPI 도 적지만 Windows 카탈로그는 아직
    /// DPI 를 기록하지 않으므로 기록된 값만 냅니다.
    /// </summary>
    public static string DescribeSource(LibraryFrameSnapshot frame)
    {
        if (frame.SourceMetadata is not { IsValid: true } metadata)
        {
            return string.Empty;
        }
        return string.Create(
            CultureInfo.CurrentCulture,
            $"{metadata.PixelWidth}×{metadata.PixelHeight} px · {metadata.BitsPerSample}-bit");
    }

    /// <summary>
    /// 폴더 줄에 적을 이름입니다. macOS <c>exportFolderDisplay</c> ·
    /// <c>quickExportFolderDisplay</c> 와 같이 <b>마지막 한 칸</b>만 씁니다 - 한 줄에
    /// 전체 경로를 우겨넣으면 가운데가 잘려 어느 폴더인지 오히려 알 수 없습니다.
    /// 전체 경로는 그 줄의 도구 설명과 폴더 열기 단추가 알려 줍니다.
    /// </summary>
    private static string FolderDisplay(string folderPath, string besideSourceText)
    {
        if (string.IsNullOrWhiteSpace(folderPath))
        {
            return besideSourceText;
        }
        string trimmed = folderPath.TrimEnd(
            System.IO.Path.DirectorySeparatorChar,
            System.IO.Path.AltDirectorySeparatorChar);
        string name = System.IO.Path.GetFileName(trimmed);
        // 드라이브 뿌리("C:\\")는 마지막 칸이 비어 있습니다. 그때는 경로 그대로 적습니다.
        return name.Length > 0 ? name : folderPath;
    }
}
