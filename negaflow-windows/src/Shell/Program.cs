using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.ApplicationModel.WindowsAppRuntime;

namespace Negaflow.Shell;

/// <summary>
/// 앱 진입점입니다. Windows App SDK 는 기본이 여러 프로세스라서, 창과 카탈로그를
/// 만들기 전에 하나만 남깁니다.
/// </summary>
/// <remarks>
/// 패키지된 실행은 <c>AppInstance.FindOrRegisterForKey</c> 로 선출하고, 두 번째
/// 실행은 <c>RedirectActivationToAsync</c> 로 이미 떠 있는 프로세스에 넘깁니다.
/// 공식 안내: https://learn.microsoft.com/windows/apps/windows-app-sdk/applifecycle/applifecycle-single-instance
/// <c>RedirectActivationToAsync</c> 는 끝나면 프로세스가 죽지 않으므로 우리가 종료합니다.
/// STA 에서 그 작업을 동기 <c>Wait</c> 하면 교착이 나므로, 공식 예제처럼 스레드 풀에서
/// 돌리고 <c>CoWaitForMultipleObjects</c> 로 기다립니다.
///
/// 패키지 없이 exe 를 직접 실행하면 Windows App Runtime COM 이 등록되지 않아
/// 모듈 초기화의 <c>DeploymentManager.Initialize</c> 가
/// <c>REGDB_E_CLASSNOTREG (0x80040154)</c> 로 죽습니다. 그 초기화는 끄고, 여기서
/// 로컬 뮤텍스로 선출한 뒤에만 Initialize 합니다. 이미 떠 있는 프로세스에는
/// 등록된 창 클래스로 복원 신호를 보냅니다.
/// </remarks>
internal static class Program
{
    // D-017: 사용자·제품 채널·설치 정체성마다 primary 하나. 지금 트리는 채널이 하나라
    // 키도 하나입니다. 경로를 넣지 않습니다.
    internal const string PrimaryInstanceKey = "negaflow.primary";
    internal const string LocalMutexName = @"Local\Negaflow.Shell.primary";
    internal const string RestoreWindowClass = "Negaflow.Shell.Restore";

    private const uint CwmoDefault = 0;
    private const uint Infinite = 0xFFFFFFFF;
    private const uint WmRestoreExisting = 0x0400; // WM_USER

    [STAThread]
    private static void Main(string[] args)
    {
        _ = args;
        Diagnostics.StartupTrace.Mark("Main");
        using Mutex? localPrimary = TryClaimLocalPrimary();
        if (localPrimary is null)
        {
            // Packaged second launch can still hand arguments to AppInstance.
            if (TryInitializeWindowsAppRuntime())
            {
                WinRT.ComWrappersSupport.InitializeComWrappers();
                if (!ShouldRedirectToExistingInstance())
                {
                    SignalExistingInstance();
                }
            }
            else
            {
                SignalExistingInstance();
            }

            return;
        }

        if (!HasPackageIdentity())
        {
            // 패키지 없이 exe 를 직접 실행하면 WinUI Application.Start 가
            // REGDB_E_CLASSNOTREG 로 죽습니다. 두 번째 창을 여는 편이 더 나쁘므로
            // 여기서 끝냅니다. 제품 실행은 AUMID / 등록된 패키지입니다.
            return;
        }

        Diagnostics.StartupTrace.Mark("ComWrappers begin");
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Diagnostics.StartupTrace.Mark("ComWrappers end");
        if (!TryInitializeWindowsAppRuntime())
        {
            return;
        }
        Diagnostics.StartupTrace.Mark("app runtime ready");

        if (ShouldRedirectToExistingInstance())
        {
            return;
        }

        int firstChanceCount = 0;
        AppDomain.CurrentDomain.FirstChanceException += (_, args) =>
        {
            if (Interlocked.Increment(ref firstChanceCount) > 40)
            {
                return;
            }

            try
            {
                string directory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Negaflow",
                    "Logs");
                Directory.CreateDirectory(directory);
                File.AppendAllText(
                    Path.Combine(directory, "startup-first-chance.txt"),
                    args.Exception.GetType().FullName + ": " +
                    args.Exception.Message + Environment.NewLine);
            }
            catch (Exception)
            {
            }
        };

        Diagnostics.StartupTrace.Mark("Application.Start");
        Application.Start(static _ =>
        {
            SynchronizationContext.SetSynchronizationContext(
                new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            new App();
        });
    }

