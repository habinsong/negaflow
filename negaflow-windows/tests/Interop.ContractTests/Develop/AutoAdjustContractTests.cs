using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class AutoAdjustContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        const uint width = 64;
        const uint height = 48;
        byte[] pixels = new byte[width * height * 4];
        for (int index = 0; index < pixels.Length; index += 4)
        {
            int pixel = index / 4;
            pixels[index] = (byte)(pixel % 200);           // blue
            pixels[index + 1] = (byte)((pixel / 3) % 200); // green
            pixels[index + 2] = (byte)((pixel / 7) % 200); // red
            pixels[index + 3] = 0xFF;
        }

        AutoAdjustSettings settings = NativeAutoAdjust.Compute(pixels, width, height);
        context.Check(
            settings.Exposure >= -3.0 && settings.Exposure <= 3.0,
            "auto_adjust_exposure_inside_engine_range");
        context.Check(settings.Highlights <= 0.0, "auto_adjust_highlights_recover_only");
        context.Check(settings.Shadows >= 0.0, "auto_adjust_shadows_lift_only");
        context.Check(settings.Vibrance == 0.0, "auto_tone_does_not_propose_a_vibrance_change");
        double score = NativeAutoAdjust.ToneScore(pixels, width, height, adjustMid: true);
        context.Check(double.IsFinite(score) && score >= 0,
            "auto_tone_score_is_finite_for_a_valid_preview");
        context.CheckThrows<ArgumentException>(
            () => NativeAutoAdjust.ToneScore(new byte[16], width, height, adjustMid: true),
            "auto_tone_score_refuses_an_undersized_bitmap");
        // 잔차 클램프는 ±1(예전 슬라이더 끝)입니다 — 2026-10-14 ±0.6 에서 넓혔습니다.
        context.Check(
            settings.Warmth >= -1.0 && settings.Warmth <= 1.0 &&
                settings.Tint >= -1.0 && settings.Tint <= 1.0,
            "auto_adjust_white_balance_inside_clamp");

        // v2 는 필름 종류만 더 받습니다 — 컬러면 v1 과 같은 답입니다.
        AutoAdjustSettings colour = NativeAutoAdjust.Compute(pixels, width, height, blackAndWhiteNegative: false);
        context.Check(
            colour.Exposure == settings.Exposure && colour.Whites == settings.Whites &&
                colour.Warmth == settings.Warmth && colour.Tint == settings.Tint,
            "auto_adjust_v2_colour_matches_v1");

        // 폐루프는 노출과 화이트만 바로잡고 나머지는 첫 값 그대로 둡니다.
        AutoAdjustSettings refined = NativeAutoAdjust.Refine(pixels, width, height, false, colour);
        context.Check(
            refined.Contrast == colour.Contrast && refined.Highlights == colour.Highlights &&
                refined.Shadows == colour.Shadows && refined.Blacks == colour.Blacks &&
                refined.Density == colour.Density && refined.Vibrance == colour.Vibrance &&
                refined.Warmth == colour.Warmth && refined.Tint == colour.Tint,
            "auto_tone_refine_moves_only_exposure_and_whites");
        context.Check(
            refined.Exposure >= -3.0 && refined.Exposure <= 3.0 &&
                refined.Whites >= -1.0 && refined.Whites <= 1.0,
            "auto_tone_refine_stays_inside_the_automatic_ranges");

        // Assigning twice must not drift, because the shell assigns rather than accumulates.
        AutoAdjustSettings again = NativeAutoAdjust.Compute(pixels, width, height);
        context.Check(
            again.Exposure == settings.Exposure && again.Contrast == settings.Contrast &&
                again.Warmth == settings.Warmth && again.Tint == settings.Tint,
            "auto_adjust_is_deterministic_across_calls");

        context.CheckThrows<ArgumentException>(
            () => NativeAutoAdjust.Compute(new byte[16], width, height),
            "auto_adjust_refuses_a_buffer_smaller_than_its_dimensions");
        context.CheckThrows<ArgumentOutOfRangeException>(
            () => NativeAutoAdjust.Compute(pixels, 0, height),
            "auto_adjust_refuses_zero_width");
    }
}
