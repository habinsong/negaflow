using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Info;

/// <summary>
/// 적어 둔 앱 메타데이터를 컨트롤에 되비춥니다. 값이 없으면 빈 칸이고, placeholder 가 무엇을
/// 적는 자리인지 말합니다 — macOS 도 라벨 대신 placeholder 를 씁니다.
/// </summary>
public sealed partial class DevelopAppMetadataCard : UserControl
{
    public DevelopAppMetadataCard() => InitializeComponent();

    public event EventHandler? Committed;

    public void Localize()
    {
        string card = AppResources.Get("developAppMetadataCard", "Text");
        TitleText.Text = card;
        AutomationProperties.SetName(Card, card);
        DevelopMetadataBox.Localize(TitleBox, "developAppMetadataTitle");
        DevelopMetadataBox.Localize(CaptionBox, "developAppMetadataCaption");
        DevelopMetadataBox.Localize(KeywordsBox, "developAppMetadataKeywords");
        DevelopMetadataBox.Localize(CopyrightBox, "developAppMetadataCopyright");
    }

    public void Show(AppMetadataOverlay overlay)
    {
        TitleBox.Text = overlay.Title ?? string.Empty;
        CaptionBox.Text = overlay.Caption ?? string.Empty;
        KeywordsBox.Text = string.Join(", ", overlay.Keywords);
        CopyrightBox.Text = overlay.Copyright ?? string.Empty;
        SavedText.Text = overlay.IsEmpty
            ? string.Empty
            : AppResources.Get("developAppMetadataSaved", "Text");
    }

    public AppMetadataOverlay Read(FilmShotMetadata? filmShot) => new()
    {
        Title = TitleBox.Text,
        Caption = CaptionBox.Text,
        Keywords = DevelopMetadataFields.SplitKeywords(KeywordsBox.Text),
        Copyright = CopyrightBox.Text,
        FilmShot = filmShot,
    };

    private void OnCommitted(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Committed?.Invoke(this, EventArgs.Empty);
    }
}
