using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Negaflow.Shell;

/// <summary>
/// 이 프로세스가 끝난 뒤 같은 앱을 다시 엽니다. macOS <c>AppRelauncher</c> 를 옮겼습니다.
/// </summary>
/// <remarks>
/// <para>
/// 종료가 <b>승인된 뒤에만</b> 부릅니다. 먼저 띄우면 두 번째 인스턴스가 라이브러리 프로세스
/// 잠금에 걸리고, 종료가 취소되면 기다리던 헬퍼가 엉뚱한 때 앱을 엽니다.
/// </para>
/// <para>
/// <c>AppInstance.Restart</c> 는 쓰지 않습니다 — 현재 프로세스를 곧바로 끝내 종료 저장
/// 경로(결함 기록 → 카탈로그 커밋)를 건너뜁니다. 헬퍼는 숨은 PowerShell 로, 이 PID 가 끝나길
/// 최대 60초 기다린 뒤 패키지면 <c>shell:AppsFolder\&lt;AUMID&gt;</c>, 아니면 실행 파일을 엽니다.
/// </para>
/// </remarks>
internal static class AppRelauncher
{
    /// <summary>종료가 끝나지 않을 때 무한히 기다리지 않도록 둔 상한입니다(macOS 와 같은 60초).</summary>
    internal const int MaximumWaitMilliseconds = 60_000;

    /// <summary>헬퍼를 띄웠으면 <see langword="true"/> 입니다. 실패는 진단에만 남깁니다.</summary>
    internal static bool RelaunchAfterExit()
    {
        string? target = LaunchTarget();
        if (target is null)
        {
            return false;
        }
        int processId = Environment.ProcessId;
        string script =
            $"$p = Get-Process -Id {processId} -ErrorAction SilentlyContinue; " +
            $"if ($p) {{ $null = $p.WaitForExit({MaximumWaitMilliseconds}) }}; " +
            target;
        var start = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };
        foreach (string argument in new[]
        {
            "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script,
        })
        {
            start.ArgumentList.Add(argument);
        }
        try
        {
            using Process? helper = Process.Start(start);
            return helper is not null;
        }
        catch (Exception error) when (error is Win32Exception or InvalidOperationException or
            PlatformNotSupportedException)
        {
            Diagnostics.AppErrorLog.Shared.Record("relaunch helper failed: " + error.Message);
            return false;
        }
    }

    /// <summary>
    /// 다시 열 명령입니다. MSIX 로 설치된 앱은 실행 파일을 직접 띄우면 패키지 정체성이 없어
    /// 뜨지 않으므로 AUMID 로 엽니다(<c>scripts/run-app.ps1</c> 과 같은 방법).
    /// </summary>
    private static string? LaunchTarget()
    {
        try
        {
            string family = Windows.ApplicationModel.Package.Current.Id.FamilyName;
            if (!string.IsNullOrEmpty(family))
            {
                return $"Start-Process -FilePath 'explorer.exe' -ArgumentList " +
                    $"'shell:AppsFolder\\{family}!App'";
            }
        }
        catch (Exception error) when (error is InvalidOperationException or COMException)
        {
            // 패키지 밖에서 도는 개발 실행입니다. 실행 파일을 그대로 엽니다.
        }
        return Environment.ProcessPath is { Length: > 0 } path
            ? $"Start-Process -FilePath '{path.Replace("'", "''", StringComparison.Ordinal)}'"
            : null;
    }
}
