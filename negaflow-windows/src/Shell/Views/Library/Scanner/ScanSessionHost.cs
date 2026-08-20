using Negaflow.Catalog;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>
/// 라이브러리뷰와 현상뷰 좌측탭이 나눠 쓰는 스캐너 상태입니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS 는 <c>AppModel</c> 하나가 <c>showScannerControls</c> 와 스캐너 세션을 들고,
/// 라이브러리 사이드바(<c>LibraryWorkspaceView+Layout</c>)와 현상 사이드바
/// (<c>WorkflowSidebar</c> 의 library 탭)가 <b>같은</b> <c>LibrarySourceSection</c> 을 그 하나에
/// 걸어 냅니다. 그래서 어느 쪽에서 스캐너를 찾든 두 화면이 같은 것을 보입니다.
/// </para>
/// <para>
/// Windows 는 두 사이드바가 각자 <see cref="LibraryScanPanel"/> 을 하나씩 들고 각자
/// <c>ScanSessionController</c> 를 만들었습니다. 현상뷰 쪽 세션은 아무도 열지 않아
/// <b>현상뷰 좌측탭의 스캔 자리가 늘 비어 있었습니다.</b> 여기서 세션을 한 벌로 모읍니다.
/// </para>
/// </remarks>
public sealed class ScanSessionHost
{
    private ScanSessionController? session;
    private ImageRotation defaultRotation = ImageRotation.Degrees0;

    /// <summary>세션이 새로 만들어졌을 때입니다. 붙어 있는 패널이 다시 걸 자리입니다.</summary>
    public event EventHandler? SessionCreated;

    /// <summary>macOS <c>showScannerControls</c> 가 바뀌었을 때입니다.</summary>
    public event EventHandler? ShowScannerControlsChanged;

    /// <summary>아직 만들지 않았으면 <see langword="null"/> 입니다.</summary>
    public ScanSessionController? Session => session;

    /// <summary>macOS <c>AppModel.showScannerControls</c>.</summary>
    public bool ShowScannerControls { get; private set; }

    /// <summary>macOS <c>presentScannerSetup()</c> — 켜기만 합니다.</summary>
    public void PresentScannerSetup() => SetShowScannerControls(true);

    /// <summary>스캔 자리를 접습니다. macOS 에는 없지만 Windows 는 가져오기 단추가 토글입니다.</summary>
    public void SetShowScannerControls(bool shown)
    {
        if (ShowScannerControls == shown)
        {
            return;
        }
        ShowScannerControls = shown;
        ShowScannerControlsChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>설정에서 고른 기본 스캔 회전입니다. 세션이 아직 없어도 기억해 둡니다.</summary>
    public void ApplyDefaultRotation(ImageRotation rotation)
    {
        defaultRotation = rotation;
        if (session is not null)
        {
            session.DefaultRotation = rotation;
        }
    }

    /// <summary>
    /// 세션을 만들어 돌려줍니다. <b>UI 스레드에서만</b> 부르십시오 — 디스패처를 여기서
    /// 잡습니다. 이미 있으면 그대로 돌려줍니다.
    /// </summary>
    public ScanSessionController? Ensure()
    {
        if (session is not null)
        {
            return session;
        }
        if (DispatcherQueueUiDispatcher.CaptureForCurrentThread() is not { } uiDispatcher)
        {
            return null;
        }
        Trust = new ScannerPluginTrustStore();
        session = new ScanSessionController(
            new ScannerPluginGateway(),
            Trust,
            uiDispatcher)
        {
            DefaultRotation = defaultRotation,
        };
        SessionCreated?.Invoke(this, EventArgs.Empty);
        return session;
    }

    /// <summary>승인 저장소입니다. 세션과 같은 수명을 씁니다.</summary>
    public ScannerPluginTrustStore? Trust { get; private set; }
}
