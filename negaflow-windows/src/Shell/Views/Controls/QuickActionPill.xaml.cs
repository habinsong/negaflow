using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 주 동작 + 오른쪽 보조 단추 알약입니다. macOS <c>QuickActionPill</c> 이식본입니다.
/// </summary>
public sealed partial class QuickActionPill : UserControl
{
    public QuickActionPill() => InitializeComponent();

    /// <summary>주 단추를 눌렀습니다.</summary>
    public event EventHandler? ActionInvoked;

    /// <summary>보조 단추를 눌렀습니다.</summary>
    public event EventHandler? TrailingInvoked;

    /// <summary>
    /// 이름표·아이콘·풍선 도움말을 채웁니다. 언어가 바뀔 때마다 다시 부릅니다.
    /// </summary>
    public void Configure(
        string title,
        string glyph,
        string help,
        string trailingGlyph,
        string trailingHelp)
    {
        ActionText.Text = title;
        ActionIcon.Glyph = glyph;
        TrailingIcon.Glyph = trailingGlyph;
        ToolTipService.SetToolTip(ActionButton, help);
        ToolTipService.SetToolTip(TrailingButton, trailingHelp);
        AutomationProperties.SetName(ActionButton, title);
        AutomationProperties.SetHelpText(ActionButton, help);
        AutomationProperties.SetName(TrailingButton, trailingHelp);
    }

    /// <summary>UI 자동화가 찾을 이름입니다. 보조 단추는 <c>.trailing</c> 을 붙입니다.</summary>
    public void SetAutomationId(string automationId)
    {
        AutomationProperties.SetAutomationId(ActionButton, automationId);
        AutomationProperties.SetAutomationId(TrailingButton, automationId + ".trailing");
    }

    /// <summary>
    /// 주 동작만 막습니다. 보조 단추(예: 탐색기에서 보기)는 계속 누를 수 있어야 합니다.
    /// </summary>
    public bool IsActionEnabled
    {
        get => ActionButton.IsEnabled;
        set => ActionButton.IsEnabled = value;
    }

    private void OnActionClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ActionInvoked?.Invoke(this, EventArgs.Empty);
    }

    private void OnTrailingClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        TrailingInvoked?.Invoke(this, EventArgs.Empty);
    }
}
