using Microsoft.UI.Xaml;
using Negaflow.Catalog;
using Negaflow.Shell.Library;
using Negaflow.Shell.Services;
using System.Runtime.InteropServices;
using Microsoft.Windows.AppLifecycle;

namespace Negaflow.Shell;

public partial class App : Application
{
    private Window? mainWindow;
    private LibraryHostService? libraryHost;
    private ThumbnailService? thumbnails;
    private RestoreSignalWindow? restoreSignal;

    public App()
    {
        InitializeComponent();
        AppInstance.GetCurrent().Activated += OnRedirectedActivation;
    }

    /// <summary>
    /// 설정에 담긴 언어를 겁니다. 비어 있으면 시스템 언어를 그대로 씁니다 — 빈 문자열이 곧
    /// "시스템을 따르라" 는 뜻입니다.
    /// </summary>
    private static void ApplySavedLanguage()
    {
        try
        {
            string language = AppLanguages.Normalize(
                new PresentationSettingsStore().Current.Language);
            Windows.Globalization.ApplicationLanguages.PrimaryLanguageOverride = language;
        }
        catch (Exception exception) when (exception is IOException or
            UnauthorizedAccessException or ArgumentException or COMException)
        {
            // 설정을 못 읽으면 시스템 언어로 뜹니다. 언어 하나 때문에 앱이 시작하지 못하는
            // 것보다 낫습니다.
        }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _ = args;
        // 언어는 **창을 만들기 전에** 걸어야 합니다. 창이 뜬 뒤에 바꾸면 이미 만들어진
        // 컨트롤은 옛 언어를 들고 있어 한 화면에 두 언어가 섞입니다.
        ApplySavedLanguage();
        // 첫 창을 만들기 전에 읽습니다. 썸네일과 미리보기가 곧바로 현상 요청을 만들기 시작하므로
        // 그 뒤에 읽으면 처음 몇 장만 프리셋 없이 현상됩니다.
        LookPresetLibrary.Load(Path.Combine(AppContext.BaseDirectory, "presets"));
        var settingsStore = new PresentationSettingsStore();
        var workspaceState = new WorkspacePresentationState(settingsStore);
        mainWindow = new MainWindow(
            settingsStore,
            workspaceState,
            new NativeEngineStatusService(),
            OpenLibrary(),
            thumbnails);
        mainWindow.Closed += OnMainWindowClosed;
        restoreSignal = new RestoreSignalWindow(() =>
        {
            if (mainWindow is MainWindow window)
            {
                if (window.DispatcherQueue.HasThreadAccess)
                {
                    window.BringToFront();
                    return;
                }

                _ = window.DispatcherQueue.TryEnqueue(window.BringToFront);
            }
        });
        mainWindow.Activate();
    }

    /// <summary>
    /// 두 번째 실행이 여기로 넘어온 자리입니다. 새 창을 만들지 않고 이미 있는 메인 창만
    /// 다시 보여 줍니다.
    /// </summary>
    private void OnRedirectedActivation(object? sender, AppActivationArguments args)
    {
        _ = sender;
        _ = args;
        if (mainWindow is not MainWindow window)
        {
            return;
        }

        if (window.DispatcherQueue.HasThreadAccess)
        {
            window.BringToFront();
            return;
        }

        _ = window.DispatcherQueue.TryEnqueue(window.BringToFront);
    }

    /// <summary>
    /// 검증용 저장소 뿌리 지정입니다. <c>NEGAFLOW_STORAGE_ROOT</c> 가 절대 경로로 설정돼
    /// 있으면 그 아래를 씁니다.
    /// </summary>
    /// <remarks>
    /// 대량 라이브러리에서 격자와 썸네일 큐를 재려면 수백 장이 든 카탈로그가 필요한데, 그것을
    /// 사용자의 실제 카탈로그에 넣을 수는 없습니다(지우는 경로가 없습니다). 환경 변수를 켠
    /// 실행에서만 갈라지므로 평소 동작은 그대로입니다. 경로가 절대 경로가 아니면 무시하고
    /// 제품 경로로 갑니다 — 상대 경로를 추측해서 엉뚱한 곳에 카탈로그를 만들지 않습니다.
    /// </remarks>
    private static StorageRootResolutionResult ResolveStorageRoots()
    {
        string? isolated = Environment.GetEnvironmentVariable("NEGAFLOW_STORAGE_ROOT");
        return !string.IsNullOrWhiteSpace(isolated) && Path.IsPathFullyQualified(isolated)
            ? StorageRootResolver.ResolveForTests(isolated)
            : StorageRootResolver.ResolveProduction();
    }

    /// <summary>
    /// 카탈로그를 여는 곳입니다. 열기에 실패해도 던지지 않습니다. 셸은 상태를 보여 줄 뿐이며,
    /// **실패를 빈 라이브러리로 착각하지 않습니다.**
    /// </summary>
    private LibraryHostService? OpenLibrary()
    {
        // dispatcher 는 반드시 UI 스레드에서 잡아야 합니다. 워커에서는 null 입니다.
        if (DispatcherQueueUiDispatcher.CaptureForCurrentThread() is not { } dispatcher)
        {
            return null;
        }

        StorageRootResolutionResult roots = ResolveStorageRoots();
        if (roots.Roots is not { } resolved)
        {
            return null;
        }

        libraryHost = new LibraryHostService(dispatcher);
        libraryHost.Open(resolved);
        thumbnails = new ThumbnailService(
            new NativeDevelopExporterAdapter(),
            new WicThumbnailCodec(),
            dispatcher,
            resolved.ThumbnailRoot);
        return libraryHost;
    }

    private void OnMainWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        AppInstance.GetCurrent().Activated -= OnRedirectedActivation;
        AppInstance.GetCurrent().UnregisterKey();
        restoreSignal?.Dispose();
        restoreSignal = null;
        // 세션을 놓아야 다음 실행이 카탈로그의 작성자가 될 수 있습니다.
        libraryHost?.Dispose();
        libraryHost = null;
        // 대기 중인 썸네일 쓰기를 끝까지 흘려보냅니다. 캐시라 잃어도 되지만, 방금 만든 것을
        // 버리면 다음 실행이 같은 현상을 다시 합니다.
        if (thumbnails is { } service)
        {
            thumbnails = null;
            _ = service.DisposeAsync().AsTask();
        }
    }
}
