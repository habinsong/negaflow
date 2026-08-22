namespace Negaflow.Shell.Diagnostics;

/// <summary>사용자에게 보였던 문제 한 줄입니다. macOS <c>DiagnosticsReport.Problem</c>.</summary>
public sealed record DiagnosticsProblem(string Message, DateTimeOffset Date);

/// <summary>실패로 끝난 일 하나입니다. macOS <c>DiagnosticsReport.FailureEvent</c>.</summary>
public sealed record DiagnosticsFailureEvent(string Title, string Code, DateTimeOffset Date);

/// <summary>라벨과 값 한 줄입니다. macOS <c>DiagnosticsReport.Stat</c>.</summary>
public sealed record DiagnosticsStat(string Label, string Value, bool IsWarning = false);

/// <summary>
/// 진단 보고서입니다. macOS <c>DiagnosticsReport</c> 이식본이며 <b>구역과 차례가 같습니다</b> —
/// 최근 문제 · 최근 실패 이벤트 · 라이브러리 상태 · 스캐너.
/// </summary>
public sealed record DiagnosticsReport
{
    public IReadOnlyList<DiagnosticsProblem> Problems { get; init; } = [];

    public IReadOnlyList<DiagnosticsFailureEvent> FailureEvents { get; init; } = [];

    public IReadOnlyList<DiagnosticsStat> LibraryStats { get; init; } = [];

    public IReadOnlyList<DiagnosticsStat> ScannerStats { get; init; } = [];

    public bool ScannerAvailable { get; init; }

    public string? ScannerError { get; init; }

    public DateTimeOffset GeneratedAt { get; init; } = DateTimeOffset.Now;
}

/// <summary>보고서를 붙여넣을 수 있는 글로 바꿀 때 쓰는 낱말들입니다.</summary>
public sealed record DiagnosticsTextWords(
    string Title,
    string GeneratedAt,
    string ProblemsSection,
    string EventsSection,
    string LibrarySection,
    string ScannerSection,
    string NoProblems,
    string NoActiveScanner);

public static class DiagnosticsReportText
{
    /// <summary>
    /// macOS <c>DiagnosticsReportView.plainText(_:)</c> 와 같은 줄 차례로 만듭니다.
    /// 붙여넣어 그대로 보낼 수 있어야 하므로 구역 제목까지 담습니다.
    /// </summary>
    public static string PlainText(DiagnosticsReport report, DiagnosticsTextWords words)
    {
        ArgumentNullException.ThrowIfNull(report);
        ArgumentNullException.ThrowIfNull(words);
        List<string> lines =
        [
            words.Title,
            $"{words.GeneratedAt}  {Stamp(report.GeneratedAt)}",
            string.Empty,
            words.ProblemsSection,
        ];
        lines.AddRange(report.Problems.Count == 0
            ? [words.NoProblems]
            : report.Problems.Select(problem => $"{Time(problem.Date)}  {problem.Message}"));
        lines.AddRange([string.Empty, words.EventsSection]);
        lines.AddRange(report.FailureEvents.Count == 0
            ? [words.NoProblems]
            : report.FailureEvents.Select(
                item => $"{Time(item.Date)}  {item.Title}  {item.Code}"));
        lines.AddRange([string.Empty, words.LibrarySection]);
        lines.AddRange(report.LibraryStats.Select(stat => $"{stat.Label}: {stat.Value}"));
        lines.AddRange([string.Empty, words.ScannerSection]);
        if (report.ScannerError is { Length: > 0 } error)
        {
            lines.Add(error);
        }
        else if (report.ScannerAvailable)
        {
            lines.AddRange(report.ScannerStats.Select(stat => $"{stat.Label}: {stat.Value}"));
        }
        else
        {
            lines.Add(words.NoActiveScanner);
        }
        return string.Join(Environment.NewLine, lines);
    }

    public static string Time(DateTimeOffset value) =>
        value.LocalDateTime.ToString("HH:mm:ss", System.Globalization.CultureInfo.CurrentCulture);

    public static string Stamp(DateTimeOffset value) =>
        value.LocalDateTime.ToString("g", System.Globalization.CultureInfo.CurrentCulture);
}
