using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

using Negaflow.Shell.Views;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>
/// 인화 검사기 카드가 쓰는 컨트롤입니다. macOS <c>PrintWorkspaceInspector</c> 의 세 탭
/// (레이아웃 · 콘텐츠 · 출력)에 나오는 것만 담습니다.
/// </summary>
/// <remarks>
/// 퍼포레이션은 macOS 에 없어 뺐습니다 — Windows 에만 있던 창작이었습니다.
/// </remarks>
internal sealed class PrintInspectorSurface
{
    // 레이아웃 탭
    public required PrintInspectorInlineField LayoutModeField { get; init; }
    public required Controls.NegaflowPopupPicker LayoutModeSelector { get; init; }
    public required PrintInspectorInlineField PaperSizeField { get; init; }
    public required Controls.NegaflowPopupPicker PaperSizeSelector { get; init; }
    public required PrintInspectorStackedField OrientationField { get; init; }
    public required Controls.NegaflowSegmentedPicker OrientationSelector { get; init; }
    public required TextBlock MarginText { get; init; }
    public required TextBlock MarginValueText { get; init; }
    public required Slider MarginSlider { get; init; }
    public required PrintInspectorStackedField RulerField { get; init; }
    public required Controls.NegaflowSegmentedPicker RulerSelector { get; init; }
    public required PrintInspectorStackedField RulerUnitField { get; init; }
    public required Controls.NegaflowSegmentedPicker RulerUnitSelector { get; init; }
    public required PrintInspectorStackedField SheetColorField { get; init; }
    public required Controls.NegaflowSegmentedPicker SheetBackgroundSelector { get; init; }
    public required PrintInspectorInlineField SurfaceField { get; init; }
    public required Controls.NegaflowPopupPicker SurfaceSelector { get; init; }

    // 패키지 배치(레이아웃 탭 두 번째 카드)
    public required FrameworkElement PackageLayoutCard { get; init; }
    public required FontIcon PackageLayoutIcon { get; init; }
    public required TextBlock PackageLayoutTitle { get; init; }
    public required FrameworkElement GridSizeRow { get; init; }
    public required PrintInspectorInlineField RowsField { get; init; }
    public required NumberBox RowsBox { get; init; }
    public required PrintInspectorInlineField ColumnsField { get; init; }
    public required NumberBox ColumnsBox { get; init; }
    public required PrintInspectorInlineField TemplateField { get; init; }
    public required Controls.NegaflowPopupPicker TemplateSelector { get; init; }
    public required TextBlock SpacingText { get; init; }
    public required TextBlock SpacingValueText { get; init; }
    public required Slider SpacingSlider { get; init; }
    public required FrameworkElement SpacingGroup { get; init; }
    public required TextBlock VerticalSpacingText { get; init; }
    public required TextBlock VerticalSpacingValueText { get; init; }
    public required Slider VerticalSpacingSlider { get; init; }
    public required PrintInspectorStackedField NormalizeOrientationField { get; init; }
    public required Controls.NegaflowSegmentedPicker NormalizeOrientationSelector { get; init; }
    public required FrameworkElement CustomPanel { get; init; }
    public required Panel CustomItemsHost { get; init; }
    public required Button CustomAddButton { get; init; }

    // 콘텐츠 탭
    public required PrintInspectorStackedField ContentFitField { get; init; }
    public required Controls.NegaflowSegmentedPicker ContentFitSelector { get; init; }
    public required PrintInspectorStackedField RotateToFitField { get; init; }
    public required Controls.NegaflowSegmentedPicker RotateToFitSelector { get; init; }
    public required FrameworkElement ContentFitGroup { get; init; }
    public required PrintInspectorInlineField CaptionField { get; init; }
    public required Controls.NegaflowPopupPicker CaptionSelector { get; init; }
    public required PrintInspectorStackedField CaptionAlignmentField { get; init; }
    public required Controls.NegaflowSegmentedPicker CaptionAlignmentSelector { get; init; }
    public required PrintInspectorStackedField RepeatField { get; init; }
    public required Controls.NegaflowSegmentedPicker RepeatSelector { get; init; }
    public required PrintInspectorInlineField CaptionFontField { get; init; }
    public required Controls.NegaflowPopupPicker CaptionFontSelector { get; init; }
    public required FrameworkElement CaptionDetailGroup { get; init; }
    public required FrameworkElement CaptionAlignmentGroup { get; init; }
    public required FrameworkElement CustomCaptionGroup { get; init; }
    public required Panel CustomCaptionsHost { get; init; }
    public required Button AddCaptionButton { get; init; }
    public required PrintInspectorStackedField ContentCropMarksField { get; init; }
    public required Controls.NegaflowSegmentedPicker ContentCropMarksSelector { get; init; }
    public required TextBlock ContentSectionText { get; init; }

    // 출력 탭
    public required Controls.NegaflowSegmentedPicker OutputProcessSelector { get; init; }
    public required PrintInspectorStackedField OutputProcessField { get; init; }
    public required TextBox CprintLabBox { get; init; }
    public required TextBox CprintPaperBox { get; init; }
    public required PrintInspectorInlineField CprintLabField { get; init; }
    public required PrintInspectorInlineField CprintPaperField { get; init; }
    public required Controls.NegaflowSegmentedPicker PrintProofPreviewSelector { get; init; }
    public required PrintInspectorStackedField ProofProfileField { get; init; }
    public required PrintInspectorStackedField ProofPreviewField { get; init; }
    public required TextBlock OutputSectionText { get; init; }

    // 고급 서랍 — macOS `PrintInspectorDisclosure(printAdvanced)` 안의 세 줄입니다.
    public required TextBlock AdvancedProofText { get; init; }
    public required PrintInspectorRow DeliveryColorSpaceRow { get; init; }
    public required TextBlock DeliveryColorSpaceValue { get; init; }
    public required PrintInspectorStackedField PaperSimulationField { get; init; }
    public required Views.Controls.NegaflowSegmentedPicker PaperSimulationSelector { get; init; }
    public required PrintInspectorStackedField GamutWarningField { get; init; }
    public required Views.Controls.NegaflowSegmentedPicker GamutWarningSelector { get; init; }
}
