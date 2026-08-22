using Microsoft.UI.Xaml;

namespace Negaflow.Shell.Views;

/// <summary>
/// 평판 프리뷰 오버레이를 라이브러리 화면에 걸고 내립니다.
/// </summary>
/// <remarks>
/// macOS 는 프리뷰가 카탈로그의 한 프레임이라 캔버스가 그대로 띄우고, 오버레이는 그 위에
/// 얹기만 합니다(<c>CanvasView</c>: <c>frame.isPreviewScan &amp;&amp;
/// flatbedPreviewFrameID == frame.id &amp;&amp; usesFlatbedRegionWorkflow</c>). Windows
/// 라이브러리에는 한 장을 크게 띄우는 캔버스가 없어 격자 자리를 대신 씁니다 - 조건은
/// macOS 와 같습니다.
/// </remarks>
public sealed partial class LibraryWorkspaceView
{
    /// <summary>
    /// 평판 프리뷰가 살아 있으면 오버레이를 보이고, 아니면 격자를 되돌립니다.
    /// </summary>
    internal void SyncFlatbedOverlay()
    {
        string? previewPath = ScanPanel.FlatbedPreviewPath;
        bool show = previewPath is { Length: > 0 };
        if (show && ScanPanel.SessionForOverlay is { } session)
        {
            FlatbedOverlay.Attach(session);
        }

        FlatbedOverlay.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        if (show)
        {
            // 프리뷰를 띄우는 동안에는 격자와 살펴보기를 내립니다. 두 개가 겹치면
            // 프레임 사각형을 집을 수 없습니다.
            FrameListView.Visibility = Visibility.Collapsed;
            CullingSurface.Visibility = Visibility.Collapsed;
            LibraryContentPanel.Visibility = Visibility.Visible;
            EmptyLibraryPanel.Visibility = Visibility.Collapsed;
        }
        // 보기 방식 캡슐과 검색은 격자에 딸린 것입니다. 프리뷰 위에 그대로 떠 있으면
        // 아래쪽 프레임을 가리고 그 자리를 집을 수도 없습니다.
        LibraryBottomBar.Visibility = show ? Visibility.Collapsed : Visibility.Visible;
        FlatbedOverlay.Render(previewPath);
    }
}
