namespace Negaflow.Shell.Views;

/// <summary>
/// 라이브러리 화면의 썸네일이 도착했을 때 할 일입니다.
/// </summary>
/// <remarks>
/// **라이브러리에는 평판 오버레이가 없습니다.**
///
/// macOS 에서 프레임 사각형을 그리는 자리는 <c>CanvasView</c> 이고, 그 캔버스는
/// <c>ContentView+Workspace</c> 의 <c>case .develop</c> 안에만 있습니다 - <c>case .library</c>
/// 는 <c>LibraryWorkspaceView</c> 만 띄웁니다. 앞 판은 이것을 라이브러리에 얹으면서
/// <c>FrameListView.Visibility = Collapsed</c> 로 **격자를 통째로 내렸습니다.** 그래서 프리뷰
/// 스캔 한 번이면 사진 56장이 화면에서 사라지고 평판 한 장만 남았습니다.
///
/// 사각형은 현상뷰 캔버스가 그립니다(<see cref="DevelopWorkspaceView"/>).
/// </remarks>
public sealed partial class LibraryWorkspaceView
{
    private void OnThumbnailReady(string frameId) => thumbs.OnReady(frameId);
}
