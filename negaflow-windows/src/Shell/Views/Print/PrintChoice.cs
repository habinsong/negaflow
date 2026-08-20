using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Print;

/// <summary>고르개 한 줄입니다. 값과 보이는 이름을 함께 듭니다.</summary>
internal sealed record PrintChoice<T>(T Value, string Label)
{
    internal static PrintChoice<T> FromResource(T value, string key) =>
        new(value, AppResources.Get(key, "Text"));

    internal static T Selected(ComboBox selector, T fallback) =>
        selector.SelectedItem is PrintChoice<T> choice ? choice.Value : fallback;

    internal static void Select(ComboBox selector, T value)
    {
        foreach (object item in selector.ItemsSource is IEnumerable<object> source
                     ? source
                     : [])
        {
            if (item is PrintChoice<T> choice && EqualityComparer<T>.Default.Equals(
                    choice.Value,
                    value))
            {
                selector.SelectedItem = item;
                return;
            }
        }
    }

    /// <summary>세그먼트 컨트롤에 같은 목록을 넣습니다. 값과 이름은 그대로입니다.</summary>
    internal static void Fill(
        Views.Controls.NegaflowSegmentedPicker picker,
        IReadOnlyList<PrintChoice<T>> choices,
        T selected)
    {
        picker.SetOptions(
            [.. choices.Select(choice => new Views.Controls.SegmentOption(choice.Value!, choice.Label))],
            selected);
    }

    internal static T Selected(Views.Controls.NegaflowSegmentedPicker picker, T fallback) =>
        picker.SelectedValue is T value ? value : fallback;

    internal static void Select(Views.Controls.NegaflowSegmentedPicker picker, T value) =>
        picker.SetSelected(value);

    internal static void SetToggleLabel(ToggleSwitch toggle, string text)
    {
        toggle.Header = text;
        AutomationProperties.SetName(toggle, text);
    }
}
