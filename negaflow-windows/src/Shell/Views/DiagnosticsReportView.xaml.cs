using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

/// <summary>
/// 작업 옵션 · 진단 화면입니다. macOS <c>DiagnosticsReportView</c> 이식본이며 구역 넷의
/// 차례와 내용이 같습니다.
/// </summary>
public sealed partial class DiagnosticsReportView : UserControl
{
    private DiagnosticsReport? report;

    public DiagnosticsReportView()
    {
        InitializeComponent();
        Localize();
        AppResources.LanguageChanged += OnLanguageChanged;
        Unloaded += (_, _) => AppResources.LanguageChanged -= OnLanguageChanged;
    }

    /// <summary>보고서를 다시 만들어 달라는 요청입니다. 창이 채워 줍니다.</summary>
    public Func<Task<DiagnosticsReport>>? ReportSource { get; set; }

    public async Task RefreshAsync()
    {
        if (ReportSource is not { } source)
        {
            return;
        }
        RefreshButton.IsEnabled = false;
        CopyAllButton.IsEnabled = false;
        try
        {
            report = await source();
            Build();
        }
        finally
        {
            RefreshButton.IsEnabled = true;
            CopyAllButton.IsEnabled = report is not null;
        }
    }

    private void OnLanguageChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        Localize();
        Build();
    }

    private void Localize()
    {
        TitleText.Text = AppResources.Get("commandDiagnostics", "Text");
        CopyAllButton.Content = AppResources.Get("copyAll", "Content");
        string refresh = AppResources.Get("diagnosticsRefresh", "Value");
        ToolTipService.SetToolTip(RefreshButton, refresh);
        AutomationProperties.SetName(RefreshButton, refresh);
    }

    /// <summary>macOS 와 같은 구역 넷을 같은 차례로 놓습니다.</summary>
    private void Build()
    {
        Sections.Children.Clear();
        if (report is not { } value)
        {
            return;
        }
        GeneratedText.Text = string.Concat(
            AppResources.Get("diagnosticsGeneratedAt", "Text"),
            "  ",
            DiagnosticsReportText.Stamp(value.GeneratedAt));

        string none = AppResources.Get("diagnosticsNoProblems", "Text");
        Sections.Children.Add(Card(
            AppResources.Get("diagnosticsReportProblemsSection", "Text"),
            value.Problems.Count == 0 ? null : value.Problems.Count,
            value.Problems.Count == 0
                ? [Empty(none)]
                : [.. value.Problems.Select(problem => Line(
                    DiagnosticsReportText.Time(problem.Date), problem.Message))]));

        Sections.Children.Add(Card(
            AppResources.Get("diagnosticsReportEventsSection", "Text"),
            value.FailureEvents.Count == 0 ? null : value.FailureEvents.Count,
            value.FailureEvents.Count == 0
                ? [Empty(none)]
                : [.. value.FailureEvents.Select(item => Line(
                    DiagnosticsReportText.Time(item.Date), $"{item.Title}  {item.Code}"))]));

        Sections.Children.Add(Card(
            AppResources.Get("diagnosticsReportLibrarySection", "Text"),
            null,
            [.. value.LibraryStats.Select(Stat)]));

        List<UIElement> scanner = value.ScannerError is { Length: > 0 } error
            ? [Empty(error)]
            : value.ScannerAvailable
                ? [.. value.ScannerStats.Select(Stat)]
                : [Empty(AppResources.Get("noActiveScanner", "Text"))];
        Sections.Children.Add(Card(
            AppResources.Get("diagnosticsReportScannerSection", "Text"), null, scanner));
    }

    private static SettingsSection Card(string title, int? count, IList<UIElement> rows)
    {
        SettingsSection section = new()
        {
            HeaderText = count is { } value ? $"{title}  {value}" : title,
        };
        foreach (UIElement row in rows)
        {
            section.Rows.Add(row);
        }
        section.Apply();
        return section;
    }

    private static SettingsValueRow Stat(DiagnosticsStat stat) => new()
    {
        Label = stat.Label,
        ValueText = stat.Value,
        Kind = stat.IsWarning ? SettingsRowValueKind.Secondary : SettingsRowValueKind.Primary,
    };

    private static SettingsValueRow Line(string time, string message) => new()
    {
        Label = time,
        ValueText = message,
        Kind = SettingsRowValueKind.Secondary,
    };

    private static SettingsFootnote Empty(string text) => new() { Text = text };

    private void OnRefreshClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = RefreshAsync();
    }

    /// <summary>보고서 전체를 클립보드에 담습니다. macOS <c>DiagnosticsCopyButton</c> 자리입니다.</summary>
    private void OnCopyAllClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (report is not { } value)
        {
            return;
        }
        Windows.ApplicationModel.DataTransfer.DataPackage package = new();
        package.SetText(DiagnosticsReportText.PlainText(value, new DiagnosticsTextWords(
            AppResources.Get("commandDiagnostics", "Text"),
            AppResources.Get("diagnosticsGeneratedAt", "Text"),
            AppResources.Get("diagnosticsReportProblemsSection", "Text"),
            AppResources.Get("diagnosticsReportEventsSection", "Text"),
            AppResources.Get("diagnosticsReportLibrarySection", "Text"),
            AppResources.Get("diagnosticsReportScannerSection", "Text"),
            AppResources.Get("diagnosticsNoProblems", "Text"),
            AppResources.Get("noActiveScanner", "Text"))));
        Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
    }
}
