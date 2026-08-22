using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;
using Windows.ApplicationModel.DataTransfer;

namespace Negaflow.Shell.Views.Library.Sources;

/// <summary>폴더 줄로 원본을 옮깁니다. 트리 그리기와 다른 이유입니다.</summary>
internal sealed class LibraryFilesSourceDrop
{
    /// <summary>
    /// 우리 카드에서 시작한 끌기인지 알아보는 표식입니다. 이것이 없으면 탐색기에서 끌어온
    /// 파일도 폴더 줄이 받아들입니다.
    /// </summary>
    internal const string FrameDragFormat = "negaflow.library-source";

    private readonly LibraryFilesSourceTree view;

    internal LibraryFilesSourceDrop(LibraryFilesSourceTree view) => this.view = view;

    /// <summary>
    /// 이 줄이 어느 폴더인지입니다. 폴더 머리줄은
    /// <see cref="LibraryFolderTreeView"/> 가 만들며 <c>Tag</c> 에 구역을 답니다 — 구역의
    /// <c>Id</c> 가 곧 폴더 경로입니다. 사진 줄에는 <c>Tag</c> 가 없어 null 이 나오고,
    /// 그래서 사진 위에는 놓을 수 없습니다.
    /// </summary>
    private static string? DestinationOf(object sender) =>
        sender is FrameworkElement { Tag: LibraryBrowserFolderSection section }
            ? section.Id
            : null;

    /// <summary>
    /// 폴더 줄 위에 있는 동안입니다. 우리 카드가 아니면 아무 표시도 내지 않습니다 — 밖에서 온
    /// 파일을 여기로 받으면 사용자는 가져오기가 될 것으로 읽습니다.
    /// </summary>
    internal void OnDragOver(object sender, DragEventArgs args)
    {
        args.AcceptedOperation =
            DestinationOf(sender) is not null &&
            string.Equals(args.DataView?.Properties.Title, FrameDragFormat, StringComparison.Ordinal)
                ? DataPackageOperation.Move
                : DataPackageOperation.None;
        args.Handled = true;
    }

    /// <summary>
    /// 원본 파일을 이 폴더로 옮깁니다. <b>원본을 실제로 옮기는 유일한 자리</b>이며, 파일 이동이
    /// 실패하면 카탈로그는 손대지 않습니다.
    /// </summary>
    internal async void OnDrop(object sender, DragEventArgs args)
    {
        if (DestinationOf(sender) is not { } destination ||
            view.libraryHost is not { } host ||
            args.DataView is not { } data ||
            !string.Equals(data.Properties.Title, FrameDragFormat, StringComparison.Ordinal))
        {
            return;
        }
        args.Handled = true;
        DragOperationDeferral deferral = args.GetDeferral();
        try
        {
            string payload = await data.GetTextAsync();
            var wanted = new HashSet<string>(
                payload.Split('\n', StringSplitOptions.RemoveEmptyEntries),
                StringComparer.Ordinal);
            LibraryFrameSnapshot[] frames = [.. host.Frames.Where(frame => wanted.Contains(frame.Id))];
            if (frames.Length == 0)
            {
                return;
            }
            SourceMoveOutcome outcome = host.MoveSources(frames, destination);
            view.RaiseStatus(outcome == SourceMoveOutcome.Moved
                ? string.Empty
                : AppResources.Get("librarySourceMoveFailed", "Text"));
            if (outcome == SourceMoveOutcome.Moved)
            {
                view.RaiseLibraryChanged();
            }
        }
        finally
        {
            deferral.Complete();
        }
    }
}
