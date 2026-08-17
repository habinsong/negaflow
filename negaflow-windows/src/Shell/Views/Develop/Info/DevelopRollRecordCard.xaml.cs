using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Info;

/// <summary>
/// 롤 기록 카드입니다. 이 frame 이 롤에 속해 있을 때만 칸이 나오고, 아니면 macOS 와 같이
/// 아직 롤에 속해 있지 않다고 알립니다.
/// </summary>
public sealed partial class DevelopRollRecordCard : UserControl
{
    public DevelopRollRecordCard() => InitializeComponent();

    public event EventHandler? Committed;

    public event EventHandler? CreateRequested;

    public void Localize()
    {
        string card = AppResources.Get("developRollRecordCard", "Text");
        TitleText.Text = card;
        AutomationProperties.SetName(Card, card);
        MissingText.Text = AppResources.Get("developRollMissing", "Text");
        FillHintText.Text = AppResources.Get("developRollFillHint", "Text");
        DevelopMetadataBox.Localize(CodeBox, "developRollCode");
        DevelopMetadataBox.Localize(CameraMakeBox, "developFilmShotCameraMake");
        DevelopMetadataBox.Localize(CameraModelBox, "developFilmShotCameraModel");
        DevelopMetadataBox.Localize(LensModelBox, "developFilmShotLensModel");
        DevelopMetadataBox.Localize(FilmStockBox, "developFilmShotFilmStock");
        DevelopMetadataBox.Localize(NotesBox, "developRollNotes");
        string create = AppResources.Get("developRollCreateFromSelection", "Content");
        CreateButton.Content = create;
        AutomationProperties.SetName(CreateButton, create);
        ToolTipService.SetToolTip(CreateButton, create);
    }

    public void Show(LibraryRollSnapshot? roll)
    {
        RollNameText.Text = roll?.Name ?? string.Empty;
        MissingText.Visibility = roll is null ? Visibility.Visible : Visibility.Collapsed;
        CreateButton.Visibility = MissingText.Visibility;
        Fields.Visibility = roll is null ? Visibility.Collapsed : Visibility.Visible;
        if (roll is null)
        {
            return;
        }

        RollRecord record = roll.Record ?? new RollRecord();
        FilmShotMetadata shot = record.Shot ?? new FilmShotMetadata();
        CodeBox.Text = record.Code ?? string.Empty;
        NotesBox.Text = record.Notes ?? string.Empty;
        CameraMakeBox.Text = shot.CameraMake ?? string.Empty;
        CameraModelBox.Text = shot.CameraModel ?? string.Empty;
        LensModelBox.Text = shot.LensModel ?? string.Empty;
        FilmStockBox.Text = shot.FilmStock ?? string.Empty;
    }

    public RollRecord Read() => new(
        CodeBox.Text,
        new FilmShotMetadata(
            CameraMakeBox.Text,
            CameraModelBox.Text,
            LensModelBox.Text,
            FilmStockBox.Text),
        NotesBox.Text);

    private void OnCommitted(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Committed?.Invoke(this, EventArgs.Empty);
    }

    private void OnCreateClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CreateRequested?.Invoke(this, EventArgs.Empty);
    }
}
