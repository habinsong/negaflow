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
            DevelopImportedFrames(imported.AddedFrameCount);
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

    /// <summary>
    /// macOS <c>developImportedFramesSequentially</c> 자리입니다. 설정 · 워크플로의
    /// "새로 가져온 사진 자동 현상" 이 켜져 있으면, 방금 들어온 프레임을 사용자가 열기
    /// 전에 미리 현상해 둡니다. 꺼져 있으면 예전처럼 열 때 현상합니다.
    /// </summary>
    private void DevelopImportedFrames(int addedFrameCount)
    {
        if (addedFrameCount <= 0 ||
            view.workspaceState is not { } state ||
            !state.Current.DevelopsImportsAutomatically ||
            view.thumbnails is not { } cache ||
            view.libraryHost is not { } host)
        {
            return;
        }
        // 방금 들어온 것은 목록의 끝입니다. 카탈로그 전체를 다시 현상하지 않습니다.
        foreach (LibraryFrameSnapshot frame in host.Frames.TakeLast(addedFrameCount))
        {
            cache.Request(frame);
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

    /// <summary>
    /// macOS <c>presentRelinkFolderPanel(_:)</c> — 사라진 폴더를 새 자리로 다시 잇습니다.
    /// 좌측 폴더 트리의 우클릭 메뉴에서만 부릅니다(격자 머리줄에는 macOS 에도 없습니다).
    /// </summary>
    internal async void LocateFolder(string folderPath)
    {
        if (view.libraryHost is null || view.importWindowId is null ||
            string.IsNullOrWhiteSpace(folderPath))
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
                folderPath,
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
