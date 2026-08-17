using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Info;

/// <summary>메타데이터 칸의 placeholder 와 접근성 이름을 한곳에서 맞춥니다.</summary>
internal static class DevelopMetadataBox
{
    public static void Localize(TextBox box, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Text");
        box.PlaceholderText = text;
        AutomationProperties.SetName(box, text);
    }
}
