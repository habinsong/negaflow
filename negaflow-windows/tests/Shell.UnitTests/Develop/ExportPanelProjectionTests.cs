using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 출력 패널이 무엇을 내는지입니다. 이 계약은 `DevelopWorkspaceView` 안에 있을 때는 창을
/// 띄우지 않고 확인할 수 없었습니다.
/// </summary>
internal static class ExportPanelProjectionTests
{
    public static void Run()
    {
        VerifyFolderFallback();
        VerifyExportButtonCount();
        VerifySourceSummary();
        VerifyNoSelectedFrame();
    }

    private static ExportPanelView Project(
        LibraryFrameSnapshot? frame,
        ExportSettings? exportSettings = null,
        QuickExportSettings? quickSettings = null,
        bool canExport = true,
        int selectedFrameCount = 1) =>
        ExportPanelProjection.Create(
            frame,
            exportSettings ?? new ExportSettings(),
            quickSettings ?? new QuickExportSettings(),
            namingContext: null,
            canExport,
            selectedFrameCount,
            "원본 옆",
            "내보내기");

    private static void VerifyFolderFallback()
    {
        ExportPanelView blank = Project(null);
        Check(blank.ExportFolderPath == "원본 옆" && blank.QuickExportFolderPath == "원본 옆",
            "export_panel_says_beside_source_when_no_folder_is_set");
        ExportPanelView chosen = Project(
            null,
            new ExportSettings { FolderPath = @"D:\Export" },
            new QuickExportSettings { FolderPath = @"D:\Quick" });
        Check(chosen.ExportFolderPath == @"D:\Export" &&
            chosen.QuickExportFolderPath == @"D:\Quick",
            "export_panel_shows_the_chosen_folders");
        // 공백만 적힌 경로는 고른 것으로 치지 않습니다.
        Check(Project(null, new ExportSettings { FolderPath = "   " }).ExportFolderPath == "원본 옆",
            "export_panel_treats_blank_as_unset");
    }

    private static void VerifyExportButtonCount()
    {
        Check(Project(null, selectedFrameCount: 1).ExportButtonText == "내보내기",
            "export_button_stays_plain_for_one_frame");
        Check(Project(null, selectedFrameCount: 0).ExportButtonText == "내보내기",
            "export_button_stays_plain_for_no_selection");
        // macOS 는 여러 장을 고르면 몇 장인지 단추에 적습니다.
        Check(Project(null, selectedFrameCount: 7).ExportButtonText == "내보내기 (7)",
            "export_button_counts_a_multiple_selection");
        Check(!Project(null, canExport: false).CanExport && Project(null).CanExport,
            "export_panel_carries_the_export_availability");
    }

    private static void VerifySourceSummary()
    {
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2));
        // 기록된 원본 정보가 없으면 지어내지 않고 비웁니다.
        Check(ExportPanelProjection.DescribeSource(frame) == string.Empty,
            "export_summary_stays_empty_without_source_metadata");
        LibraryFrameSnapshot measured = frame with
        {
            SourceMetadata = new LibrarySourceMetadata(
                FileBytes: 103_825_968,
                PixelWidth: 5088,
                PixelHeight: 3401,
                SamplesPerPixel: 3,
                BitsPerSample: 16,
                SampleFormat: 1,
                Orientation: 1),
        };
        Check(ExportPanelProjection.DescribeSource(measured) == "5088×3401 px · 16-bit",
            "export_summary_reports_the_recorded_pixels_and_depth");
    }

    private static void VerifyNoSelectedFrame()
    {
        ExportPanelView view = Project(null);
        Check(view.ExportFileNamePreview.Length == 0 &&
            view.QuickExportFileName.Length == 0 &&
            view.SourceSummary.Length == 0,
            "export_panel_shows_no_file_names_without_a_frame");
        ExportPanelView withFrame = Project(Frame(new ManualBaseRgb(0.2, 0.2, 0.2)));
        Check(withFrame.ExportFileNamePreview.Length > 0 &&
            withFrame.QuickExportFileName.Length > 0,
            "export_panel_previews_a_file_name_for_the_selected_frame");
    }
}
