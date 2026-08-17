using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Sources;

/// <summary>
/// 라이브러리 폴더 투영을 TreeView 노드로 옮깁니다. Files 탭과 Library 탭이 같은 줄을 씁니다.
/// </summary>
internal static class DevelopSourceFolderTree
{
    public static void AddFolderNodes(
        TreeView tree,
        IEnumerable<LibraryBrowserFolderSection> sections)
    {
        foreach (LibraryBrowserFolderSection section in sections)
        {
            var folder = new TreeViewNode
            {
                Content = LibrarySourceNode.Folder(
                    section.Title,
                    AppResources.FormatIntegers("libraryFolderFrameCount", "Text", section.Count)),
            };
            foreach (LibraryFrameListItem item in section.Items)
            {
                folder.Children.Add(new TreeViewNode
                {
                    Content = LibrarySourceNode.Frame(item.DisplayName, item.Id),
                });
            }
            tree.RootNodes.Add(folder);
        }
    }

    public static bool TryGetFrameId(TreeViewItemInvokedEventArgs args, out string frameId)
    {
        if (args.InvokedItem is TreeViewNode { Content: LibrarySourceNode node } &&
            node.FrameId is { } id)
        {
            frameId = id;
            return true;
        }

        frameId = string.Empty;
        return false;
    }
}
