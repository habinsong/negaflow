using System.Runtime.InteropServices;
using System.Text.Json;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class ContractTestRunner
{
    private static readonly List<string> Failures = [];
    private static int assertionCount;

    internal static int Run(string[] args)
    {
        if (args.Length != 1)
        {
            Console.Error.WriteLine("Usage: Negaflow.Interop.ContractTests <absolute-native-dll-path>");
            return 2;
        }

        VerifyManagedLayout();
        VerifyPathPolicy();

        NativeBuildInfo? buildInfo = null;
        try
        {
            buildInfo = NativeEngineBootstrap.LoadAndQuery(args[0]);
            VerifyBuildInfo(buildInfo);
            Check(
                NativeEngineBootstrap.LoadAndQuery(args[0]) == buildInfo,
                "same_path_reload_is_idempotent");
            VerifyDevelopExportContract();
            VerifyRunStateContract();
            VerifyAutoAdjustContract();
            VerifySoftProofContract();
            VerifyToneLimits();
            VerifyNegativeLimits();
        }
        catch (Exception exception)
        {
            Failures.Add($"bootstrap:{exception.GetType().Name}");
        }

        var report = new
        {
            status = Failures.Count == 0 ? "ok" : "failed",
            operation = "interop_contract",
            assertions = assertionCount,
            failures = Failures,
            abi_version = buildInfo?.AbiVersion.ToString(),
            architecture = buildInfo?.Architecture.ToString().ToLowerInvariant(),
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return Failures.Count == 0 ? 0 : 1;
    }

    private static void VerifyManagedLayout()
    {
        Check((int)DevelopExportStage.DefectBrush == 21, "defect_brush_stage_value");
        Check(sizeof(NativeBuildInfoV1) == NativeAbiReader.BuildInfoV1Size, "build_info_size");
        Check(
            Marshal.OffsetOf<NativeBuildInfoV1>(nameof(NativeBuildInfoV1.SourceCommitSha1)).ToInt32() ==
                NativeAbiReader.SourceCommitSha1Offset,
            "source_commit_offset");

        // The native side static_asserts the same three numbers. Both halves have to
        // be checked, because a layout drift binds cleanly and then reads garbage.
        Check(
            sizeof(NativeDevelopExportRequestV1) == NativeDevelopExporter.RequestV1Size,
            "develop_export_request_size");
        Check(
            sizeof(NativeDevelopExportResultV1) == NativeDevelopExporter.ResultV1Size,
            "develop_export_result_size");
        Check(
            sizeof(NativeDevelopExportRequestV2) == NativeDevelopExporter.RequestV2Size,
            "develop_export_v2_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV3) == NativeDevelopExporter.RequestV3Size,
            "develop_export_v3_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV4) == NativeDevelopExporter.RequestV4Size,
            "develop_export_v4_request_size");
        Check(
            sizeof(NativePointCurveV1) == NativeDevelopExporter.PointCurveV1Size,
            "point_curve_v1_size");
        Check(
            sizeof(NativeDevelopExportRequestV5) == NativeDevelopExporter.RequestV5Size,
            "develop_export_v5_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV6) == NativeDevelopExporter.RequestV6Size,
            "develop_export_v6_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV7) == NativeDevelopExporter.RequestV7Size,
            "develop_export_v7_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV8) == NativeDevelopExporter.RequestV8Size,
            "develop_export_v8_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV9) == NativeDevelopExporter.RequestV9Size,
            "develop_export_v9_request_size");
          Check(
              sizeof(NativeDevelopExportRequestV10) == NativeDevelopExporter.RequestV10Size,
              "develop_export_v10_request_size");
          Check(
              sizeof(NativeDevelopExportRequestV11) == NativeDevelopExporter.RequestV11Size,
              "develop_export_v11_request_size");
        Check(
            sizeof(NativeLocalDodgeBurnPointV1) ==
                NativeDevelopExporter.LocalDodgeBurnPointV1Size,
            "local_dodge_burn_point_v1_size");
        Check(
            sizeof(NativeLocalDodgeBurnStrokeV1) ==
                NativeDevelopExporter.LocalDodgeBurnStrokeV1Size,
            "local_dodge_burn_stroke_v1_size");
        Check(
            sizeof(NativeLocalDodgeBurnAdjustmentV1) ==
                NativeDevelopExporter.LocalDodgeBurnAdjustmentV1Size,
            "local_dodge_burn_adjustment_v1_size");
        Check(
            sizeof(NativeDevelopExportRequestV12) == NativeDevelopExporter.RequestV12Size,
            "develop_export_v12_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV13) == NativeDevelopExporter.RequestV13Size,
            "develop_export_v13_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV14) == NativeDevelopExporter.RequestV14Size,
            "develop_export_v14_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV15) == NativeDevelopExporter.RequestV15Size,
            "develop_export_v15_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV16) == NativeDevelopExporter.RequestV16Size,
            "develop_export_v16_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV17) == NativeDevelopExporter.RequestV17Size,
            "develop_export_v17_request_size");
        Check(
            sizeof(NativeDefectRegionEditV1) ==
                NativeDevelopExporter.DefectRegionEditV1Size,
            "defect_region_edit_v1_size");
        Check(
            sizeof(NativeDevelopExportRequestV18) == NativeDevelopExporter.RequestV18Size,
            "develop_export_v18_request_size");
        Check(
            sizeof(NativeDevelopExportRequestV19) == NativeDevelopExporter.RequestV19Size,
            "develop_export_v19_request_size");
        Check(
            sizeof(NativeDefectClonePointV1) == NativeDevelopExporter.DefectClonePointV1Size,
            "defect_clone_point_v1_size");
        Check(
            sizeof(NativeDefectCloneStrokeV1) == NativeDevelopExporter.DefectCloneStrokeV1Size,
            "defect_clone_stroke_v1_size");
        Check(
            sizeof(NativeDefectCloneEditV1) == NativeDevelopExporter.DefectCloneEditV1Size,
            "defect_clone_edit_v1_size");
        Check(
            sizeof(NativeDefectRecipeEditRefV1) ==
                NativeDevelopExporter.DefectRecipeEditRefV1Size,
            "defect_recipe_edit_ref_v1_size");
        Check(
            sizeof(NativeDevelopExportRequestV20) == NativeDevelopExporter.RequestV20Size,
            "develop_export_v20_request_size");
        Check(
            sizeof(NativeDefectBrushPointV1) == NativeDevelopExporter.DefectBrushPointV1Size,
            "defect_brush_point_v1_size");
        Check(
            sizeof(NativeDefectBrushStrokeV1) == NativeDevelopExporter.DefectBrushStrokeV1Size,
            "defect_brush_stroke_v1_size");
        Check(
            sizeof(NativeDefectBrushEditV1) == NativeDevelopExporter.DefectBrushEditV1Size,
            "defect_brush_edit_v1_size");
        Check(
            sizeof(NativeDevelopExportRequestV21) == NativeDevelopExporter.RequestV21Size,
            "develop_export_v21_request_size");
        Check(
            sizeof(NativeDefectInfraredEditV1) ==
                NativeDevelopExporter.DefectInfraredEditV1Size,
            "defect_infrared_edit_v1_size");
        Check(
            sizeof(NativeDevelopExportRequestV24) == NativeDevelopExporter.RequestV24Size,
            "develop_export_v24_request_size");
        Check(
            sizeof(NativeDefectInfraredItemV1) ==
                NativeDevelopExporter.DefectInfraredItemV1Size,
            "defect_infrared_item_v1_size");
        Check(
            sizeof(NativeDevelopExportRequestV25) == NativeDevelopExporter.RequestV25Size,
            "develop_export_v25_request_size");
        Check(
            sizeof(NativeDevelopExportResultV2) == NativeDevelopExporter.ResultV2Size,
            "develop_export_v2_result_size");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV1>(
                nameof(NativeDevelopExportRequestV1.FilmEmulationIntensity)).ToInt32() == 80,
            "develop_export_intensity_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportResultV1>(
                nameof(NativeDevelopExportResultV1.FailureName)).ToInt32() == 12,
            "develop_export_failure_name_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportResultV1>(
                nameof(NativeDevelopExportResultV1.SourceFileBytes)).ToInt32() == 104,
            "develop_export_source_bytes_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV2>(
                nameof(NativeDevelopExportRequestV2.BaseEstimationMode)).ToInt32() == 32,
            "develop_export_v2_base_mode_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV3>(
                nameof(NativeDevelopExportRequestV3.Density)).ToInt32() == 92,
            "develop_export_v3_basic_tone_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV4>(
                nameof(NativeDevelopExportRequestV4.FilmStockDminId)).ToInt32() == 112,
            "develop_export_v4_film_stock_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV5>(
                nameof(NativeDevelopExportRequestV5.PointCurveRgb)).ToInt32() == 128,
            "develop_export_v5_point_curve_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV6>(
                nameof(NativeDevelopExportRequestV6.ColorMixerHue)).ToInt32() == 4256,
            "develop_export_v6_color_mixer_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV7>(
                nameof(NativeDevelopExportRequestV7.ColorGradingShadowsHue)).ToInt32() == 4352,
            "develop_export_v7_color_grading_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV8>(
                nameof(NativeDevelopExportRequestV8.DefectRemovalStrength)).ToInt32() == 4400,
            "develop_export_v8_grain_mend_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV9>(
                nameof(NativeDevelopExportRequestV9.NoiseReductionStrength)).ToInt32() == 4408,
            "develop_export_v9_noise_reduction_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV9>(
                nameof(NativeDevelopExportRequestV9.NoiseReductionFilmProfile)).ToInt32() == 4432,
            "develop_export_v9_noise_reduction_profile_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV10>(
                nameof(NativeDevelopExportRequestV10.TextureGrain)).ToInt32() == 4440,
            "develop_export_v10_texture_offset");
          Check(
              Marshal.OffsetOf<NativeDevelopExportRequestV10>(
                  nameof(NativeDevelopExportRequestV10.TextureVignette)).ToInt32() == 4456,
              "develop_export_v10_vignette_offset");
          Check(
              Marshal.OffsetOf<NativeDevelopExportRequestV11>(
                  nameof(NativeDevelopExportRequestV11.BwToningMode)).ToInt32() == 4464,
              "develop_export_v11_bw_toning_offset");
          Check(
              Marshal.OffsetOf<NativeDevelopExportRequestV11>(
                  nameof(NativeDevelopExportRequestV11.StraightenAngle)).ToInt32() == 4544,
              "develop_export_v11_straighten_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV12>(
                nameof(NativeDevelopExportRequestV12.LocalAdjustments)).ToInt32() == 4552,
            "develop_export_v12_adjustment_pointer_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV12>(
                nameof(NativeDevelopExportRequestV12.LocalPoints)).ToInt32() == 4584,
            "develop_export_v12_point_pointer_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV13>(
                nameof(NativeDevelopExportRequestV13.Warmth)).ToInt32() == 4600,
            "develop_export_v13_warmth_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV13>(
                nameof(NativeDevelopExportRequestV13.BluePrimary)).ToInt32() == 4628,
            "develop_export_v13_blue_primary_offset");
        Check(
            Marshal.OffsetOf<NativeDefectRegionEditV1>(
                nameof(NativeDefectRegionEditV1.Strength)).ToInt32() == 32,
            "defect_region_edit_strength_offset");
        Check(
            Marshal.OffsetOf<NativeDefectRegionEditV1>(
                nameof(NativeDefectRegionEditV1.PreferredAngleDegrees)).ToInt32() == 48,
            "defect_region_edit_angle_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV18>(
                nameof(NativeDevelopExportRequestV18.DefectRegionEdits)).ToInt32() == 4664,
            "develop_export_v18_defect_edits_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV18>(
                nameof(NativeDevelopExportRequestV18.DefectMaskBytes)).ToInt32() == 4680,
            "develop_export_v18_defect_mask_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV19>(
                nameof(NativeDevelopExportRequestV19.DefectSourceFileBytes)).ToInt32() == 4696,
            "develop_export_v19_defect_source_size_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV19>(
                nameof(NativeDevelopExportRequestV19.DefectSourceSha256)).ToInt32() == 4704,
            "develop_export_v19_defect_source_sha_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV20>(
                nameof(NativeDevelopExportRequestV20.DefectCloneEdits)).ToInt32() == 4720,
            "develop_export_v20_clone_edit_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV20>(
                nameof(NativeDevelopExportRequestV20.DefectCloneStrokes)).ToInt32() == 4736,
            "develop_export_v20_clone_stroke_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV20>(
                nameof(NativeDevelopExportRequestV20.DefectClonePoints)).ToInt32() == 4752,
            "develop_export_v20_clone_point_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV20>(
                nameof(NativeDevelopExportRequestV20.DefectEditOrder)).ToInt32() == 4768,
            "develop_export_v20_edit_order_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV21>(
                nameof(NativeDevelopExportRequestV21.DefectBrushEdits)).ToInt32() == 4784,
            "develop_export_v21_brush_edit_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV21>(
                nameof(NativeDevelopExportRequestV21.DefectBrushStrokes)).ToInt32() == 4800,
            "develop_export_v21_brush_stroke_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV21>(
                nameof(NativeDevelopExportRequestV21.DefectBrushPoints)).ToInt32() == 4816,
            "develop_export_v21_brush_point_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV24>(
                nameof(NativeDevelopExportRequestV24.DefectInfraredEdits)).ToInt32() == 4832,
            "develop_export_v24_infrared_edit_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV24>(
                nameof(NativeDevelopExportRequestV24.DefectInfraredAttenuationBytes)).ToInt32() ==
                4848,
            "develop_export_v24_attenuation_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV25>(
                nameof(NativeDevelopExportRequestV25.DefectInfraredItems)).ToInt32() == 4864,
            "develop_export_v25_infrared_item_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportResultV2>(
                nameof(NativeDevelopExportResultV2.AppliedDminRed)).ToInt32() == 136,
            "develop_export_v2_applied_dmin_offset");
    }

    // The run state is the only place where managed memory outlives the marshalling of a
    // call, so it gets its own checks: a latch set before the call has to stop the run,
    // and the handle has to keep answering after it is disposed instead of tearing.
    private static void VerifyRunStateContract()
    {
        string temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-run-state-{Guid.NewGuid():N}");
        string absentSource = Path.Combine(temporaryRoot, "absent.tif");
        string destination = Path.Combine(temporaryRoot, "out.png");

        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();
            using var cancelled = new DevelopRun(cancellation.Token);
            Check(cancelled.IsCancelRequested, "run_state_token_latches_before_the_call");

            DevelopExportResult result = NativeDevelopExporter.Run(
                new DevelopExportRequest
                {
                    SourcePath = absentSource,
                    DestinationPath = destination,
                },
                cancelled);
            Check(!result.Succeeded, "cancelled_run_does_not_succeed");
            Check(result.Cancelled, "cancelled_run_is_reported_as_cancelled");
            Check(result.FailureName == "cancelled", "cancelled_run_failure_name");
            Check(!File.Exists(destination), "cancelled_run_writes_nothing");
        }

        // An untouched handle must not change the answer a plain call would have given.
        using (var untouched = new DevelopRun())
        {
            DevelopExportResult result = NativeDevelopExporter.Run(
                new DevelopExportRequest
                {
                    SourcePath = absentSource,
                    DestinationPath = destination,
                },
                untouched);
            Check(!result.Cancelled, "untouched_run_state_does_not_cancel");
            Check(
                result.FailedStage == DevelopExportStage.ObserveSourceBefore,
                "untouched_run_state_keeps_the_ordinary_failure");
        }

        var disposed = new DevelopRun();
        disposed.Dispose();
        Check(disposed.ProgressPermille == 0, "disposed_run_reads_zero_progress");
        Check(disposed.Stage == DevelopExportStage.None, "disposed_run_reads_no_stage");
        Check(!disposed.IsCancelRequested, "disposed_run_reads_no_cancellation");
        disposed.Cancel();
        disposed.Dispose();
        Check(true, "disposed_run_tolerates_cancel_and_second_dispose");
    }

    // Auto adjust is the one call that hands a whole bitmap across the boundary, so the
    // checks here are about the boundary itself: that a real buffer produces values the
    // engine would accept, and that a malformed one is refused rather than read past.
    private static void VerifyAutoAdjustContract()
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
        Check(
            settings.Exposure >= -3.0 && settings.Exposure <= 3.0,
            "auto_adjust_exposure_inside_engine_range");
        Check(settings.Highlights <= 0.0, "auto_adjust_highlights_recover_only");
        Check(settings.Shadows >= 0.0, "auto_adjust_shadows_lift_only");
        Check(settings.Vibrance >= 0.0, "auto_adjust_vibrance_increases_only");
        Check(
            settings.Warmth >= -0.6 && settings.Warmth <= 0.6 &&
                settings.Tint >= -0.6 && settings.Tint <= 0.6,
            "auto_adjust_white_balance_inside_clamp");

        // Assigning twice must not drift, because the shell assigns rather than accumulates.
        AutoAdjustSettings again = NativeAutoAdjust.Compute(pixels, width, height);
        Check(
            again.Exposure == settings.Exposure && again.Contrast == settings.Contrast &&
                again.Warmth == settings.Warmth && again.Tint == settings.Tint,
            "auto_adjust_is_deterministic_across_calls");

        CheckThrows<ArgumentException>(
            () => NativeAutoAdjust.Compute(new byte[16], width, height),
            "auto_adjust_refuses_a_buffer_smaller_than_its_dimensions");
        CheckThrows<ArgumentOutOfRangeException>(
            () => NativeAutoAdjust.Compute(pixels, 0, height),
            "auto_adjust_refuses_zero_width");
    }

    // Soft proof crosses the boundary as raw profile bytes going one way and ten numbers
    // coming back, so the checks are about that translation - not about the ICC parser,
    // which native.soft_proof covers against the profiles installed on the machine.
    private static void VerifySoftProofContract()
    {
        // A display profile has to come back as an identity proof. If it did not, choosing
        // sRGB as the proof destination would visibly tint the frame.
        const string installed =
            @"C:\Windows\System32\spool\drivers\color\sRGB Color Space Profile.icm";
        if (File.Exists(installed))
        {
            byte[] profile = File.ReadAllBytes(installed);
            SoftProofMedia media = NativeSoftProof.ReadMedia(profile);
            Check(media.IsRgbOutputProfile, "soft_proof_accepts_an_rgb_display_profile");
            Check(media.HasWhite, "soft_proof_reads_the_white_point");
            Check(
                Math.Abs(media.PaperWhite.Red - 1.0) < 0.002 &&
                    Math.Abs(media.PaperWhite.Green - 1.0) < 0.002 &&
                    Math.Abs(media.PaperWhite.Blue - 1.0) < 0.002,
                "soft_proof_display_profile_is_an_identity_paper");
        }

        // Anything that is not a renderable RGB profile has to be refused here, at the
        // point of choosing, rather than silently producing nothing at render time.
        SoftProofMedia empty = NativeSoftProof.ReadMedia(ReadOnlySpan<byte>.Empty);
        Check(
            !empty.IsRgbOutputProfile && !empty.HasWhite && !empty.HasBlack,
            "soft_proof_refuses_an_absent_profile");
        Check(
            empty.PaperWhite == SoftProofRgb.White && empty.BlackInk == SoftProofRgb.Black,
            "soft_proof_falls_back_to_a_neutral_paper");

        SoftProofMedia malformed = NativeSoftProof.ReadMedia(new byte[64]);
        Check(
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
        Check(
            settings.IsEnabled &&
                settings.Simulation == SoftProofSimulation.PaperAndBlackInk &&
                settings.PaperWhite.Blue == 0.95 && settings.BlackInk.Blue == 0.05,
            "soft_proof_settings_carry_the_resolved_media");
        Check(
            !SoftProofSettings.Disabled.IsEnabled &&
                SoftProofSettings.Disabled.PaperWhite == SoftProofRgb.White,
            "soft_proof_disabled_is_a_neutral_identity");
    }

    private static void VerifyToneLimits()
    {
        ToneLimits limits = ToneLimits.Read();

        // 값 자체를 여기에 다시 적으면 이 테스트가 바로 그 중복이 됩니다. 대신 이 값들이
        // 컨트롤을 실제로 묶을 수 있는 모양인지, 그리고 엔진이 거부하는 값을 clamp 가
        // 통과시키지 않는지를 봅니다.
        Check(limits.MaximumExposureStops > 0, "tone_limits_exposure_positive");
        Check(limits.MaximumToneControl > 0, "tone_limits_control_positive");
        Check(
            limits.MinimumFilmEmulationIntensity < limits.MaximumFilmEmulationIntensity,
            "tone_limits_intensity_range");

        Check(
            limits.ClampExposure(limits.MaximumExposureStops * 10) ==
                limits.MaximumExposureStops,
            "tone_limits_clamps_high_exposure");
        Check(
            limits.ClampExposure(-limits.MaximumExposureStops * 10) ==
                -limits.MaximumExposureStops,
            "tone_limits_clamps_low_exposure");
        Check(limits.ClampExposure(double.NaN) == 0.0, "tone_limits_clamps_nan");
        Check(
            limits.ClampToneControl(limits.MaximumToneControl * 10) ==
                limits.MaximumToneControl,
            "tone_limits_clamps_control");

        // clamp 를 지난 값은 엔진이 받아야 합니다. 받지 않으면 두 쪽이 어긋난 것입니다.
        string absentSource = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-tone-limit-{Guid.NewGuid():N}.tif");
        DevelopExportResult atLimit = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = Path.Combine(Path.GetTempPath(), "negaflow-tone-limit.png"),
            ExposureStops = (float)limits.ClampExposure(double.MaxValue),
            Contrast = (float)limits.ClampToneControl(double.MaxValue),
            Density = (float)limits.ClampToneControl(double.MinValue),
            Highlight = (float)limits.ClampToneControl(double.MaxValue),
            Shadow = (float)limits.ClampToneControl(double.MinValue),
            Whites = (float)limits.ClampToneControl(double.MaxValue),
            Blacks = (float)limits.ClampToneControl(double.MinValue),
            Highlights = (float)limits.ClampToneControl(double.MinValue),
        });
        Check(
            atLimit.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "tone_limits_clamped_values_pass_validation");

        // 반대로 범위를 넘으면 엔진이 거부해야 합니다. 그래야 위 확인이 의미를 가집니다.
        DevelopExportResult overLimit = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = Path.Combine(Path.GetTempPath(), "negaflow-tone-limit.png"),
            ExposureStops = limits.MaximumExposureStops * 2,
        });
        Check(
            overLimit.FailedStage == DevelopExportStage.RequestValidation,
            "tone_limits_over_limit_is_rejected");
        Check(
            overLimit.FailureName == "invalid_tone_adjustment_parameter",
            "tone_limits_over_limit_reason");
    }

    private static void VerifyNegativeLimits()
    {
        NegativeLimits limits = NegativeLimits.Read();

        Check(limits.MinimumManualDmin > 0, "negative_limits_minimum_positive");
        Check(
            limits.MinimumManualDmin < limits.MaximumManualDmin,
            "negative_limits_range");
        Check(
            limits.ClampChannel(limits.MaximumManualDmin * 10) == limits.MaximumManualDmin,
            "negative_limits_clamps_high");
        Check(limits.ClampChannel(-1.0) == limits.MinimumManualDmin, "negative_limits_clamps_low");
        Check(limits.ClampChannel(double.NaN) == limits.MinimumManualDmin, "negative_limits_nan");

        // 톤 한계와 달리 엔진은 범위를 벗어난 dmin 을 **거부하지 않고 조용히 clamp** 합니다.
        // 그래서 "범위를 넘으면 거부된다" 는 대칭 확인을 여기서 할 수 없습니다. 대신 clamp 를
        // 지난 값이 develop 단계까지 도달하는지를 봅니다.
        string absentSource = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-base-limit-{Guid.NewGuid():N}.tif");
        DevelopExportResult atLimit = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = Path.Combine(Path.GetTempPath(), "negaflow-base-limit.png"),
            DminRed = (float)limits.ClampChannel(double.MaxValue),
            DminGreen = (float)limits.ClampChannel(double.MinValue),
            DminBlue = (float)limits.ClampChannel(0.25),
        });
        Check(
            atLimit.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "negative_limits_clamped_values_pass_validation");
    }

    private static void VerifyDevelopExportContract()
    {
        string temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-develop-export-{Guid.NewGuid():N}");
        string absentSource = Path.Combine(temporaryRoot, "absent.tif");
        string destination = Path.Combine(temporaryRoot, "out.png");

        // A missing source must be reported as an observation failure, not as a
        // malformed request, so the shell can tell a user error from a bug.
        DevelopExportResult missing = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
        });
        Check(!missing.Succeeded, "develop_export_missing_source_fails");
        Check(
            missing.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_missing_source_stage");
        Check(missing.FailureName.Length > 0, "develop_export_failure_name_present");
        Check(missing.FailureName != "ok", "develop_export_failure_name_not_ok");
        Check(!File.Exists(destination), "develop_export_failure_writes_nothing");

        DevelopExportResult autoMissing = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            BaseEstimationMode = DevelopBaseEstimationMode.Auto,
        });
        Check(
            autoMissing.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_auto_reaches_source_observation");

        DevelopExportResult digital = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            FilmLookSourceKind = DevelopSourceKind.RenderedDigital,
            FilmEmulation = FilmEmulationProfile.Vision3_500T,
        });
        Check(!digital.Succeeded, "develop_export_digital_source_fails");
        Check(
            digital.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_vision3_digital_source_stage");
        Check(
            digital.FailureName != "ok",
            "develop_export_digital_source_name");

        DevelopExportResult local = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            LocalDodgeBurn =
            [
                new DevelopLocalDodgeBurnAdjustment
                {
                    Mode = DevelopLocalDodgeBurnMode.Dodge,
                    Amount = 0.6,
                    Mask = new DevelopLocalDodgeBurnMask
                    {
                        Kind = DevelopLocalDodgeBurnMaskKind.Brush,
                        Strokes =
                        [
                            new DevelopLocalDodgeBurnStroke
                            {
                                Points =
                                [
                                    new DevelopLocalDodgeBurnPoint(0.4, 0.5),
                                    new DevelopLocalDodgeBurnPoint(0.6, 0.5),
                                ],
                            },
                        ],
                    },
                },
            ],
        });
        Check(
            local.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_local_mask_reaches_source_observation");

        DevelopExportResult defects = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectRegions =
            [
                new DevelopDefectRegionEdit
                {
                    RoiX = 12,
                    RoiY = 20,
                    Width = 8,
                    Height = 8,
                    Mask = new byte[64],
                    Strength = 0.75,
                    PreferredAngleDegrees = 90.0,
                },
            ],
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        });
        Check(
            defects.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_defect_region_reaches_source_observation");

        DevelopExportRequest infraredRequest = new()
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectInfrared =
            [
                new DevelopDefectInfraredEdit
                {
                    Strength = 0.75,
                    Clusters =
                    [
                        new DevelopDefectInfraredCluster
                        {
                            RoiX = 12,
                            RoiY = 20,
                            Width = 8,
                            Height = 8,
                            CoreMask = new byte[64],
                            AttenuationR16 = new byte[128],
                        },
                    ],
                },
            ],
            DefectEditOrder =
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
            ],
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        };
        DevelopExportResult infrared = NativeDevelopExporter.Run(infraredRequest);
        Check(
            infrared.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_infrared_reaches_source_observation");
        Span<byte> infraredPreviewPixels = stackalloc byte[4];
        DevelopExportResult infraredPreview = NativeDevelopExporter.Preview(
            infraredRequest, 1, 1, infraredPreviewPixels);
        Check(
            infraredPreview.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_preview_infrared_reaches_source_observation");

        DevelopDefectInfraredCluster maximumCluster = new()
        {
            Width = 3,
            Height = 3,
            CoreMask = new byte[9],
        };
        DevelopDefectInfraredCluster[] maximumClusters = Enumerable.Repeat(
            maximumCluster,
            4_096).ToArray();
        DevelopDefectCloneEdit maximumClone = new() { IsEnabled = false };
        DevelopDefectCloneEdit[] maximumClones = Enumerable.Repeat(
            maximumClone,
            4_096).ToArray();
        DevelopDefectRecipeEditRef[] maximumOrder =
        [
            new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
            .. Enumerable.Range(0, 4_096).Select(index =>
                new DevelopDefectRecipeEditRef(
                    DevelopDefectEditKind.Clone,
                    checked((uint)index))),
        ];
        DevelopExportRequest maximumInfraredRequest = new()
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectInfrared =
            [
                new DevelopDefectInfraredEdit { Clusters = maximumClusters },
            ],
            DefectClones = maximumClones,
            DefectEditOrder = maximumOrder,
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        };
        Check(
            NativeDevelopExporter.Run(maximumInfraredRequest).FailedStage ==
                DevelopExportStage.ObserveSourceBefore,
            "develop_export_accepts_4096_flat_regions_and_8192_expanded_order");
        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectInfrared =
                [
                    new DevelopDefectInfraredEdit
                    {
                        Clusters = [.. maximumClusters, maximumCluster],
                    },
                ],
                DefectClones = [],
                DefectEditOrder =
                [
                    new DevelopDefectRecipeEditRef(
                        DevelopDefectEditKind.Infrared,
                        0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_rejects_4097_flat_regions_before_marshalling");
        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectInfrared =
                [
                    new DevelopDefectInfraredEdit { Clusters = maximumClusters },
                ],
                DefectClones = maximumClones,
                DefectBrushes = [new DevelopDefectBrushEdit { IsEnabled = false }],
                DefectEditOrder =
                [
                    .. maximumOrder,
                    new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Brush, 0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_rejects_8193_expanded_order_before_marshalling");

        DevelopExportResult clone = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectClones =
            [
                new DevelopDefectCloneEdit
                {
                    Strength = 0.75,
                    Strokes =
                    [
                        new DevelopDefectCloneStroke
                        {
                            Points = [new DevelopDefectClonePoint(0.5, 0.5)],
                            OffsetX = 0.1,
                            DiameterPixels = 9.0,
                            Hardness = 0.8,
                        },
                    ],
                },
            ],
            DefectEditOrder =
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Clone, 0),
            ],
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        });
        Check(
            clone.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_clone_reaches_source_observation");

        DevelopExportResult brush = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectBrushes =
            [
                new DevelopDefectBrushEdit
                {
                    Strength = 0.75,
                    Strokes =
                    [
                        new DevelopDefectBrushStroke
                        {
                            Points =
                            [
                                new DevelopDefectBrushPoint(0.4, 0.5),
                                new DevelopDefectBrushPoint(0.6, 0.5),
                            ],
                            Thickness = 0.02,
                        },
                    ],
                },
            ],
            DefectEditOrder =
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Brush, 0),
            ],
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        });
        Check(
            brush.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_brush_reaches_source_observation");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectClones = [new DevelopDefectCloneEdit()],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_clone_requires_order");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectBrushes =
                [
                    new DevelopDefectBrushEdit
                    {
                        Strokes =
                        [
                            new DevelopDefectBrushStroke
                            {
                                Points = [new DevelopDefectBrushPoint(2.0, 0.5)],
                                Thickness = 0.02,
                            },
                        ],
                    },
                ],
                DefectEditOrder =
                [
                    new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Brush, 0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_invalid_brush_geometry_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectRegions =
                [
                    new DevelopDefectRegionEdit
                    {
                        Width = 8,
                        Height = 8,
                        Mask = new byte[64],
                    },
                ],
            }),
            "develop_export_defect_region_requires_source_identity");

        DevelopExportResult colorModel = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            Warmth = 0.25F,
            Tint = -0.2F,
            ColorDepth = 0.3F,
            Vibrance = 0.4F,
            Saturation = -0.1F,
            RedPrimary = 0.1F,
            GreenPrimary = -0.1F,
            BluePrimary = 0.2F,
        });
        Check(
            colorModel.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_color_model_reaches_source_observation");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                LocalDodgeBurn =
                [
                    new DevelopLocalDodgeBurnAdjustment
                    {
                        Amount = 0.5,
                        Mask = new DevelopLocalDodgeBurnMask
                        {
                            Kind = DevelopLocalDodgeBurnMaskKind.Polygon,
                            Points = [new DevelopLocalDodgeBurnPoint(double.NaN, 0.5)],
                        },
                    },
                ],
            }),
            "develop_export_invalid_local_mask_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectRegions =
                [
                    new DevelopDefectRegionEdit
                    {
                        Width = 8,
                        Height = 8,
                        Mask = new byte[63],
                    },
                ],
            }),
            "develop_export_short_defect_mask_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectInfrared =
                [
                    new DevelopDefectInfraredEdit
                    {
                        Clusters =
                        [
                            new DevelopDefectInfraredCluster
                            {
                                Width = 8,
                                Height = 8,
                                CoreMask = new byte[64],
                                AttenuationR16 = new byte[127],
                            },
                        ],
                    },
                ],
                DefectEditOrder =
                [
                    new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_short_infrared_attenuation_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectInfrared =
                [
                    new DevelopDefectInfraredEdit
                    {
                        Clusters =
                        [
                            new DevelopDefectInfraredCluster
                            {
                                Width = 8,
                                Height = 8,
                                CoreMask = new byte[64],
                                AttenuationStrideBytes = 15,
                                AttenuationR16 = new byte[128],
                            },
                        ],
                    },
                ],
                DefectEditOrder =
                [
                    new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_short_infrared_stride_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                FilmEmulation = (FilmEmulationProfile)99,
            }),
            "develop_export_undefined_enum_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                BaseEstimationMode = (DevelopBaseEstimationMode)99,
            }),
            "develop_export_undefined_base_mode_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                FilmPolarity = (FilmPolarity)99,
            }),
            "develop_export_undefined_film_polarity_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                PointCurves = new DevelopPointCurves
                {
                    Rgb =
                    [
                        new DevelopPointCurvePoint(0.5, 0.5),
                        new DevelopPointCurvePoint(0.5, 0.6),
                    ],
                },
            }),
            "develop_export_duplicate_point_curve_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                ColorMixer = new DevelopColorMixer
                {
                    Hue = [0.0f, 0.0f],
                },
            }),
            "develop_export_short_color_mixer_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                ColorGrading = new DevelopColorGrading
                {
                    Midtones = new DevelopColorGradeRegion(361.0f, 0.0f, 0.0f),
                },
            }),
            "develop_export_invalid_color_grading_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectRemovalStrength = double.NaN,
            }),
            "develop_export_invalid_grain_mend_strength_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                NoiseReductionDetail = float.NaN,
            }),
            "develop_export_invalid_noise_reduction_control_rejected");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                Vignette = 1.01F,
            }),
            "develop_export_invalid_texture_control_rejected");

        CheckThrows<ArgumentNullException>(
            () => NativeDevelopExporter.Run(null!),
            "develop_export_null_request_rejected");
    }

    private static void VerifyPathPolicy()
    {
        CheckThrows<ArgumentException>(
            () => NativeLibraryLoader.EnsureLoaded(NativeMethods.FileName),
            "relative_path_rejected");

        string wrongName = Path.Combine(Path.GetTempPath(), "not-negaflow-native.dll");
        CheckThrows<ArgumentException>(
            () => NativeLibraryLoader.EnsureLoaded(wrongName),
            "wrong_file_name_rejected");

        string missingLibrary = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-missing-{Guid.NewGuid():N}",
            NativeMethods.FileName);
        ++assertionCount;
        try
        {
            NativeEngineBootstrap.LoadAndQuery(missingLibrary);
            Failures.Add("missing_library_classified");
        }
        catch (NativeBootstrapException exception)
            when (exception.Failure == NativeBootstrapFailure.LoadFailed)
        {
        }
    }

    private static void VerifyBuildInfo(NativeBuildInfo buildInfo)
    {
        // Compatibility, not an exact pin. A minor ahead of the minimum is a valid
        // engine; pinning the exact number turned every added export into a test edit.
        // The exact version still reaches the report below.
        Check(
            buildInfo.AbiVersion.Major == NativeAbiReader.SupportedMajor &&
                buildInfo.AbiVersion.Minor >= NativeAbiReader.MinimumMinor,
            "abi_version");
        Check(buildInfo.Compiler == NativeCompiler.Msvc, "compiler");
        Check(buildInfo.CompilerVersion != 0, "compiler_version");
        Check(
            buildInfo.SourceCommitSha1.Length == 40 &&
                buildInfo.SourceCommitSha1.Any(character => character != '0'),
            "source_commit");

        NativeArchitecture expectedArchitecture = RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.X64 => NativeArchitecture.X64,
            Architecture.Arm64 => NativeArchitecture.Arm64,
            _ => NativeArchitecture.Unknown,
        };
        Check(
            expectedArchitecture != NativeArchitecture.Unknown &&
                buildInfo.Architecture == expectedArchitecture,
            "architecture");

        bool avxUsable = buildInfo.CpuFeatures.HasFlag(NativeCpuFeatures.AvxUsable);
        Check(
            !buildInfo.CpuFeatures.HasFlag(NativeCpuFeatures.Avx2) || avxUsable,
            "avx2_requires_avx_state");
        Check(
            !buildInfo.CpuFeatures.HasFlag(NativeCpuFeatures.Fma) || avxUsable,
            "fma_requires_avx_state");
    }

    private static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }

    private static void CheckThrows<TException>(Action action, string name)
        where TException : Exception
    {
        ++assertionCount;
        try
        {
            action();
            Failures.Add(name);
        }
        catch (TException)
        {
        }
    }
}
