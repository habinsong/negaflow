using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Develop.Perspective;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// 변환(원근) — 모드 캡슐 두 줄, 슬라이더 일곱 개, 자르기 제한입니다. macOS <c>TransformSection</c> 과
/// 같은 구성·같은 동작(두 번 누르면 기본값, 값 칸을 눌러 직접 입력)입니다.
/// </summary>
public sealed partial class DevelopTransformSection : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopTransformSection() => InitializeComponent();

    public event EventHandler? PreviewRequested;

    public event EventHandler? ToggleRequested;

    public event EventHandler<DisclosureExpansionRequestedEventArgs>? ExpansionRequested;

    public event EventHandler<Func<DevelopPanelState, LibraryFrameError>>? ResetRequested;

    /// <summary>자동 계열 모드를 골랐습니다. 화면의 현상본으로 선을 찾는 일은 뷰가 맡습니다.</summary>
    public event EventHandler<PerspectiveMode>? AutoSolveRequested;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void Localize()
    {
        DevelopInspectorSectionChrome.Localize(
            TransformSectionBorder,
            TransformHeaderButton,
            TransformSectionTitleText,
            TransformResetButton,
            AppResources.Get("developTransform", "Text"));
        ModeOffButton.Content = AppResources.Get("transformModeOff", "Text");
        ModeAutoButton.Content = AppResources.Get("transformModeAuto", "Text");
        ModeGuidedButton.Content = AppResources.Get("transformModeGuided", "Text");
        ModeLevelButton.Content = AppResources.Get("transformModeLevel", "Text");
        ModeVerticalButton.Content = AppResources.Get("transformModeVertical", "Text");
        ModeFullButton.Content = AppResources.Get("transformModeFull", "Text");
        VerticalControl.Label = AppResources.Get("transformVertical", "Text");
        HorizontalControl.Label = AppResources.Get("transformHorizontal", "Text");
        RotateControl.Label = AppResources.Get("transformRotate", "Text");
        AspectControl.Label = AppResources.Get("transformAspect", "Text");
        ScaleControl.Label = AppResources.Get("transformScale", "Text");
        OffsetXControl.Label = AppResources.Get("transformOffsetX", "Text");
        OffsetYControl.Label = AppResources.Get("transformOffsetY", "Text");
        ConstrainCropCheck.Content = AppResources.Get("transformConstrainCrop", "Text");
        GuidedHintText.Text = AppResources.Get("transformGuidedHint", "Text");
        ClearGuidesButton.Content = AppResources.Get("transformGuidedClear", "Text");
    }

    public void Show(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        PerspectiveRecipe perspective =
            hostPanel.SelectedFrame?.ImageTransform.Perspective ?? PerspectiveRecipe.Identity;
        isSynchronizing = true;
        try
        {
            RadioButton selected = perspective.Mode switch
            {
                PerspectiveMode.Auto => ModeAutoButton,
                PerspectiveMode.Guided => ModeGuidedButton,
                PerspectiveMode.Level => ModeLevelButton,
                PerspectiveMode.Vertical => ModeVerticalButton,
                PerspectiveMode.Full => ModeFullButton,
                _ => ModeOffButton,
            };
            selected.IsChecked = true;
            VerticalControl.Value = perspective.Vertical;
            HorizontalControl.Value = perspective.Horizontal;
            RotateControl.Value = perspective.Rotate;
            AspectControl.Value = perspective.Aspect;
            ScaleControl.Value = perspective.Scale;
            OffsetXControl.Value = perspective.OffsetX;
            OffsetYControl.Value = perspective.OffsetY;
            ConstrainCropCheck.IsChecked = perspective.ConstrainCrop;
            bool guided = perspective.Mode == PerspectiveMode.Guided;
            GuidedHintText.Visibility = guided ? Visibility.Visible : Visibility.Collapsed;
            ClearGuidesButton.Visibility = guided && perspective.Guides.Count > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    public void SetEnabled(bool enabled)
    {
        foreach (Control control in new Control[]
                 {
                     ModeOffButton, ModeAutoButton, ModeGuidedButton, ModeLevelButton, ModeVerticalButton,
                     ModeFullButton, VerticalControl, HorizontalControl, RotateControl, AspectControl,
                     ScaleControl, OffsetXControl, OffsetYControl, ConstrainCropCheck, ClearGuidesButton,
                 })
        {
            control.IsEnabled = enabled;
        }
    }

    public void ApplyExpanded(bool expanded) =>
        DevelopInspectorSectionChrome.Apply(TransformHeaderButton, TransformChevron, TransformControls, expanded);

    private void Update(Func<PerspectiveRecipe, PerspectiveRecipe> change)
    {
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.SetPerspective(change) == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnModeChecked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (isSynchronizing || panel?.SelectedFrame is not { } frame ||
            sender is not RadioButton { Tag: string tag } ||
            !Enum.TryParse(tag, out PerspectiveMode mode) ||
            frame.ImageTransform.Perspective.Mode == mode)
        {
            return;
        }
        switch (mode)
        {
            case PerspectiveMode.Off:
                // 끄면 푼 값만 지우고 슬라이더는 그대로 둡니다(macOS 와 같음).
                Update(p => p with { Mode = PerspectiveMode.Off, SolvedVertical = 0, SolvedHorizontal = 0, SolvedRotate = 0 });
                break;
            case PerspectiveMode.Guided:
                uint width = frame.SourceMetadata?.PixelWidth ?? 0U;
                uint height = frame.SourceMetadata?.PixelHeight ?? 0U;
                Update(p => PerspectiveWorkflow.WithGuidedSolution(p, frame.ImageTransform, width, height));
                break;
            default:
                Update(p => p with { Mode = mode });
                AutoSolveRequested?.Invoke(this, mode);
                break;
        }
        Show(panel);
    }

    private void OnSliderChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        double value = args.Value;
        if (ReferenceEquals(sender, VerticalControl)) { Update(p => p with { Vertical = value }); }
        else if (ReferenceEquals(sender, HorizontalControl)) { Update(p => p with { Horizontal = value }); }
        else if (ReferenceEquals(sender, RotateControl)) { Update(p => p with { Rotate = value }); }
        else if (ReferenceEquals(sender, AspectControl)) { Update(p => p with { Aspect = value }); }
        else if (ReferenceEquals(sender, ScaleControl)) { Update(p => p with { Scale = value }); }
        else if (ReferenceEquals(sender, OffsetXControl)) { Update(p => p with { OffsetX = value }); }
        else if (ReferenceEquals(sender, OffsetYControl)) { Update(p => p with { OffsetY = value }); }
    }

    private void OnConstrainCropChanged(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        bool constrain = ConstrainCropCheck.IsChecked == true;
        Update(p => p with { ConstrainCrop = constrain });
    }

    private void OnClearGuidesClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        uint width = frame.SourceMetadata?.PixelWidth ?? 0U;
        uint height = frame.SourceMetadata?.PixelHeight ?? 0U;
        Update(p => PerspectiveWorkflow.WithGuidedSolution(p with { Guides = [] }, frame.ImageTransform, width, height));
        Show(panel);
    }

    private void OnTransformResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetRequested?.Invoke(this, static state => state.SetPerspective(_ => PerspectiveRecipe.Identity));
    }

    private void OnInspectorSectionHeaderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ToggleRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnInspectorSectionExpansionRequested(object? sender, DisclosureExpansionRequestedEventArgs args)
    {
        _ = sender;
        ExpansionRequested?.Invoke(this, args);
    }
}
