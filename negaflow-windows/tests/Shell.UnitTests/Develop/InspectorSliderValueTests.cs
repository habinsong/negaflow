using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

internal static class InspectorSliderValueTests
{
    public static void Run()
    {
        Check(
            InspectorSliderValue.Adjust(0, -5, 5, increase: true, coarse: false) == 0.01,
            "inspector_slider_fine_increment");
        Check(
            InspectorSliderValue.Adjust(0, -5, 5, increase: false, coarse: true) == -0.10,
            "inspector_slider_coarse_decrement");
        Check(
            InspectorSliderValue.Adjust(4.99, -5, 5, increase: true, coarse: true) == 5,
            "inspector_slider_clamps_upper_bound");
        Check(
            InspectorSliderValue.TryParse("-1.25", -5, 5, out double parsed) && parsed == -1.25,
            "inspector_slider_parses_valid_decimal");
        Check(
            InspectorSliderValue.TryParse(" 1.25 ", -5, 5, out double trimmed) && trimmed == 1.25,
            "inspector_slider_trims_decimal_input");
        Check(
            !InspectorSliderValue.TryParse("NaN", -5, 5, out _),
            "inspector_slider_rejects_non_finite");
        Check(
            !InspectorSliderValue.TryParse("5.01", -5, 5, out _),
            "inspector_slider_rejects_out_of_range");
        Check(
            !InspectorSliderValue.TryParse("1e2", -5, 5, out _),
            "inspector_slider_rejects_non_decimal_notation");
    }
}
