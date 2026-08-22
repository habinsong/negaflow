using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Library.Host;

/// <summary>사진 편집·되돌리기·이름 바꾸기입니다. 컨텍스트 메뉴 구성과 다른 이유입니다.</summary>
internal sealed class LibraryFrameActions
{
    private readonly LibraryWorkspaceView view;

    internal LibraryFrameActions(LibraryWorkspaceView view) => this.view = view;

    /// <summary>
    /// 같은 원본을 가리키는 사진을 하나 더 만듭니다. 만든 사본을 바로 고릅니다 — macOS 도
    /// 그렇게 하며, 그래야 다음 조정이 사본에 걸립니다.
    /// </summary>
    internal void CreateVirtualCopy(LibraryFrameListItem item)
    {
        if (view.libraryHost is not { } host || host.CreateVirtualCopy(item.Id) is not { } copyId)
        {
            return;
        }
        view.ShowLibrary(host, view.importWindowId ?? default);
        LibraryFrameListItem? created = view.FrameListView.Items
            .OfType<LibraryFrameListItem>()
            .FirstOrDefault(candidate => candidate.Id == copyId);
        if (created is not null)
        {
            view.FrameListView.SelectedItem = created;
            view.FrameListView.ScrollIntoView(created);
        }
    }

    internal void SetRating(IReadOnlyList<LibraryFrameListItem> targets, int rating)
    {
        ApplyEdit(targets, frame =>
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, Rating: rating));
    }

    internal void SetPickState(
        IReadOnlyList<LibraryFrameListItem> targets,
        FramePickState pickState)
    {
        ApplyEdit(targets, frame =>
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, PickState: pickState));
    }

    /// <summary>
    /// 여러 장에 같은 편집을 겁니다. 저장은 한 번만 합니다 — 200장을 고르고 별점을 주면
    /// catalog 를 200번 쓰게 되어 눈에 보이게 멈춥니다.
    /// </summary>
    internal void ApplyEdit(
        IReadOnlyList<LibraryFrameListItem> targets,
        Func<LibraryFrameSnapshot, LibraryFrameEdit> makeEdit)
    {
        if (view.libraryHost is null || targets.Count == 0)
        {
            return;
        }
        bool changed = false;
        foreach (LibraryFrameListItem target in targets)
        {
            if (view.libraryHost.Edit(target.Frame.Id, makeEdit(target.Frame)) ==
                LibraryFrameError.None)
            {
                changed = true;
            }
        }
        if (changed && view.libraryHost.Save() == CatalogStoreError.None)
        {
            view.ShowLibrary(view.libraryHost, view.importWindowId ?? default);
        }
    }

    internal void AddToCollection(
        string collectionId,
        IReadOnlyList<LibraryFrameListItem> targets)
    {
        if (view.libraryHost?.Collections.FirstOrDefault(collection =>
                string.Equals(collection.Id, collectionId, StringComparison.Ordinal))
            is not { } existing)
        {
            return;
        }
        // 이미 들어 있는 사진은 다시 넣지 않습니다. 넣으면 같은 사진이 두 번 보입니다.
        List<string> frameIds = [.. existing.FrameIds];
        var present = new HashSet<string>(frameIds, StringComparer.Ordinal);
        foreach (LibraryFrameListItem target in targets)
        {
            if (present.Add(target.Id))
            {
                frameIds.Add(target.Id);
            }
        }
        if (frameIds.Count == existing.FrameIds.Count)
        {
            return;
        }
        if (view.libraryHost.SetCollectionFrames(collectionId, frameIds))
        {
            view.ControlsPanel.CollectionsPanel.Rebuild();
            view.ShowFilteredItems();
        }
    }

    internal void RemoveFromCollection(
        string collectionId,
        IReadOnlyList<LibraryFrameListItem> targets)
    {
        if (view.libraryHost?.Collections.FirstOrDefault(collection =>
                string.Equals(collection.Id, collectionId, StringComparison.Ordinal))
            is not { } existing)
        {
            return;
        }
        var removing = new HashSet<string>(
            targets.Select(target => target.Id),
            StringComparer.Ordinal);
        List<string> frameIds = [.. existing.FrameIds.Where(id => !removing.Contains(id))];
        if (frameIds.Count == existing.FrameIds.Count)
        {
            return;
        }
        if (view.libraryHost.SetCollectionFrames(collectionId, frameIds))
        {
            view.ControlsPanel.CollectionsPanel.Rebuild();
            view.ShowFilteredItems();
        }
    }

    /// <summary>
    /// 원본이 있는 폴더를 열고 그 파일을 고릅니다. macOS 의 "Finder 에서 보기" 와 같은 자리이며,
    /// <b>원본을 열지 않습니다</b> — 여는 것은 다른 프로그램의 일입니다.
    /// </summary>
    internal static void ShowInExplorer(LibraryFrameListItem item)
    {
        string path = item.Frame.SourcePath;
        if (!File.Exists(path))
        {
            return;
        }
        _ = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = "explorer.exe",
            // 인용은 반드시 있어야 합니다. 공백이 든 경로가 인용 없이 가면 탐색기는 엉뚱한
            // 폴더를 열고 아무 말도 하지 않습니다.
            Arguments = $"/select,\"{path}\"",
            UseShellExecute = true,
        });
    }

    /// <summary>
    /// 사진을 라이브러리에서 뺍니다. <b>묻지 않습니다</b> — macOS 처럼 곧바로 빼고 되돌릴 수 있다고
    /// 알립니다. 되돌리기가 붙기 전에는 물어봤지만, 물음은 되돌리기의 대용품이었을 뿐입니다.
    /// </summary>
    internal void RemoveFromLibrary(IReadOnlyList<LibraryFrameListItem> targets)
    {
        if (view.libraryHost is not { } host || targets.Count == 0)
        {
            return;
        }
        int removed = host.RemoveFrames(targets.Select(target => target.Id));
        if (removed == 0)
        {
            return;
        }
        // 썸네일은 지우지 않습니다. 되돌리면 그 사진이 다시 오고, 그때 다시 만들게 하면
        // 되살아난 격자가 한동안 빈 칸으로 보입니다.
        view.ControlsPanel.CollectionsPanel.Rebuild();
        view.ShowLibrary(host, view.importWindowId ?? default);
        view.ControlsPanel.ImportStatusText.Text = AppResources.FormatIntegers(
            "libraryRemovalUndoFormat",
            "Text",
            removed);
    }

    /// <summary>
    /// 한 단계 되돌리고 무엇을 되돌렸는지 알립니다. 조용히 되돌리면 사용자는 무엇이 바뀌었는지
    /// 격자에서 찾아내야 합니다.
    /// </summary>
    internal bool Undo(bool redo)
    {
        if (view.libraryHost is not { } host)
        {
            return false;
        }
        string? actionKey = redo ? host.Redo() : host.Undo();
        if (actionKey is null)
        {
            return false;
        }
        view.ControlsPanel.CollectionsPanel.Rebuild();
        view.ShowLibrary(host, view.importWindowId ?? default);
        view.ControlsPanel.ImportStatusText.Text = AppResources
            .Get("libraryUndoneFormat", "Text")
            .Replace("{0}", ActionDisplayName(actionKey), StringComparison.Ordinal);
        return true;
    }

    /// <summary>
    /// 되돌린 동작의 이름입니다. 카탈로그 쪽은 리소스 키만 알고, 번역은 셸이 붙입니다.
    /// </summary>
    internal static string ActionDisplayName(string actionKey) => actionKey switch
    {
        LibraryHostService.UndoActions.RemoveFrames =>
            AppResources.Get("libraryRemoveFromLibrary", "Content"),
        LibraryHostService.UndoActions.CreateCollection =>
            AppResources.Get("libraryNewCollection", "Content"),
        LibraryHostService.UndoActions.RenameCollection =>
            AppResources.Get("libraryRename", "Content"),
        LibraryHostService.UndoActions.EditCollection =>
            AppResources.Get("libraryAddToCollection", "Text"),
        LibraryHostService.UndoActions.DeleteCollection =>
            AppResources.Get("libraryDelete", "Content"),
        LibraryHostService.UndoActions.VirtualCopy =>
            AppResources.Get("libraryVirtualCopy", "Content"),
        LibraryHostService.UndoActions.CreateStack =>
            AppResources.Get("libraryStackGroup", "Content"),
        LibraryHostService.UndoActions.UngroupStack =>
            AppResources.Get("libraryStackUngroup", "Content"),
        LibraryHostService.UndoActions.ResetAdjustments =>
            AppResources.Get("shortcutResetAdjustments", "Text"),
        LibraryHostService.UndoActions.DevelopAdjustment =>
            AppResources.Get("developAdjustment", "Text"),
        LibraryHostService.UndoActions.DefectEdit =>
            AppResources.Get("developGrainMend", "Text"),
        _ => AppResources.Get("libraryStackCollapse", "Content"),
    };

    /// <summary>
    /// 사진 번호를 바꿉니다. macOS 와 같이 이름이 아니라 <b>번호</b>를 받습니다 — 라이브러리의
    /// 이름은 폴더 안의 순번이기 때문입니다.
    /// </summary>
    internal async void Rename(LibraryFrameListItem item)
    {
        if (view.libraryHost is null)
        {
            return;
        }
        TextBox field = new()
        {
            PlaceholderText = AppResources.Get("libraryPhotoName", "Text"),
            Text = LibraryFrameNaming.EditableNumberText(item.Frame),
        };
        AutomationProperties.SetName(field, field.PlaceholderText);
        AutomationProperties.SetAutomationId(field, "negaflow.photo-number-field");
        // macOS 는 숫자가 아닌 글자를 입력 즉시 지웁니다. 확인 단추에서만 막으면 사용자는
        // 무엇이 잘못됐는지 모른 채 눌리지 않는 단추를 봅니다.
        field.TextChanged += (_, _) =>
        {
            string digits = new([.. field.Text.Where(char.IsAsciiDigit)]);
            if (!string.Equals(digits, field.Text, StringComparison.Ordinal))
            {
                int caret = field.SelectionStart;
                field.Text = digits;
                field.SelectionStart = Math.Min(caret, digits.Length);
            }
        };
        ContentDialog dialog = new()
        {
            XamlRoot = view.XamlRoot,
            Title = AppResources.Get("libraryRenamePhoto", "Content"),
            Content = field,
            PrimaryButtonText = AppResources.Get("libraryRename", "Content"),
            CloseButtonText = AppResources.Get("commonCancel", "Content"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }
        if (!int.TryParse(
                field.Text,
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out int number) ||
            !LibraryFrameNaming.IsNumberAvailable(view.libraryHost.Frames, item.Frame, number))
        {
            return;
        }
        // 같은 원본을 가리키는 사진들은 함께 번호가 바뀝니다 — macOS 도 원본 경로로 묶습니다.
        DisplayNameSelection selection = LibraryFrameNaming.NumberSelection(number);
        bool changed = false;
        foreach (LibraryFrameSnapshot frame in view.libraryHost.Frames)
        {
            if (!string.Equals(
                    frame.SourcePath,
                    item.Frame.SourcePath,
                    StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (view.libraryHost.Edit(
                    frame.Id,
                    new LibraryFrameEdit(
                        frame.Tone,
                        frame.ManualBase,
                        DisplayName: selection)) == LibraryFrameError.None)
            {
                changed = true;
            }
        }
        if (changed && view.libraryHost.Save() == CatalogStoreError.None)
        {
            view.ShowLibrary(view.libraryHost, view.importWindowId ?? default);
        }
    }

    internal void OnRatingCommitted(object? sender, int rating)
    {
        if (view.libraryHost is null ||
            sender is not FrameRatingStars { Tag: LibraryFrameListItem item })
        {
            return;
        }
        LibraryFrameSnapshot frame = item.Frame;
        LibraryFrameError error = view.libraryHost.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, Rating: rating));
        if (error != LibraryFrameError.None || view.libraryHost.Save() != CatalogStoreError.None)
        {
            // 저장에 실패했으면 화면도 되돌립니다 — 다음 실행에서 사라질 값을 남기지 않습니다.
            ((FrameRatingStars)sender).Rating = frame.Rating;
            return;
        }
        view.ShowLibrary(view.libraryHost, view.importWindowId ?? default);
    }
}
