using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Host;

/// <summary>파일·폴더 가져오기와 원본 다시 찾기입니다. 격자 오케스트레이션과 다른 이유입니다.</summary>
internal sealed class LibraryImportActions
{
    private readonly LibraryWorkspaceView view;

    internal LibraryImportActions(LibraryWorkspaceView view) => this.view = view;

    internal async void OnImagesClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.libraryHost is null || view.importWindowId is null)
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FileOpenPicker picker = new(view.importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("importSection", "Value"),
        };
        foreach (string extension in ImageSourcePaths.SupportedImportExtensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

        SetBusy(false);
        view.ImportStatusText.Text = string.Empty;
        try
        {
            IReadOnlyList<Microsoft.Windows.Storage.Pickers.PickFileResult> picked =
                await picker.PickMultipleFilesAsync();
            List<string> paths = [];
            foreach (Microsoft.Windows.Storage.Pickers.PickFileResult file in picked)
            {
                paths.Add(file.Path);
            }
            _ = view.libraryHost.Import(paths, DevelopmentProcess.C41);
            view.ShowLibrary(view.libraryHost, view.importWindowId.Value);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            view.ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
        }
        finally
        {
            SetBusy(true);
        }
    }

    internal async void OnFoldersClicked(object sender, RoutedEventArgs args)
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

        SetBusy(false);
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
            if (!imported.IsSuccess)
            {
                view.ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
                return;
            }
            view.ImportStatusText.Text = AppResources.FormatIntegers(
                "libraryFolderImportResult",
                "Text",
                imported.AddedFrameCount,
                imported.AddedFolderCount);
            view.ShowLibrary(view.libraryHost, view.importWindowId.Value);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            view.ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
        }
        finally
        {
            SetBusy(true);
        }
    }

    internal async void OnLocateOriginalClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (view.libraryHost is null || view.importWindowId is null ||
            sender is not Button { Tag: LibraryFrameListItem item })
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FileOpenPicker picker = new(view.importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("libraryLocateOriginal", "Content"),
        };
        foreach (string extension in ImageSourcePaths.SupportedImportExtensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

        try
        {
            Microsoft.Windows.Storage.Pickers.PickFileResult? picked = await picker.PickSingleFileAsync();
            if (picked is null)
            {
                return;
            }
            SourceRelinkPlan? plan = SourceRelinkPlanner.FilePlan(item.Frame.SourcePath, picked.Path);
            if (plan is null || !view.libraryHost.Relink(plan).IsSuccess)
            {
                view.ImportStatusText.Text = AppResources.Get("libraryRelinkFailed", "Text");
                return;
            }
            view.ShowLibrary(view.libraryHost, view.importWindowId.Value);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            view.ImportStatusText.Text = AppResources.Get("libraryRelinkFailed", "Text");
        }
    }

    internal async void OnLocateFolderClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (view.libraryHost is null || view.importWindowId is null ||
            sender is not Button { Tag: LibraryBrowserFolderSection { IsRegistered: true } section })
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FolderPicker picker = new(view.importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("libraryLocateFolder", "Content"),
        };
        try
        {
            Microsoft.Windows.Storage.Pickers.PickFolderResult? picked =
                await picker.PickSingleFolderAsync();
            if (picked is null)
            {
                return;
            }

            SourceRelinkPlan plan = SourceRelinkPlanner.FolderPlan(
                section.Id,
                picked.Path,
                view.libraryHost.Frames);
            if (!view.libraryHost.Relink(plan).IsSuccess)
            {
                view.ImportStatusText.Text = AppResources.Get("libraryFolderRelinkFailed", "Text");
                return;
            }
            view.ShowLibrary(view.libraryHost, view.importWindowId.Value);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            view.ImportStatusText.Text = AppResources.Get("libraryFolderRelinkFailed", "Text");
        }
    }

    private void SetBusy(bool enabled)
    {
        view.ImportImagesButton.IsEnabled = enabled;
        view.EmptyImportImagesButton.IsEnabled = enabled;
        view.ImportFoldersButton.IsEnabled = enabled;
    }
}
