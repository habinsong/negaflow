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
        context.Check(settings.Vibrance >= 0.0, "auto_adjust_vibrance_increases_only");
        context.Check(
            settings.Warmth >= -0.6 && settings.Warmth <= 0.6 &&
                settings.Tint >= -0.6 && settings.Tint <= 0.6,
            "auto_adjust_white_balance_inside_clamp");

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
