using Microsoft.UI.Xaml;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Views.Library.Scanner;

namespace Negaflow.Shell.Views;

/// <summary>
/// 평판 프리뷰의 프레임 사각형을 <b>현상 캔버스 위에</b> 얹습니다.
/// </summary>
/// <remarks>
/// macOS 는 <c>CanvasView</c> 가 그 자리를 소유합니다:
/// <code>
/// if frame.isPreviewScan,
///    model.flatbedPreviewFrameID == frame.id,
///    model.usesFlatbedRegionWorkflow,
///    !cropMode, !brushMode, !regionDefectMode, !cloneStampMode, !basePickerMode {
///     FlatbedScanAreaOverlay(frame: frame, imageFrame: imageFrame)
/// }
/// </code>
/// Windows 는 이 오버레이를 <c>LibraryWorkspaceView</c> 에만 걸어 두었습니다. 그래서 현상뷰에서
/// 프리뷰를 뜨면 스캔 패널에는 "선택: 18" 이라고 적히는데 <b>사각형은 어디에도 그려지지
/// 않았습니다.</b> 같은 조건으로 현상 캔버스에도 겁니다.
///
/// 사진은 캔버스가 그립니다(줌·팬 포함). 오버레이는 자기 그림을 그리지 않고 그 자리만
/// 받습니다 - <c>DevelopPreviewCanvas.ApplyImageFrame</c> 이 매번 넘깁니다.
/// </remarks>
public sealed partial class DevelopWorkspaceView
{
    private ScanSessionHost? flatbedScanHost;
    private ScanSessionController? flatbedSession;

    private void AttachFlatbedOverlay(ScanSessionHost host)
    {
        ArgumentNullException.ThrowIfNull(host);
        if (ReferenceEquals(flatbedScanHost, host))
        {
            return;
        }
        if (flatbedScanHost is not null)
        {
            flatbedScanHost.SessionCreated -= OnFlatbedSessionCreated;
        }
        flatbedScanHost = host;
        flatbedScanHost.SessionCreated += OnFlatbedSessionCreated;
        PreviewCanvas.FlatbedOverlay.UseExternalImage();
        PreviewCanvas.FlatbedOverlay.RegionsChanged += (_, _) => RequestFlatbedOverlaySync();
        BindFlatbedSession(host.Session);
    }

    private void OnFlatbedSessionCreated(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (DispatcherQueue is null || DispatcherQueue.HasThreadAccess)
        {
            BindFlatbedSession(flatbedScanHost?.Session);
            return;
        }
        _ = DispatcherQueue.TryEnqueue(() => BindFlatbedSession(flatbedScanHost?.Session));
    }

    private void BindFlatbedSession(ScanSessionController? session)
    {
        if (ReferenceEquals(flatbedSession, session))
        {
            SyncFlatbedOverlay();
            return;
        }
        if (flatbedSession is not null)
        {
            flatbedSession.Changed -= OnFlatbedSessionChanged;
        }
        flatbedSession = session;
        if (flatbedSession is not null)
        {
            flatbedSession.Changed += OnFlatbedSessionChanged;
        }
        SyncFlatbedOverlay();
    }

    /// <summary>
    /// <b>UI 스레드로 넘겨서</b> 부릅니다. <see cref="ScanSessionController.Changed"/> 는
    /// 장치 탐색 같은 워커 작업에서도 올라옵니다. 그 스레드에서 <c>Visibility</c> 를 건드리면
    /// WinUI 가 <c>COMException</c> 을 던지고 그것이 스캔 흐름을 통째로 끊습니다 - 실기에서
    /// `RefreshDevicesAsync -> OnFlatbedSessionChanged -> SyncFlatbedOverlay` 로 앱이
    /// 죽었습니다(§22.1 과 같은 종류의 실수입니다).
    /// </summary>
    private void OnFlatbedSessionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        RequestFlatbedOverlaySync();
    }

    private void RequestFlatbedOverlaySync()
    {
        if (DispatcherQueue is null || DispatcherQueue.HasThreadAccess)
        {
            SyncFlatbedOverlay();
            return;
        }
        _ = DispatcherQueue.TryEnqueue(SyncFlatbedOverlay);
    }

    /// <summary>
    /// macOS 의 다섯 가지 배제 조건을 그대로 봅니다. 도구를 쓰는 동안에는 프레임 사각형이
    /// 그 위를 덮으면 안 됩니다.
    /// </summary>
    private bool CanvasToolsAreIdle() =>
        !crop.IsActive &&
        GrainMendPanel.grainMend.Strokes.Tool == GrainMendTool.None &&
        !GrainMendPanel.grainMend.IsDetecting &&
        !BaseCard.IsBasePickerActive;

    internal void SyncFlatbedOverlay()
    {
        FlatbedScanAreaOverlay overlay = PreviewCanvas.FlatbedOverlay;
        LibraryFrameSnapshot? frame = ActiveFlatbedPreviewFrame();
        bool show = frame is not null && CanvasToolsAreIdle();
        if (!show)
        {
            overlay.Visibility = Visibility.Collapsed;
            return;
        }

        overlay.Attach(flatbedSession!, frame, thumbnails);
        overlay.Visibility = Visibility.Visible;
        // 캔버스가 지금 그리고 있는 자리를 먼저 넘긴 뒤 사각형을 폅니다.
        PreviewCanvas.RefreshFlatbedOverlayFrame();
        overlay.Render(flatbedSession!.LastPreviewPath);
    }

    /// <summary>
    /// 지금 보고 있는 사진이 <b>이 세션의 평판 프리뷰</b>일 때만 프레임을 그립니다.
    /// macOS <c>frame.isPreviewScan &amp;&amp; flatbedPreviewFrameID == frame.id &amp;&amp;
    /// usesFlatbedRegionWorkflow</c> 와 같은 세 가지입니다.
    /// </summary>
    private LibraryFrameSnapshot? ActiveFlatbedPreviewFrame()
    {
        if (flatbedSession is not { UsesFlatbedRegionWorkflow: true } session ||
            session.PreviewFrameId is not { Length: > 0 } previewFrameId ||
            libraryHost is null ||
            !string.Equals(libraryHost.ActiveFrameId, previewFrameId, StringComparison.Ordinal))
        {
            return null;
        }
        LibraryFrameSnapshot? frame = libraryHost.Frames.FirstOrDefault(candidate =>
            string.Equals(candidate.Id, previewFrameId, StringComparison.Ordinal));
        return frame is { IsPreviewScan: true } ? frame : null;
    }
}
