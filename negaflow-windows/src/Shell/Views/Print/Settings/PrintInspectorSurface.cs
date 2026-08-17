using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>인화 검사기 카드가 쓰는 컨트롤입니다.</summary>
internal sealed class PrintInspectorSurface
{
    public required TextBlock LayoutModeText { get; init; }
    public required ComboBox LayoutModeSelector { get; init; }
    public required TextBlock PaperSizeText { get; init; }
    public required ComboBox PaperSizeSelector { get; init; }
    public required TextBlock OrientationText { get; init; }
    public required ComboBox OrientationSelector { get; init; }
    public required TextBlock PerforationText { get; init; }
    public required ComboBox PerforationSelector { get; init; }
    public required TextBlock DpiText { get; init; }
    public required ComboBox DpiSelector { get; init; }
    public required TextBlock MarginText { get; init; }
    public required Slider MarginSlider { get; init; }
    public required FrameworkElement SheetCard { get; init; }
    public required TextBlock SheetSectionText { get; init; }
    public required TextBlock RowsText { get; init; }
    public required NumberBox RowsBox { get; init; }
    public required TextBlock ColumnsText { get; init; }
    public required NumberBox ColumnsBox { get; init; }
    public required TextBlock SpacingText { get; init; }
    public required Slider SpacingSlider { get; init; }
    public required TextBlock ContentModeText { get; init; }
    public required ComboBox ContentModeSelector { get; init; }
    public required ToggleSwitch RotateToFitToggle { get; init; }
    public required ToggleSwitch RepeatToggle { get; init; }
    public required TextBlock SheetBackgroundText { get; init; }
    public required ComboBox SheetBackgroundSelector { get; init; }
    public required FrameworkElement TemplatePanel { get; init; }
    public required TextBlock TemplateText { get; init; }
    public required ComboBox TemplateSelector { get; init; }
    public required TextBlock CaptionModeText { get; init; }
    public required ComboBox CaptionModeSelector { get; init; }
    public required ToggleSwitch CropMarksToggle { get; init; }
    public required TextBlock ViewSectionText { get; init; }
    public required ToggleSwitch RulersToggle { get; init; }
    public required TextBlock RulerUnitText { get; init; }
    public required ComboBox RulerUnitSelector { get; init; }
    public required FrameworkElement CustomCard { get; init; }
    public required TextBlock CustomHintText { get; init; }
    public required TextBlock OutputSectionText { get; init; }
    public required Button PrintExportButton { get; init; }
}
