using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;
using Negaflow.Shell.Views;

namespace Negaflow.Shell.Views.Print.Export;

/// <summary>
/// 판을 폴더에 씁니다. 폴더는 macOS 처럼 사용자가 고릅니다.
/// </summary>
internal sealed class PrintExportWorkflow
{
    private readonly Button exportButton;
    private readonly TextBlock statusText;
    private readonly Panel rasterHost;
    private Microsoft.UI.WindowId? windowId;

    internal PrintExportWorkflow(Button exportButton, TextBlock statusText, Panel rasterHost)
    {
        this.exportButton = exportButton;
        this.statusText = statusText;
        this.rasterHost = rasterHost;
    }

    /// <summary>폴더 선택기는 자기가 어느 창에 붙을지 알아야 합니다.</summary>
    internal void AttachWindow(Microsoft.UI.WindowId id) => windowId = id;

    /// <summary>인화 프로파일 고르기 대화상자를 이 창에 답니다.</summary>
    internal Microsoft.UI.WindowId? WindowId => windowId;

    internal async void Export(
        WorkspacePresentationState? state,
        IReadOnlyList<LibraryFrameSnapshot> sources)
    {
        if (state is null || windowId is not { } id)
        {
            return;
        }
        if (sources.Count == 0)
        {
            return;
        }
        // 디스크 탭의 "내보내기 폴더"에서 시작합니다 — 매번 처음부터 찾아 들어가지 않도록.
        Microsoft.Windows.Storage.Pickers.FolderPicker picker = new(id)
        {
            SuggestedStartLocation =
                Microsoft.Windows.Storage.Pickers.PickerLocationId.DocumentsLibrary,
        };
        if (await picker.PickSingleFolderAsync() is not { } folder)
        {
            return;
        }
        exportButton.IsEnabled = false;
        statusText.Text = string.Empty;
        try
        {
            PrintSheetWriteResult result = await PrintSheetWriter.WriteAsync(
                sources,
                state.Current.Print,
                folder.Path,
                LibraryFrameNaming.DisplayName(sources[0]),
                rasterHost);
            statusText.Text = result.IsSuccess
                ? AppResources
                    .Get("printExportDone", "Text")
                    .Replace("{0}", folder.Path, StringComparison.Ordinal)
                : AppResources.Get("printExportFailed", "Text");
        }
        finally
        {
            exportButton.IsEnabled = true;
        }
    }
}
