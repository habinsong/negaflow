using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell;

public sealed partial class MainWindow
{
    private bool terminationInProgress;
    private bool terminationApproved;

    private async void OnAppWindowClosing(
        AppWindow sender,
        AppWindowClosingEventArgs args)
    {
        _ = sender;
        if (terminationApproved || libraryHost is null)
        {
            return;
        }

        args.Cancel = true;
        if (terminationInProgress)
        {
            return;
        }

        terminationInProgress = true;
        LibraryDefectTerminationResult result;
        try
        {
            // **셸이 없을 수 있습니다.** 카탈로그를 열지 못하면 셸 자리에 복구 화면만 서고
            // `ShellView` 는 끝까지 null 입니다(`MainWindow.Recovery.ShowRecovery`). 그런데 그
            // 상태에서도 `libraryHost` 는 null 이 아니라 위 가드를 통과하므로, 여기서 그냥
            // 부르면 닫을 때마다 `NullReferenceException` 으로 죽었습니다 — 실측으로
            // 복구 화면에서 창을 닫으면 `startup-fault.txt` 에 그 예외가 남습니다.
            if (ShellView is { } shell)
            {
                await shell.PrepareForTerminationAsync();
            }
            string scansDirectory = new DiskStorageLocations(
                settingsStore.Current.Disk).Scans;
            result = await libraryHost.PrepareForTerminationAsync(scansDirectory);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or InvalidOperationException or COMException or
            DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
        {
            result = new LibraryDefectTerminationResult(
                LibraryDefectTerminationError.NativeBakeFailed,
                NativeFailureName: error.GetType().Name);
        }

        // 실패했을 때만 남깁니다. 성공은 굽기 쪽이 이미 `defect bake ok …` 로 적었고,
        // 여기서 `None` 을 또 적으면 성공한 줄이 실패처럼 읽힙니다.
        if (!result.IsSuccess)
        {
            TerminationLog.Write(
                $"recipe save on quit failed: {result.Error}" +
                (result.FrameId is { Length: > 0 } frameId ? $" frame={frameId}" : string.Empty) +
                (result.NativeFailureName is { Length: > 0 } native
                    ? $" ({native})"
                    : string.Empty));
        }

        if (!result.IsSuccess)
        {
            terminationInProgress = false;
            if (Content is Microsoft.UI.Xaml.FrameworkElement root && root.XamlRoot is { } xamlRoot)
            {
                await new Microsoft.UI.Xaml.Controls.ContentDialog
                {
                    XamlRoot = xamlRoot,
                    Title = "Negaflow",
                    Content = Localization.AppResources.Get("developExportSaveFailed", "Text"),
                    CloseButtonText = Localization.AppResources.Get("commonDone", "Content"),
                }.ShowAsync();
            }
            return;
        }
        terminationApproved = true;
        terminationInProgress = false;
        Close();
    }
}
