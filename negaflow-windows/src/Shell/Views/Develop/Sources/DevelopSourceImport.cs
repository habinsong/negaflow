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
        foreach (string extension in ImageSourcePaths.SupportedImportExtensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

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

            FrameImportPlan plan = view.libraryHost.Import(paths, DevelopmentProcess.C41);
            view.ImportStatusText.Text = FrameImport.Describe(plan);
            view.NotifyFramesImported();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            view.ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
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
        view.ImportStatusText.Text = string.Empty;
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
                DevelopmentProcess.C41);
            view.ImportStatusText.Text = imported.IsSuccess
                ? AppResources.FormatIntegers(
                    "libraryFolderImportResult",
                    "Text",
                    imported.AddedFrameCount,
                    imported.AddedFolderCount)
                : AppResources.Get("libraryImportFailed", "Text");
            view.NotifyFramesImported();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            view.ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
        }
        finally
        {
            view.SetImportActionsEnabled(true);
        }
    }
}