    /// <summary>
    /// 같은 사용자 세션에서 프로세스가 이미 있으면 창을 만들지 않습니다. Windows App
    /// Runtime COM 보다 앞에서 돌아가므로, 패키지 없이 exe 를 직접 실행한 두 번째
    /// 프로세스도 여기서 끝납니다.
    /// </summary>
    private static Mutex? TryClaimLocalPrimary()
    {
        var mutex = new Mutex(true, LocalMutexName, out bool created);
        if (created)
        {
            return mutex;
        }

        mutex.Dispose();
        return null;
    }

    private static bool TryInitializeWindowsAppRuntime()
    {
        try
        {
            var options = new DeploymentInitializeOptions
            {
                OnErrorShowUI = false,
            };
            DeploymentResult result = DeploymentManager.Initialize(options);
            return result.Status == DeploymentStatus.Ok;
        }
        catch (COMException)
        {
            // 패키지된 프로세스에서는 COM 이 있어야 합니다. 패키지 없이 exe 를 직접
            // 실행하면 등록이 없어 여기서 실패하고, 호출부가 AppInstance 없이 끝냅니다.
            return false;
        }
        catch (TypeLoadException)
        {
            return false;
        }
    }

    private static bool HasPackageIdentity()
    {
        try
        {
            return !string.IsNullOrEmpty(Windows.ApplicationModel.Package.Current.Id.FullName);
        }
        catch (Exception exception) when (exception is InvalidOperationException or COMException)
        {
            return false;
        }
    }

    /// <summary>
    /// 이미 떠 있는 프로세스가 있으면 활성화를 넘기고 true 를 돌려 이 프로세스를 끝냅니다.
    /// 선출에 실패하면 창을 만들지 않습니다 — 두 번째 카탈로그 작성자를 여는 편이 더 나쁘기
    /// 때문입니다.
    /// </summary>
    private static bool ShouldRedirectToExistingInstance()
    {
        AppInstance registered;
        try
        {
            registered = AppInstance.FindOrRegisterForKey(PrimaryInstanceKey);
        }
        catch (COMException)
        {
            // 선출 API 가 죽으면 창을 아예 안 띄우는 편이 더 나쁩니다. 이미 떠 있는
            // 프로세스가 있는지는 이 예외만으로 알 수 없으므로, 이 프로세스가 primary 로
            // 갑니다.
            return false;
        }

        if (registered.IsCurrent)
        {
            return false;
        }

        AppActivationArguments? activation = AppInstance.GetCurrent().GetActivatedEventArgs();
        if (activation is not null)
        {
            try
            {
                RedirectActivation(registered, activation);
            }
            catch (Exception)
            {
                // 넘기기에 실패해도 이 프로세스는 끝냅니다. 두 번째 창을 여는 편이 더 나쁘기
                // 때문입니다.
            }
        }

        return true;
    }

    private static void RedirectActivation(AppInstance existing, AppActivationArguments activation)
    {
        nint finished = CreateEventW(0, true, false, null);
        if (finished == 0)
        {
            existing.RedirectActivationToAsync(activation).AsTask().GetAwaiter().GetResult();
            return;
        }

        try
        {
            _ = Task.Run(() =>
            {
                existing.RedirectActivationToAsync(activation).AsTask().GetAwaiter().GetResult();
                _ = SetEvent(finished);
            });
            _ = CoWaitForMultipleObjects(CwmoDefault, Infinite, 1, [finished], out _);
        }
        finally
        {
            _ = CloseHandle(finished);
        }
    }

    private static void SignalExistingInstance()
    {
        nint window = FindWindowW(RestoreWindowClass, null);
        if (window != 0)
        {
            _ = PostMessageW(window, WmRestoreExisting, 0, 0);
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint CreateEventW(
        nint eventAttributes,
        [MarshalAs(UnmanagedType.Bool)] bool manualReset,
        [MarshalAs(UnmanagedType.Bool)] bool initialState,
        string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetEvent(nint handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(nint handle);

    [DllImport("ole32.dll")]
    private static extern uint CoWaitForMultipleObjects(
        uint flags,
        uint timeoutMilliseconds,
        uint handleCount,
        nint[] handles,
        out uint index);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint FindWindowW(string? className, string? windowName);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessageW(nint window, uint message, nint wParam, nint lParam);
}
