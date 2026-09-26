using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

/// <summary>
/// 진단 패널의 카탈로그 수동 복구·재설치 동작입니다. 창이 채워 줍니다.
/// </summary>
/// <param name="CanRun">
/// 주 단추를 누를 수 있는지입니다. 스캔·스캔 마무리·내보내기·인쇄 내보내기·유지보수·종료
/// 저장 중이거나 라이브러리가 열려 있지 않으면 <see langword="false"/> 입니다.
/// </param>
/// <param name="CatalogPath">카탈로그 파일 경로입니다. 보조 단추의 풍선 도움말에 씁니다.</param>
public sealed record DiagnosticsCatalogMaintenance(
    Func<bool> CanRun,
    Func<Task> Repair,
    Func<Task> Reinstall,
    Action RevealCatalog,
    Func<string?> CatalogPath);

/// <summary>
/// 진단 패널 맨 아래 한 줄입니다. macOS <c>DiagnosticsLibraryMaintenanceBar</c> 이식본입니다.
/// </summary>
/// <remarks>
/// macOS 는 모델을 관찰해 스캔·내보내기가 시작되면 곧바로 단추를 잠급니다. 여기는 그 상태가 셸
/// 여러 곳에 흩어져 있어 보이는 동안 1초마다 다시 봅니다 — 값 몇 개를 읽는 일이라 비용이 없습니다.
/// </remarks>
public sealed partial class DiagnosticsLibraryMaintenanceBar : UserControl
{
    private readonly DispatcherQueueTimer? timer;
    private DiagnosticsCatalogMaintenance? maintenance;

    public DiagnosticsLibraryMaintenanceBar()
    {
        InitializeComponent();
        RepairPill.SetAutomationId("negaflow.diagnostics.catalogRepair");
        ReinstallPill.SetAutomationId("negaflow.diagnostics.catalogReinstall");
        RepairPill.ActionInvoked += async (_, _) => await RunAsync(m => m.Repair());
        ReinstallPill.ActionInvoked += async (_, _) => await RunAsync(m => m.Reinstall());
        RepairPill.TrailingInvoked += (_, _) => maintenance?.RevealCatalog();
        ReinstallPill.TrailingInvoked += (_, _) => maintenance?.RevealCatalog();
        timer = DispatcherQueue?.CreateTimer();
        if (timer is not null)
        {
            timer.Interval = TimeSpan.FromSeconds(1);
            timer.Tick += (_, _) => UpdateEnabled();
        }
        Loaded += (_, _) => timer?.Start();
        Unloaded += (_, _) => timer?.Stop();
        LocalizedElement.Track(this, Localize);
    }

    public DiagnosticsCatalogMaintenance? Maintenance
    {
        get => maintenance;
        set
        {
            maintenance = value;
            Localize();
        }
    }

    private void Localize()
    {
        string reveal = AppResources.Get("showInExplorer", "Value") +
            (maintenance?.CatalogPath() is { Length: > 0 } path ? " — " + path : string.Empty);
        RepairPill.Configure(
            AppResources.Get("libraryCatalogRepairAction", "Text"),
            "",
            AppResources.Get("libraryCatalogRepairHelp", "Text"),
            "",
            reveal);
        ReinstallPill.Configure(
            AppResources.Get("libraryCatalogReinstallAction", "Text"),
            "",
            AppResources.Get("libraryCatalogReinstallHelp", "Text"),
            "",
            reveal);
        UpdateEnabled();
    }

    private void UpdateEnabled()
    {
        bool enabled = maintenance?.CanRun() == true;
        RepairPill.IsActionEnabled = enabled;
        ReinstallPill.IsActionEnabled = enabled;
    }

    /// <summary>확인 창 없이 곧바로 합니다. 도는 동안 두 주 단추를 잠급니다.</summary>
    private async Task RunAsync(Func<DiagnosticsCatalogMaintenance, Task> action)
    {
        if (maintenance is not { } current || !current.CanRun())
        {
            return;
        }
        RepairPill.IsActionEnabled = false;
        ReinstallPill.IsActionEnabled = false;
        try
        {
            await action(current);
        }
        finally
        {
            UpdateEnabled();
        }
    }
}
