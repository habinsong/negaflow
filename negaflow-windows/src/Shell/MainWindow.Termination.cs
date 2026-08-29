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
            await ShellView.PrepareForTerminationAsync();
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
                $"defect bake on quit failed: {result.Error}" +
                (result.FrameId is { Length: > 0 } frameId ? $" frame={frameId}" : string.Empty) +
                (result.NativeFailureName is { Length: > 0 } native
                    ? $" ({native})"
                    : string.Empty));
        }

        // **실패해도 닫습니다.**
        //
        // macOS `applicationShouldTerminate` 은 어느 갈래로 가든 종료합니다 — 굽기가
        // 실패하면 `saveLibraryOnTerminate()` 로 카탈로그를 저장하고
        // `reply(toApplicationShouldTerminate: true)` 를 보냅니다(`AppEntry.swift`).
        // 굽지 못한 결함 편집은 카탈로그에 그대로 남으므로 잃는 것이 없고, 다음에 열면
        // 다시 시도합니다.
        //
        // 윈도우는 성공했을 때만 닫고 실패하면 모달을 띄웠습니다. 그 창은 닫기 단추뿐이라
        // **앱을 아예 끝낼 수 없었습니다** — 실기에서 "GrainMend / 현상 프로세스를 저장하지
        // 못했습니다" 가 뜨고 종료가 막혔습니다. 실패 사유는 개발자 모드에서만 켜지는
        // 기록에만 적혀 있어 왜 막혔는지 볼 수도 없었습니다.
        if (!result.IsSuccess)
        {
            _ = libraryHost.SaveIfDirty();
        }
        terminationApproved = true;
        terminationInProgress = false;
        Close();
    }
}
