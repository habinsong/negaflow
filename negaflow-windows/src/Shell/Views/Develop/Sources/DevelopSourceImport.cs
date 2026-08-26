using System.IO;
using Microsoft.UI.Xaml;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Sources;

/// <summary>
/// 현상 라이브러리 탭의 파일·폴더 가져오기입니다. 스캐너는 뷰가 설정 화면을 엽니다.
/// </summary>
internal sealed class DevelopSourceImport
{
    private readonly DevelopLibrarySourcePanel view;

    public DevelopSourceImport(DevelopLibrarySourcePanel view)
    {
        this.view = view;
    }

    internal async void OnImportClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.libraryHost is null || view.importWindowId is null)
        {
            return;
        }

        // Windows App SDK 1.8 의 picker 는 WindowId 를 받으므로 InitializeWithWindow 가
        // 필요 없습니다. 미패키지 구성에서도 그대로 동작합니다.
        Microsoft.Windows.Storage.Pickers.FileOpenPicker picker = new(view.importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("importSection", "Value"),
        };
        // Windows App SDK 기본값 *.*를 사용하고 실제 WIC/RAW decode로 raster를 판정합니다.

        view.SetImportActionsEnabled(false);
        try
        {
            IReadOnlyList<Microsoft.Windows.Storage.Pickers.PickFileResult> picked =
                await picker.PickMultipleFilesAsync();
            List<string> paths = [];
            foreach (Microsoft.Windows.Storage.Pickers.PickFileResult file in picked)
            {
                paths.Add(file.Path);
            }

            // 폴더 가져오기와 같습니다 - 프로세스는 적용을 눌러야 정해집니다.
            FrameImportPlan plan = view.libraryHost.Import(
                paths,
                DevelopmentProcess.DigitalColor);
            view.SetImportStatus(plan.Rows.Count > 0 ? null : FrameImport.Describe(plan));
            view.NotifyFramesImported();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            view.SetImportStatus(AppResources.Get("libraryImportFailed", "Text"));
        }
        finally
        {
            view.SetImportActionsEnabled(true);
        }
    }

    internal async void OnImportFolderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.libraryHost is null || view.importWindowId is null)
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FolderPicker picker = new(view.importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("importFolder", "Content"),
        };
        view.SetImportActionsEnabled(false);
        view.SetImportStatus(null);
        try
        {
            Microsoft.Windows.Storage.Pickers.PickFolderResult? picked =
                await picker.PickSingleFolderAsync();
            if (picked is null)
            {
                return;
            }
            FolderImportResult imported = view.libraryHost.ImportFolders(
                [picked.Path],
                // 가져오기는 **현상 프로세스를 정하지 않습니다.** 폴더 머리줄에서 고르고
                // 적용을 눌러야 정해집니다 - 예전에는 여기서 C-41 을 박아, 디지털 카메라
                // RAW 을 가져와도 필름 네거티브로 반전된 그림이 먼저 나왔습니다.
                // `DigitalColor` 는 `RenderedDigital` + `ColorPositive`, 곧 아무 필름
                // 프로세스도 걸지 않은 상태입니다.
                DevelopmentProcess.DigitalColor);
            view.SetImportStatus(imported.IsSuccess
                ? null
                : AppResources.Get("libraryImportFailed", "Text"));
            view.NotifyFramesImported();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            view.SetImportStatus(AppResources.Get("libraryImportFailed", "Text"));
        }
        finally
        {
            view.SetImportActionsEnabled(true);
        }
    }
}
