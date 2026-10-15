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

        // 온도·틴트 손잡이의 거듭제곱 눈금 — 예전 끝값(±1)이 손잡이 40% 지점, 범위 끝은 ±4.
        double exponent = Negaflow.Catalog.ColorModelRecipe.WhiteBalancePositionExponent;
        Check(
            Math.Abs(InspectorSliderValue.PositionFromValue(1.0, 4.0, exponent) - 0.4) < 1e-12 &&
            Math.Abs(InspectorSliderValue.PositionFromValue(-1.0, 4.0, exponent) + 0.4) < 1e-12,
            "white_balance_legacy_edge_sits_at_forty_percent");
        Check(
            InspectorSliderValue.ValueFromPosition(1.0, 4.0, exponent) == 4.0 &&
            InspectorSliderValue.ValueFromPosition(0.0, 4.0, exponent) == 0.0,
            "white_balance_position_scale_spans_the_range");
        bool roundTrips = true;
        foreach (double value in new[] { -4.0, -1.37, -0.05, 0.0, 0.02, 0.6, 3.99 })
        {
            double position = InspectorSliderValue.PositionFromValue(value, 4.0, exponent);
            roundTrips &= Math.Abs(InspectorSliderValue.ValueFromPosition(position, 4.0, exponent) - value) < 1e-9;
        }
        Check(roundTrips, "white_balance_position_scale_round_trips");
        Check(
            InspectorSliderValue.ValueFromPosition(0.1, 4.0, exponent) < 0.1,
            "white_balance_position_scale_is_finer_near_center");
    }
}
