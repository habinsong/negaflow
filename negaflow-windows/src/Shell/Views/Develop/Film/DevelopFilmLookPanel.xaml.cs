using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Film;

/// <summary>
/// 디지털 소스의 필름 룩 선택입니다. 스캔 프레임에는 안내만 냅니다.
/// 실제 recipe 쓰기는 <see cref="LookChanged"/> 로 뷰에 맡깁니다.
/// </summary>
public sealed partial class DevelopFilmLookPanel : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizingInspector;

    public DevelopFilmLookPanel() => InitializeComponent();

    public event EventHandler<Func<DevelopPanelState, LibraryFrameError>>? LookChanged;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void Localize()
    {
        FilmLookUnavailableText.Text = AppResources.Get("developFilmLookDigitalOnly", "Text");
        FilmLookIntensityControl.Label = AppResources.Get("developFilmLookIntensity", "Text");
        Update();
    }

    public void Update()
    {
        if (FilmLookGroups is null)
        {
            return;
        }
        bool applies = panel?.AppliesFilmLook == true;
        FilmLookControls.Visibility = applies ? Visibility.Visible : Visibility.Collapsed;
        FilmLookUnavailableText.Visibility = applies ? Visibility.Collapsed : Visibility.Visible;
        if (!applies || panel?.SelectedFrame is not { } frame)
        {
            FilmLookGroups.ItemsSource = null;
            return;
        }

        FilmLookGroups.ItemsSource = FilmLookMenuProjection.Groups(
            frame.Route.FilmType,
            panel.FilmEmulation,
            AppResources.Get("developFilmLookNone", "Text"),
            FilmGroupTitle);
        isSynchronizingInspector = true;
        try
        {
            FilmLookIntensityControl.Value = panel.FilmEmulationIntensity;
        }
        finally
        {
            isSynchronizingInspector = false;
        }
    }

    private static string FilmGroupTitle(FilmEmulationKind kind) =>
        AppResources.Get(FilmLookMenuProjection.GroupTitleKey(kind), "Text");

    private void OnFilmLookChecked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (isSynchronizingInspector ||
            sender is not RadioButton { Tag: FilmEmulation emulation })
        {
            return;
        }
        LookChanged?.Invoke(this, state => state.SetFilmEmulation(emulation));
    }

    private void OnFilmLookIntensityChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizingInspector)
        {
            return;
        }
        LookChanged?.Invoke(this, state => state.SetFilmEmulationIntensity(args.Value));
    }
}
