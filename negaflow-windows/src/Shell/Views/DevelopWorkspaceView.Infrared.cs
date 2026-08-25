using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class DevelopWorkspaceView
{
    private void OnInfraredCleanStatusChanged(
        string frameId,
        InfraredCleanStatus status)
    {
        // 굽기는 스캔 워커에서 끝납니다. 그 스레드에서 XAML 을 건드리면 WinUI 가
        // `COMException` 을 던지고 배치가 통째로 끊깁니다(§22.1).
        if (DispatcherQueue is { } queue && !queue.HasThreadAccess)
        {
            _ = queue.TryEnqueue(() => OnInfraredCleanStatusChanged(frameId, status));
            return;
        }
        CaptureInfraredPresentation(frameId, status);
        if (panel?.InfraredClean.Update(frameId, status) != true)
        {
            return;
        }
        ExportStatusText.Text = InfraredCleanStatusText.For(status);
        RefreshAfterInfraredClean(frameId, status);
    }

    /// <summary>
    /// IR 굽기가 끝난 사진을 <b>다시 읽어</b> 목록과 그림에 얹습니다.
    /// </summary>
    /// <remarks>
    /// 스캔은 사진을 먼저 게시하고(그 순간 선택이 그 사진으로 옮겨 갑니다) 그 **뒤에**
    /// IR 을 굽습니다. 굽기가 끝나면 카탈로그에 IR 항목이 생기는데, 앞 판은 상태 글자만
    /// 바꾸고 스냅샷을 다시 읽지 않아 <b>GrainMend 목록에 IR 이 없고 그림도 IR 전</b>
    /// 이었습니다. 사용자가 겪은 "IR 스캔이 안 된다" 가 이것입니다.
    ///
    /// 가져오기 경로는 사용자가 고르기 전에 굽기가 끝나 있어 이 자리를 지나지 않습니다 —
    /// 그래서 그쪽은 멀쩡했고, 여기를 고쳐도 그쪽 동작은 달라지지 않습니다.
    /// </remarks>
    private void RefreshAfterInfraredClean(string frameId, InfraredCleanStatus status)
    {
        if (status.Message is not (InfraredCleanMessage.Applied or InfraredCleanMessage.NoDefects))
        {
            return;
        }
        if (panel?.SelectedFrame is not { } selected ||
            !string.Equals(selected.Id, frameId, StringComparison.Ordinal))
        {
            return;
        }
        // 카탈로그가 들고 있는 최신 스냅샷으로 다시 고릅니다. 같은 id 라도 레시피가 바뀌었으므로
        // 패널이 새 값을 읽어야 합니다.
        _ = panel.Select(frameId);
        GrainMendPanel.RefreshAfterExternalRecipeChange();
        RequestPreviewNow();
    }
}
