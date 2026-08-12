using Microsoft.UI.Xaml;
using Negaflow.Catalog;
using Negaflow.Shell.Library;
using Negaflow.Shell.Services;

namespace Negaflow.Shell;

public partial class App : Application
{
    private Window? mainWindow;
    private LibraryHostService? libraryHost;
    private ThumbnailService? thumbnails;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _ = args;
        var settingsStore = new PresentationSettingsStore();
        var workspaceState = new WorkspacePresentationState(settingsStore);
        mainWindow = new MainWindow(
            settingsStore,
            workspaceState,
            new NativeEngineStatusService(),
            OpenLibrary(),
            thumbnails);
        mainWindow.Closed += OnMainWindowClosed;
        mainWindow.Activate();
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

        StorageRootResolutionResult roots = StorageRootResolver.ResolveProduction();
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
