namespace Negaflow.Shell.Views.Library.Sources;

/// <summary>
/// 좌측 "파일" 탭의 접기 상태를 셸 설정에 묶습니다.
/// </summary>
/// <remarks>
/// 라이브러리 · 현상 · 인화가 <b>같은 목록</b>을 보므로 접기 상태도 한 벌입니다. 화면마다
/// 따로 기억하면 같은 폴더가 여기서는 접히고 저기서는 펼쳐집니다. 설정에 담기 때문에 앱을
/// 다시 켜도 그대로입니다.
/// </remarks>
internal static class LibraryFolderTreeBinding
{
    /// <summary>이미 묶은 트리입니다. 두 번 묶으면 한 번 접을 때 두 번 씁니다.</summary>
    private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<
        LibraryFolderTreeView, object> Bound = [];

    internal static void Attach(LibraryFolderTreeView tree, WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(tree);
        ArgumentNullException.ThrowIfNull(state);
        // 불러온 값은 언제 붙어도 그대로 넣습니다 — 화면이 늦게 초기화돼도 접힘이 살아납니다.
        tree.CollapsedFolders = state.Current.CollapsedFolders;
        if (Bound.TryGetValue(tree, out _))
        {
            return;
        }
        Bound.Add(tree, new object());
        tree.CollapsedFoldersChanged += (_, folders) => state.SetCollapsedFolders(folders);
    }
}
