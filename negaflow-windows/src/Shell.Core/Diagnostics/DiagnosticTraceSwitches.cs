namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 개발자 모드가 켜고 끄는 진단 기록입니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS 의 개발자 모드는 현상 인스펙터에 "개발자 디버그" 구역을 엽니다. Windows 에는 아직
/// 그 구역이 없고 대신 <b>파일 기록</b>이 있습니다 — 썸네일·미리보기·단축키가 어떤 길로
/// 갔는지 남기는 추적입니다. 지금까지 그 추적은 환경 변수나 손으로 만든 표시 파일로만
/// 켤 수 있었습니다.
/// </para>
/// <para>
/// 여기서 하는 일은 그 <b>표시 파일을 만들고 지우는 것</b>뿐입니다. 켜면 다음 동작부터
/// <c>%LOCALAPPDATA%\Negaflow\Logs</c> 에 줄이 쌓이고, 끄면 멈춥니다 — 화면에 새 그림을
/// 지어내지 않고 이미 있는 장치를 사용자 손에 쥐여 줍니다.
/// </para>
/// </remarks>
public static class DiagnosticTraceSwitches
{
    /// <summary>표시 파일 이름들입니다. 각 추적이 자기 파일을 봅니다.</summary>
    public static IReadOnlyList<string> MarkerNames { get; } =
    [
        "thumbnail-trace.on",
        "preview-trace.on",
        "shortcut-trace.on",
        // 메모리 예산이 실제로 어떻게 도는지 - 상한·각 캐시 상주량·간접비를 한 줄로 남깁니다.
        MemoryBudgetLog.MarkerName,
    ];

    public static string LogDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Negaflow",
        "Logs");

    /// <summary>지금 켜져 있는지입니다. 표시 파일이 하나라도 있으면 켜진 것으로 봅니다.</summary>
    public static bool IsEnabled()
    {
        try
        {
            return MarkerNames.Any(name => File.Exists(Path.Combine(LogDirectory, name)));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    /// <summary>개발자 모드를 실제 기록 동작에 겁니다.</summary>
    public static void Apply(bool enabled)
    {
        try
        {
            string logs = LogDirectory;
            if (enabled)
            {
                Directory.CreateDirectory(logs);
            }
            foreach (string name in MarkerNames)
            {
                string marker = Path.Combine(logs, name);
                if (enabled)
                {
                    if (!File.Exists(marker))
                    {
                        File.WriteAllBytes(marker, []);
                    }
                }
                else if (File.Exists(marker))
                {
                    File.Delete(marker);
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException or PathTooLongException)
        {
            // 기록을 켜지 못해도 앱은 그대로 돕니다.
        }
    }
}
