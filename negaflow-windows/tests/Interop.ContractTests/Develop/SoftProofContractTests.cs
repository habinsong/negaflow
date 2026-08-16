using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class SoftProofContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        // A display profile has to come back as an identity proof. If it did not, choosing
        // sRGB as the proof destination would visibly tint the frame.
        const string installed =
            @"C:\Windows\System32\spool\drivers\color\sRGB Color Space Profile.icm";
        if (File.Exists(installed))
        {
            byte[] profile = File.ReadAllBytes(installed);
            SoftProofMedia media = NativeSoftProof.ReadMedia(profile);
            context.Check(media.IsRgbOutputProfile, "soft_proof_accepts_an_rgb_display_profile");
            context.Check(media.HasWhite, "soft_proof_reads_the_white_point");
            context.Check(
                Math.Abs(media.PaperWhite.Red - 1.0) < 0.002 &&
                    Math.Abs(media.PaperWhite.Green - 1.0) < 0.002 &&
                    Math.Abs(media.PaperWhite.Blue - 1.0) < 0.002,
                "soft_proof_display_profile_is_an_identity_paper");
        }

        // Anything that is not a renderable RGB profile has to be refused here, at the
        // point of choosing, rather than silently producing nothing at render time.
        SoftProofMedia empty = NativeSoftProof.ReadMedia(ReadOnlySpan<byte>.Empty);
        context.Check(
            !empty.IsRgbOutputProfile && !empty.HasWhite && !empty.HasBlack,
            "soft_proof_refuses_an_absent_profile");
        context.Check(
            empty.PaperWhite == SoftProofRgb.White && empty.BlackInk == SoftProofRgb.Black,
            "soft_proof_falls_back_to_a_neutral_paper");

        SoftProofMedia malformed = NativeSoftProof.ReadMedia(new byte[64]);
        context.Check(
            !malformed.IsRgbOutputProfile,
            "soft_proof_refuses_a_malformed_profile");

        SoftProofSettings settings = SoftProofSettings.From(
            new SoftProofMedia(
                true,
                true,
                true,
                new SoftProofRgb(0.9, 0.9, 0.95),
                new SoftProofRgb(0.04, 0.04, 0.05)),
            SoftProofSimulation.PaperAndBlackInk);
        context.Check(
            settings.IsEnabled &&
                settings.Simulation == SoftProofSimulation.PaperAndBlackInk &&
                settings.PaperWhite.Blue == 0.95 && settings.BlackInk.Blue == 0.05,
            "soft_proof_settings_carry_the_resolved_media");
        context.Check(
            !SoftProofSettings.Disabled.IsEnabled &&
                SoftProofSettings.Disabled.PaperWhite == SoftProofRgb.White,
            "soft_proof_disabled_is_a_neutral_identity");
    }
}
