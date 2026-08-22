using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// macOS <c>QuickStartHelpView</c> — 가져오기/스캔 · 현상 · 내보내기 세 단계와 문서 판을
/// 냅니다. 문구는 <c>QuickStartHelpContent</c> 와 같은 것을 resw 로 옮겨 놓았습니다.
/// </summary>
public sealed partial class QuickStartHelpView : UserControl
{
    public QuickStartHelpView()
    {
        InitializeComponent();
        LocalizedElement.Track(this, Localize);
    }

    public void Localize()
    {
        TitleText.Text = AppResources.Get("helpQuickStartTitle", "Text");
        IntroductionText.Text = AppResources.Get("helpQuickStartIntroduction", "Text");
        ImportTitleText.Text = AppResources.Get("helpQuickStartImportTitle", "Text");
        ImportDetailText.Text = AppResources.Get("helpQuickStartImportDetail", "Text");
        DevelopTitleText.Text = AppResources.Get("helpQuickStartDevelopTitle", "Text");
        DevelopDetailText.Text = AppResources.Get("helpQuickStartDevelopDetail", "Text");
        ExportTitleText.Text = AppResources.Get("helpQuickStartExportTitle", "Text");
        ExportDetailText.Text = AppResources.Get("helpQuickStartExportDetail", "Text");
        ShortcutNoteText.Text = AppResources.Get("helpQuickStartShortcutNote", "Text");
        // macOS 는 versionLabel 뒤에 앱 판을 붙입니다(QuickStartHelpDocument.version).
        VersionText.Text =
            $"{AppResources.Get("helpQuickStartVersionLabel", "Text")} " +
            AboutNegaflowView.ApplicationVersion();
        AutomationProperties.SetAutomationId(this, "help.quickStart");
        AutomationProperties.SetName(this, TitleText.Text);
    }
}
