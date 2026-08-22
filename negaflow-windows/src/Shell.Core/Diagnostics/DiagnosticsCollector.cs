namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 보고서를 만들 때 셸이 넘겨 주는 값들입니다. macOS <c>runDiagnostics()</c> 가 모델에서
/// 바로 읽던 것과 같은 항목이며, Shell.Core 는 화면을 모르므로 낱말도 함께 받습니다.
/// </summary>
public sealed record DiagnosticsInputs
{
    public int FrameCount { get; init; }

    public bool HasUnsavedChanges { get; init; }

    public string Lifecycle { get; init; } = string.Empty;

    /// <summary>카탈로그 저장이 실패한 세대입니다. 없으면 <c>null</c> 입니다.</summary>
    public string? SaveErrorGeneration { get; init; }

    /// <summary>지금 고른 스캐너 이름입니다. 없으면 빈 문자열입니다.</summary>
    public string ScannerName { get; init; } = string.Empty;

    /// <summary>macOS <c>backend.backendType.rawValue</c> 자리 - 시뮬레이터인지 플러그인인지.</summary>
    public string BackendName { get; init; } = string.Empty;

    public ScannerPluginCapabilities? Capabilities { get; init; }

    public IReadOnlyList<InstalledScannerPlugin> Plugins { get; init; } = [];

    public required DiagnosticsWords Words { get; init; }
}

/// <summary>
/// 보고서에 쓰는 낱말입니다. Shell.Core 는 리소스를 읽지 않으므로 셸이 채워 넘깁니다.
/// 이름은 macOS 문구 키와 같습니다.
/// </summary>
public sealed record DiagnosticsWords(
    string Yes,
    string No,
    string StatFrames,
    string StatUnsaved,
    string StatLifecycle,
    string StatSaveError,
    string ScannerLabel,
    string ScannerBackend,
    string ScannerPlugins,
    string NoInstalledPlugins,
    string Resolution,
    string ColorMode,
    string BitDepth,
    string Infrared,
    string CapabilityUnavailable);

/// <summary>
/// macOS <c>AppModel.runDiagnostics()</c> + <c>populateScannerStats</c> 이식본입니다.
/// </summary>
/// <remarks>
/// 담기는 값은 전부 지금 실제로 읽은 것입니다. 스캐너가 없으면 <see cref="DiagnosticsReport.ScannerAvailable"/>
/// 가 거짓이 되고 그 구역은 "활성 스캐너 없음" 으로 나옵니다 - 없는 장치의 사양을 지어내지 않습니다.
/// </remarks>
public static class DiagnosticsCollector
{
    public static DiagnosticsReport Collect(DiagnosticsInputs inputs, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(inputs);
        DiagnosticsWords words = inputs.Words;

        // macOS: errorLog.entries.suffix(12).reversed()
        List<DiagnosticsProblem> problems = [.. AppErrorLog.Shared.Entries
            .TakeLast(12)
            .Reverse()
            .Select(entry => new DiagnosticsProblem(entry.Message, entry.At))];

        // macOS: AppDiagnostics.recentEvents.filter { $0.phase == .error }.suffix(12).reversed()
        List<DiagnosticsFailureEvent> failures = [.. AppDiagnostics.RecentEvents
            .Where(item => item.Phase == AppDiagnosticPhase.Error)
            .TakeLast(12)
            .Reverse()
            .Select(item => new DiagnosticsFailureEvent(
                item.Operation.ToString(), item.Code ?? "error", item.Timestamp))];

        List<DiagnosticsStat> library =
        [
            new(words.StatFrames, inputs.FrameCount.ToString(
                System.Globalization.CultureInfo.CurrentCulture)),
            new(
                words.StatUnsaved,
                inputs.HasUnsavedChanges ? words.Yes : words.No,
                inputs.HasUnsavedChanges),
            new(words.StatLifecycle, inputs.Lifecycle),
        ];
        if (inputs.SaveErrorGeneration is { Length: > 0 } generation)
        {
            library.Add(new DiagnosticsStat(
                words.StatSaveError, $"generation {generation}", IsWarning: true));
        }

        return inputs.Capabilities is { } capabilities
            ? new DiagnosticsReport
            {
                GeneratedAt = now,
                Problems = problems,
                FailureEvents = failures,
                LibraryStats = library,
                ScannerAvailable = true,
                ScannerStats = ScannerStats(inputs, capabilities),
            }
            : new DiagnosticsReport
            {
                GeneratedAt = now,
                Problems = problems,
                FailureEvents = failures,
                LibraryStats = library,
                ScannerAvailable = false,
            };
    }

    /// <summary>macOS <c>populateScannerStats</c> 와 같은 일곱 줄, 같은 차례입니다.</summary>
    private static List<DiagnosticsStat> ScannerStats(
        DiagnosticsInputs inputs,
        ScannerPluginCapabilities capabilities)
    {
        DiagnosticsWords words = inputs.Words;
        string plugins = inputs.Plugins.Count == 0
            ? words.NoInstalledPlugins
            : string.Join(
                ", ",
                inputs.Plugins.Select(plugin =>
                    $"{plugin.Manifest.Name} [{plugin.Manifest.Id}]"));
        return
        [
            new DiagnosticsStat(words.ScannerLabel, inputs.ScannerName),
            new DiagnosticsStat(words.ScannerBackend, inputs.BackendName),
            new DiagnosticsStat(words.ScannerPlugins, plugins),
            new DiagnosticsStat(
                words.Resolution, string.Join(", ", capabilities.ResolutionsDpi)),
            new DiagnosticsStat(words.ColorMode, string.Join(", ", capabilities.Modes)),
            new DiagnosticsStat(words.BitDepth, string.Join(", ", capabilities.BitDepths)),
            new DiagnosticsStat(
                words.Infrared, capabilities.SupportsInfrared ? words.Yes : words.No),
        ];
    }
}
