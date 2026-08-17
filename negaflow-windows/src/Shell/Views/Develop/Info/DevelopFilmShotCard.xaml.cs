using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Info;

/// <summary>필름 카메라가 남기지 않는 촬영 값을 적는 카드입니다.</summary>
public sealed partial class DevelopFilmShotCard : UserControl
{
    public DevelopFilmShotCard() => InitializeComponent();

    public event EventHandler? Committed;

    public void Localize()
    {
        string shotCard = AppResources.Get("developFilmShotCard", "Text");
        TitleText.Text = shotCard;
        AutomationProperties.SetName(Card, shotCard);
        DevelopMetadataBox.Localize(CameraMakeBox, "developFilmShotCameraMake");
        DevelopMetadataBox.Localize(CameraModelBox, "developFilmShotCameraModel");
        DevelopMetadataBox.Localize(LensModelBox, "developFilmShotLensModel");
        DevelopMetadataBox.Localize(FilmStockBox, "developFilmShotFilmStock");
        DevelopMetadataBox.Localize(IsoSpeedBox, "developFilmShotIsoSpeed");
        DevelopMetadataBox.Localize(ShutterBox, "developFilmShotShutter");
        DevelopMetadataBox.Localize(ApertureBox, "developFilmShotAperture");
        DevelopMetadataBox.Localize(FocalLengthBox, "developFilmShotFocalLength");
    }

    public void Show(FilmShotMetadata shot)
    {
        CameraMakeBox.Text = shot.CameraMake ?? string.Empty;
        CameraModelBox.Text = shot.CameraModel ?? string.Empty;
        LensModelBox.Text = shot.LensModel ?? string.Empty;
        FilmStockBox.Text = shot.FilmStock ?? string.Empty;
        IsoSpeedBox.Text = shot.IsoSpeed?.ToString(CultureInfo.CurrentCulture)
            ?? string.Empty;
        ShutterBox.Text = DevelopMetadataFields.FormatShutter(shot.ExposureTimeSeconds);
        ApertureBox.Text = shot.FNumber?.ToString("0.##", CultureInfo.CurrentCulture)
            ?? string.Empty;
        FocalLengthBox.Text =
            shot.FocalLengthMm?.ToString("0.##", CultureInfo.CurrentCulture) ?? string.Empty;
    }

    public FilmShotMetadata Read() => new(
        CameraMakeBox.Text,
        CameraModelBox.Text,
        LensModelBox.Text,
        FilmStockBox.Text,
        DevelopMetadataFields.ParseInteger(IsoSpeedBox.Text),
        DevelopMetadataFields.ParseShutter(ShutterBox.Text),
        DevelopMetadataFields.ParseNumber(ApertureBox.Text),
        DevelopMetadataFields.ParseNumber(FocalLengthBox.Text));

    private void OnCommitted(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Committed?.Invoke(this, EventArgs.Empty);
    }
}
