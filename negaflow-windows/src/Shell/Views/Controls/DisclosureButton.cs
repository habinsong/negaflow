using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Controls;

public sealed class DisclosureExpansionRequestedEventArgs(bool isExpanded) : EventArgs
{
    public bool IsExpanded { get; } = isExpanded;
}

public sealed class DisclosureButton : Button
{
    public static readonly DependencyProperty IsExpandedProperty = DependencyProperty.Register(
        nameof(IsExpanded),
        typeof(bool),
        typeof(DisclosureButton),
        new PropertyMetadata(false, OnIsExpandedChanged));

    public bool IsExpanded
    {
        get => (bool)GetValue(IsExpandedProperty);
        set => SetValue(IsExpandedProperty, value);
    }

    public event EventHandler<DisclosureExpansionRequestedEventArgs>? ExpansionRequested;

    internal void RequestExpansion(bool isExpanded) =>
        ExpansionRequested?.Invoke(this, new DisclosureExpansionRequestedEventArgs(isExpanded));

    protected override AutomationPeer OnCreateAutomationPeer() =>
        new DisclosureButtonAutomationPeer(this);

    private static void OnIsExpandedChanged(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args)
    {
        if (sender is not DisclosureButton button ||
            FrameworkElementAutomationPeer.FromElement(button) is not DisclosureButtonAutomationPeer peer)
        {
            return;
        }

        peer.RaiseExpandedStateChanged((bool)args.OldValue, (bool)args.NewValue);
    }
}

internal sealed class DisclosureButtonAutomationPeer(DisclosureButton owner) :
    ButtonAutomationPeer(owner),
    IExpandCollapseProvider
{
    private DisclosureButton DisclosureOwner => (DisclosureButton)Owner;

    public ExpandCollapseState ExpandCollapseState => DisclosureOwner.IsExpanded
        ? ExpandCollapseState.Expanded
        : ExpandCollapseState.Collapsed;

    public void Collapse() => DisclosureOwner.RequestExpansion(false);

    public void Expand() => DisclosureOwner.RequestExpansion(true);

    protected override object GetPatternCore(PatternInterface patternInterface) =>
        patternInterface == PatternInterface.ExpandCollapse
            ? this
            : base.GetPatternCore(patternInterface);

    internal void RaiseExpandedStateChanged(bool oldValue, bool newValue) =>
        RaisePropertyChangedEvent(
            ExpandCollapsePatternIdentifiers.ExpandCollapseStateProperty,
            oldValue ? ExpandCollapseState.Expanded : ExpandCollapseState.Collapsed,
            newValue ? ExpandCollapseState.Expanded : ExpandCollapseState.Collapsed);
}
