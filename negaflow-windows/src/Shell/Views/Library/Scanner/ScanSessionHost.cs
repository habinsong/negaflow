using Negaflow.Catalog;
using Negaflow.Shell.Develop;

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
    private Func<GrainMendGuidedCarryover?>? guidedCarryoverProvider;
    private Action<string, GrainMendGuidedCarryover>? guidedCarryoverPublished;

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

    public void BindGrainMendCarryover(
        Func<GrainMendGuidedCarryover?> provider,
        Action<string, GrainMendGuidedCarryover> published)
    {
        ArgumentNullException.ThrowIfNull(provider);
        ArgumentNullException.ThrowIfNull(published);
        guidedCarryoverProvider = provider;
        guidedCarryoverPublished = published;
        ApplyGrainMendCarryoverCallbacks();
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
        ApplyGrainMendCarryoverCallbacks();
        SessionCreated?.Invoke(this, EventArgs.Empty);
        return session;
    }

    /// <summary>
    /// 마지막 평판 프리뷰의 밝기 값입니다. 자동 프레임 찾기가 이것으로 셉니다.
    /// </summary>
    /// <remarks>
    /// <b>두 사이드바가 나눠 씁니다.</b> 예전에는 패널마다 따로 들어, 라이브러리뷰에서 찍은
    /// 프리뷰를 현상뷰 패널은 모른다고 보았습니다 — 현상뷰에서 규격이나 수동 비율을 바꾸면
    /// 프레임이 지워지기만 하고 다시 찾지 않았고, "프레임 다시 찾기" 도 꺼져 있었습니다.
    /// macOS 는 모델 하나가 프리뷰 하나를 듭니다.
    /// </remarks>
    public PreviewLuminance FlatbedPreview { get; set; } = PreviewLuminance.None;

    /// <summary>
    /// 시뮬레이터 스위치를 설정에 적는 자리입니다. 설정값은 하나이므로 두 사이드바가 같은 것을
    /// 씁니다 — 예전에는 라이브러리뷰 패널에만 걸려, 현상뷰에서 켠 시뮬레이터가 설정에 남지 않았고
    /// 다음 설정 갱신이 저장된 옛 값(끔)을 세션에 다시 걸어 스캔 도중 시뮬레이터가 꺼졌습니다.
    /// </summary>
    public Action<bool>? SimulatorPublisher { get; set; }

    /// <summary>승인 저장소입니다. 세션과 같은 수명을 씁니다.</summary>
    public ScannerPluginTrustStore? Trust { get; private set; }

    private void ApplyGrainMendCarryoverCallbacks()
    {
        if (session is null)
        {
            return;
        }
        session.GuidedCarryoverProvider = guidedCarryoverProvider;
        session.GuidedCarryoverPublished = guidedCarryoverPublished;
    }
}
