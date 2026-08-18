using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>macOS <c>AboutNegaflowView</c> — 아이콘 96, 본문 460×330.</summary>
public sealed partial class AboutNegaflowView : UserControl
{
    public AboutNegaflowView()
    {
        InitializeComponent();
        AnniversaryText.Text = AppResources.Get("aboutAnniversaryMessage", "Text");
        VersionText.Text = $"{AppResources.Get("aboutVersionLabel", "Text")} {ApplicationVersion()}";
        CopyrightText.Text = "Copyright 2026 Song Habin";
    }

    internal static string ApplicationVersion()
    {
        try
        {
            Windows.ApplicationModel.PackageVersion version =
                Windows.ApplicationModel.Package.Current.Id.Version;
            return $"{version.Major}.{version.Minor}.{version.Build}.{version.Revision}";
        }
        catch (Exception)
        {
            return "1.0.0.0";
        }
    }
}
