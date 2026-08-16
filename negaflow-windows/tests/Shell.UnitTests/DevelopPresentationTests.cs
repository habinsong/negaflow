using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopPresentationTests
{
    public static void Run()
    {
        VerifyDevelopInspectorPresentationState();
        VerifyDevelopHistogramSampler();
    }

    private static void VerifyDevelopInspectorPresentationState()
    {
        DevelopInspectorPresentationState state = new();
        Check(
            DevelopInspectorPresentationState.TabOrder.SequenceEqual(
                new[]
                {
                    DevelopInspectorTab.Basic,
                    DevelopInspectorTab.Base,
                    DevelopInspectorTab.Edit,
                    DevelopInspectorTab.Defects,
                    DevelopInspectorTab.Info,
                    DevelopInspectorTab.Reset,
                }),
            "develop_inspector_tab_order_matches_macos");
        Check(
            DevelopInspectorPresentationState.SectionOrder.SequenceEqual(
                new[]
                {
                    DevelopInspectorSection.Tone,
                    DevelopInspectorSection.ToneCurve,
                    DevelopInspectorSection.Color,
                    DevelopInspectorSection.ColorMixer,
                    DevelopInspectorSection.ColorGrading,
                    DevelopInspectorSection.BlackAndWhiteToning,
                    DevelopInspectorSection.Calibration,
                    DevelopInspectorSection.DetailAndEffects,
                    DevelopInspectorSection.Debug,
                }),
            "develop_inspector_section_order_matches_macos");
        Check(state.SelectedTab == DevelopInspectorTab.Basic,
            "develop_inspector_defaults_to_basic");
        Check(state.ExpandedSection == DevelopInspectorSection.Tone,
            "develop_inspector_defaults_to_tone");
        Check(state.ShowsAdjustmentSections,
            "develop_inspector_basic_shows_adjustments");

        state.SelectTab(DevelopInspectorTab.Base);
        Check(state.SelectedTab == DevelopInspectorTab.Base && state.ShowsAdjustmentSections,
            "develop_inspector_base_shows_adjustments");
        state.SelectTab(DevelopInspectorTab.Info);
        Check(!state.ShowsAdjustmentSections,
            "develop_inspector_info_hides_adjustments");

        state.Expand(DevelopInspectorSection.ToneCurve);
        Check(state.ExpandedSection == DevelopInspectorSection.ToneCurve,
            "develop_inspector_expands_one_section");
        state.Expand(DevelopInspectorSection.ColorMixer);
        Check(state.ExpandedSection == DevelopInspectorSection.ColorMixer,
            "develop_inspector_replaces_expanded_section");
        state.Collapse(DevelopInspectorSection.ToneCurve);
        Check(state.ExpandedSection == DevelopInspectorSection.ColorMixer,
            "develop_inspector_ignores_other_section_collapse");
        state.Collapse(DevelopInspectorSection.ColorMixer);
        Check(state.ExpandedSection is null,
            "develop_inspector_collapses_current_section");
    }

    private static void VerifyDevelopHistogramSampler()
    {
        byte[] pixels =
        [
            0, 0, 0, 255,
            0, 0, 255, 255,
            0, 255, 0, 255,
            255, 0, 0, 255,
        ];
        DevelopHistogramBins? bins = DevelopHistogramSampler.SampleBgra8(pixels, 4, 1);
        Check(bins is not null, "develop_histogram_samples_bgra8");
        if (bins is null)
        {
            return;
        }

        Check(bins.TotalPixels == 4,
            "develop_histogram_counts_opaque_pixels");
        Check(bins.Red[0] == 3 && bins.Red[^1] == 1 &&
            bins.Green[0] == 3 && bins.Green[^1] == 1 &&
            bins.Blue[0] == 3 && bins.Blue[^1] == 1,
            "develop_histogram_maps_bgra_channels");
        Check(bins.Luma[0] == 1 && bins.Luma[4] == 1 &&
            bins.Luma[13] == 1 && bins.Luma[45] == 1,
            "develop_histogram_uses_macos_luma_weights");
        Check(bins.ShadowRed == 3 && bins.HighlightRed == 1 &&
            bins.ShadowGreen == 3 && bins.HighlightGreen == 1 &&
            bins.ShadowBlue == 3 && bins.HighlightBlue == 1,
            "develop_histogram_counts_channel_clipping");
        // 클리핑 판정은 macOS 와 같은 "표본의 0.2%, 최소 1" 문턱입니다.
        Check(bins.ClippingThreshold == 1, "develop_histogram_clipping_threshold_has_a_floor");
        Check(
            bins.ClippedChannels.Count == 3 &&
            bins.ClippedChannels[0] == "R" &&
            bins.ClippedChannels[1] == "G" &&
            bins.ClippedChannels[2] == "B",
            "develop_histogram_reports_clipped_channels_in_rgb_order");

        // 문턱 아래는 경고하지 않습니다 — 화소 하나가 끝에 닿았다고 클리핑이라 부르지 않습니다.
        byte[] mostlyMidGrey = new byte[4000];
        for (int pixel = 0; pixel < 1000; ++pixel)
        {
            int offset = pixel * 4;
            mostlyMidGrey[offset] = 128;
            mostlyMidGrey[offset + 1] = 128;
            mostlyMidGrey[offset + 2] = pixel == 0 ? (byte)255 : (byte)128;
            mostlyMidGrey[offset + 3] = 255;
        }
        DevelopHistogramBins? gentle = DevelopHistogramSampler.SampleBgra8(mostlyMidGrey, 1000, 1);
        Check(
            gentle is not null && gentle.ClippingThreshold == 2 && gentle.ClippedChannels.Count == 0,
            "develop_histogram_ignores_clipping_below_the_threshold");

        Check(DevelopHistogramSampler.SampleBgra8([0, 0, 0, 255], 2, 1) is null,
            "develop_histogram_rejects_truncated_buffer");
        Check(DevelopHistogramSampler.SampleBgra8([], 0, 1) is null,
            "develop_histogram_rejects_invalid_size");
    }

}
