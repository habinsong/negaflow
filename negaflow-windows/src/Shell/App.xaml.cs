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
    private WindowsMemoryPressureMonitor? memoryPressureMonitor;
    private RestoreSignalWindow? restoreSignal;

    public App()
    {
        UnhandledException += OnUnhandledException;
        try
        {
            InitializeComponent();
        }
        catch (Exception exception)
        {
            WriteStartupFault("InitializeComponent", exception);
            throw;
        }
        AppInstance.GetCurrent().Activated += OnRedirectedActivation;
    }

    private static void OnUnhandledException(
        object sender,
        Microsoft.UI.Xaml.UnhandledExceptionEventArgs args)
    {
        WriteStartupFault("UnhandledException", args.Exception);
    }

    private static void WriteStartupFault(string stage, Exception exception)
    {
        try
        {
            string directory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Negaflow",
                "Logs");
            Directory.CreateDirectory(directory);
            Exception? current = exception;
            var text = new System.Text.StringBuilder();
            text.AppendLine(stage);
            while (current is not null)
            {
                text.AppendLine(current.GetType().FullName);
                text.AppendLine(current.Message);
                text.AppendLine(current.StackTrace);
                text.AppendLine("---");
                current = current.InnerException;
            }

            File.WriteAllText(
                Path.Combine(directory, "startup-fault.txt"),
                text.ToString());
        }
        catch (Exception)
        {
        }
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
            Negaflow.Shell.Localization.AppResources.SetLanguage(language);
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
        Diagnostics.StartupTrace.Mark("OnLaunched");
        // 언어는 **창을 만들기 전에** 걸어야 합니다. 창이 뜬 뒤에 바꾸면 이미 만들어진
        // 컨트롤은 옛 언어를 들고 있어 한 화면에 두 언어가 섞입니다.
        using (Diagnostics.StartupTrace.Measure("language"))
        {
            ApplySavedLanguage();
        }
        // 첫 창을 만들기 전에 읽습니다. 썸네일과 미리보기가 곧바로 현상 요청을 만들기 시작하므로
        // 그 뒤에 읽으면 처음 몇 장만 프리셋 없이 현상됩니다.
        using (Diagnostics.StartupTrace.Measure("presets"))
        {
            LookPresetLibrary.Load(Path.Combine(AppContext.BaseDirectory, "presets"));
        }
        var settingsStore = new PresentationSettingsStore();
        presentationSettings = settingsStore;
        var workspaceState = new WorkspacePresentationState(settingsStore);
        try
        {
            // **카탈로그는 창 뒤에 엽니다.** 창을 띄우기 전에 읽으면 그 시간(실측 310ms)
            // 동안 화면에 아무 것도 없습니다. 셸 초기화가 이미 창 뒤로 갔으므로, 그것이
            // 쓰기 직전에 열면 됩니다.
            NativeEngineStatusService engineStatus;
            using (Diagnostics.StartupTrace.Measure("engine status"))
            {
                engineStatus = new NativeEngineStatusService();
            }
            using (Diagnostics.StartupTrace.Measure("MainWindow ctor"))
            {
                mainWindow = new MainWindow(
                    settingsStore,
                    workspaceState,
                    engineStatus,
                    OpenLibrary,
                    () => thumbnails);
            }
        }
        catch (Exception exception)
        {
            WriteStartupFault("MainWindow", exception);
            throw;
        }
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
        using (Diagnostics.StartupTrace.Measure("Activate"))
        {
            mainWindow.Activate();
        }
        Diagnostics.StartupTrace.Mark("window shown");
        // 셸을 채우는 것은 **첫 프레임이 실제로 그려진 뒤**에 시작합니다
        // (`MainWindow.OnFirstRendered`). 여기서 큐에 넣으면 그 항목이 렌더보다 먼저 돌아
        // UI 스레드를 붙잡고, 로딩 화면이 한 번도 그려지지 못한 채 검은 화면이 이어집니다 -
        // 실측으로 창은 0.82 초에 떴는데 첫 렌더는 3.01 초였습니다.
        Diagnostics.StartupTrace.Mark("OnLaunched done");
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
    /// <summary>저장된 설정입니다. 캐시를 만든 뒤 상주 한도를 한 번 걸어 주려고 붙듭니다.</summary>
    private PresentationSettingsStore? presentationSettings;

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
        // 썸네일도 설정 · 디스크 탭에서 고른 자리에 둡니다. 고른 적 없으면 기본 자리이며,
        // 그 기본 자리는 OneDrive\negaflow\Thumbnails 입니다.
        string thumbnailRoot = new Negaflow.Shell.Storage.DiskStorageLocations(
            (presentationSettings?.Current ?? new ShellPreferences()).Disk).Thumbnails;
        thumbnails = new ThumbnailService(
            new NativeDevelopExporterAdapter(),
            new WicThumbnailCodec(),
            dispatcher,
            thumbnailRoot,
            Path.Combine(resolved.CacheRoot, "DevelopedPreviews"));
        // 설정창에서 상주 한도를 바꾸면 지금 도는 캐시에 바로 걸립니다. 캐시는 상태를 만든
        // 뒤에 생기므로, 걸어 두는 것만으로는 **저장돼 있던 값이 한 번도 적용되지 않습니다.**
        ThumbnailService cache = thumbnails;
        WorkspacePresentationState.FrameCacheLimitsChanged = cache.ApplyResidencySettings;
        cache.ApplyResidencySettings(
            (presentationSettings?.Current ?? new ShellPreferences()).FrameCache);
        memoryPressureMonitor = WindowsMemoryPressureMonitor.TryStart(
            thumbnails.ApplyMemoryPressure);
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
        memoryPressureMonitor?.Dispose();
        memoryPressureMonitor = null;
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
