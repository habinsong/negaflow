using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class AppMenuBarView
{
    public event EventHandler<DevelopTarget>? CustomTargetRequested;

    private void BuildCustomTargetMenu()
    {
        CustomTargetSubmenu.Text = AppResources.Get("customTarget", "Text");
        CustomTargetSubmenu.Items.Clear();
        foreach (IReadOnlyList<DevelopTarget> group in DevelopTargets.CustomGroups)
        {
            if (CustomTargetSubmenu.Items.Count > 0) { CustomTargetSubmenu.Items.Add(new MenuFlyoutSeparator()); }
            foreach (DevelopTarget target in group)
            {
                ToggleMenuFlyoutItem item = new() { Text = DevelopTargets.DisplayName(target), Tag = target };
                AutomationProperties.SetAutomationId(item, "negaflow.menu.develop.target." + DevelopTargets.CustomId(target));
                item.Click += (_, _) => CustomTargetRequested?.Invoke(this, target);
                CustomTargetSubmenu.Items.Add(item);
            }
        }
    }

    private void SyncCustomTargetMenu(DevelopMenuState state)
    {
        foreach (ToggleMenuFlyoutItem item in CustomTargetSubmenu.Items.OfType<ToggleMenuFlyoutItem>())
        {
            item.IsChecked = item.Tag is DevelopTarget target && state.IsTargetChecked(target);
        }
    }
}
