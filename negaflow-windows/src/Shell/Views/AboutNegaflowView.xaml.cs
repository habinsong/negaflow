using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>macOS <c>AboutNegaflowView</c> — 아이콘 96, 본문 460×330.</summary>
public sealed partial class AboutNegaflowView : UserControl
{
    public AboutNegaflowView()
    {
        InitializeComponent();
        LocalizedElement.Track(this, Localize);
    }

    private void Localize()
    {
        AnniversaryText.Text = AppResources.Get("aboutAnniversaryMessage", "Text");
        VersionText.Text = $"{AppResources.Get("aboutVersionLabel", "Text")} {ApplicationVersion()}";
        // macOS 는 이 줄을 `NSHumanReadableCopyright` 에서 읽고, 여섯 `InfoPlist.strings`
        // 어디에도 번역이 없습니다 — 법 문구라 모든 언어에서 같습니다.
        CopyrightText.Text = "Copyright 2026 Song Habin";
    }

    /// <summary>macOS 는 <c>CFBundleShortVersionString</c> 을 그대로 보여 줍니다 — 세 자리입니다.</summary>
    internal static string ApplicationVersion() => NegaflowProductVersion.Current;
}
