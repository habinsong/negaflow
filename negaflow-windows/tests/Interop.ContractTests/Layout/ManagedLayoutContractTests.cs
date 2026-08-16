using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class ManagedLayoutContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        context.Check((int)DevelopExportStage.DefectBrush == 21, "defect_brush_stage_value");
        context.Check(sizeof(NativeBuildInfoV1) == NativeAbiReader.BuildInfoV1Size, "build_info_size");
        context.Check(
            Marshal.OffsetOf<NativeBuildInfoV1>(nameof(NativeBuildInfoV1.SourceCommitSha1)).ToInt32() ==
                NativeAbiReader.SourceCommitSha1Offset,
            "source_commit_offset");

        // The native side static_asserts the same three numbers. Both halves have to
        // be checked, because a layout drift binds cleanly and then reads garbage.
        context.Check(
            sizeof(NativeDevelopExportRequestV1) == NativeDevelopExporter.RequestV1Size,
            "develop_export_request_size");
        context.Check(
            sizeof(NativeDevelopExportResultV1) == NativeDevelopExporter.ResultV1Size,
            "develop_export_result_size");
        context.Check(
            sizeof(NativeGrainMendDetectParametersV3) ==
                NativeDevelopExporter.GrainMendDetectParametersV3Size,
            "grain_mend_detect_v4_parameters_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV2) == NativeDevelopExporter.RequestV2Size,
            "develop_export_v2_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV3) == NativeDevelopExporter.RequestV3Size,
            "develop_export_v3_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV4) == NativeDevelopExporter.RequestV4Size,
            "develop_export_v4_request_size");
        context.Check(
            sizeof(NativePointCurveV1) == NativeDevelopExporter.PointCurveV1Size,
            "point_curve_v1_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV5) == NativeDevelopExporter.RequestV5Size,
            "develop_export_v5_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV6) == NativeDevelopExporter.RequestV6Size,
            "develop_export_v6_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV7) == NativeDevelopExporter.RequestV7Size,
            "develop_export_v7_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV8) == NativeDevelopExporter.RequestV8Size,
            "develop_export_v8_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV9) == NativeDevelopExporter.RequestV9Size,
            "develop_export_v9_request_size");
          context.Check(
              sizeof(NativeDevelopExportRequestV10) == NativeDevelopExporter.RequestV10Size,
              "develop_export_v10_request_size");
          context.Check(
              sizeof(NativeDevelopExportRequestV11) == NativeDevelopExporter.RequestV11Size,
              "develop_export_v11_request_size");
        context.Check(
            sizeof(NativeLocalDodgeBurnPointV1) ==
                NativeDevelopExporter.LocalDodgeBurnPointV1Size,
            "local_dodge_burn_point_v1_size");
        context.Check(
            sizeof(NativeLocalDodgeBurnStrokeV1) ==
                NativeDevelopExporter.LocalDodgeBurnStrokeV1Size,
            "local_dodge_burn_stroke_v1_size");
        context.Check(
            sizeof(NativeLocalDodgeBurnAdjustmentV1) ==
                NativeDevelopExporter.LocalDodgeBurnAdjustmentV1Size,
            "local_dodge_burn_adjustment_v1_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV12) == NativeDevelopExporter.RequestV12Size,
            "develop_export_v12_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV13) == NativeDevelopExporter.RequestV13Size,
            "develop_export_v13_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV14) == NativeDevelopExporter.RequestV14Size,
            "develop_export_v14_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV15) == NativeDevelopExporter.RequestV15Size,
            "develop_export_v15_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV16) == NativeDevelopExporter.RequestV16Size,
            "develop_export_v16_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV17) == NativeDevelopExporter.RequestV17Size,
            "develop_export_v17_request_size");
        context.Check(
            sizeof(NativeDefectRegionEditV1) ==
                NativeDevelopExporter.DefectRegionEditV1Size,
            "defect_region_edit_v1_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV18) == NativeDevelopExporter.RequestV18Size,
            "develop_export_v18_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV19) == NativeDevelopExporter.RequestV19Size,
            "develop_export_v19_request_size");
        context.Check(
            sizeof(NativeDefectClonePointV1) == NativeDevelopExporter.DefectClonePointV1Size,
            "defect_clone_point_v1_size");
        context.Check(
            sizeof(NativeDefectCloneStrokeV1) == NativeDevelopExporter.DefectCloneStrokeV1Size,
            "defect_clone_stroke_v1_size");
        context.Check(
            sizeof(NativeDefectCloneEditV1) == NativeDevelopExporter.DefectCloneEditV1Size,
            "defect_clone_edit_v1_size");
        context.Check(
            sizeof(NativeDefectRecipeEditRefV1) ==
                NativeDevelopExporter.DefectRecipeEditRefV1Size,
            "defect_recipe_edit_ref_v1_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV20) == NativeDevelopExporter.RequestV20Size,
            "develop_export_v20_request_size");
        context.Check(
            sizeof(NativeDefectBrushPointV1) == NativeDevelopExporter.DefectBrushPointV1Size,
            "defect_brush_point_v1_size");
        context.Check(
            sizeof(NativeDefectBrushStrokeV1) == NativeDevelopExporter.DefectBrushStrokeV1Size,
            "defect_brush_stroke_v1_size");
        context.Check(
            sizeof(NativeDefectBrushEditV1) == NativeDevelopExporter.DefectBrushEditV1Size,
            "defect_brush_edit_v1_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV21) == NativeDevelopExporter.RequestV21Size,
            "develop_export_v21_request_size");
        context.Check(
            sizeof(NativeDefectInfraredEditV1) ==
                NativeDevelopExporter.DefectInfraredEditV1Size,
            "defect_infrared_edit_v1_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV24) == NativeDevelopExporter.RequestV24Size,
            "develop_export_v24_request_size");
        context.Check(
            sizeof(NativeDefectInfraredItemV1) ==
                NativeDevelopExporter.DefectInfraredItemV1Size,
            "defect_infrared_item_v1_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV25) == NativeDevelopExporter.RequestV25Size,
            "develop_export_v25_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV26) == NativeDevelopExporter.RequestV26Size,
            "develop_export_v26_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV27) == NativeDevelopExporter.RequestV27Size,
            "develop_export_v27_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV28) == NativeDevelopExporter.RequestV28Size,
            "develop_export_v28_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV29) == NativeDevelopExporter.RequestV29Size,
            "develop_export_v29_request_size");
        context.Check(
            sizeof(NativeDevelopExportRequestV30) == NativeDevelopExporter.RequestV30Size,
            "develop_export_v30_request_size");
        context.Check(
            sizeof(NativeDevelopExportResultV2) == NativeDevelopExporter.ResultV2Size,
            "develop_export_v2_result_size");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV1>(
                nameof(NativeDevelopExportRequestV1.FilmEmulationIntensity)).ToInt32() == 80,
            "develop_export_intensity_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportResultV1>(
                nameof(NativeDevelopExportResultV1.FailureName)).ToInt32() == 12,
            "develop_export_failure_name_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportResultV1>(
                nameof(NativeDevelopExportResultV1.SourceFileBytes)).ToInt32() == 104,
            "develop_export_source_bytes_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV2>(
                nameof(NativeDevelopExportRequestV2.BaseEstimationMode)).ToInt32() == 32,
            "develop_export_v2_base_mode_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV3>(
                nameof(NativeDevelopExportRequestV3.Density)).ToInt32() == 92,
            "develop_export_v3_basic_tone_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV4>(
                nameof(NativeDevelopExportRequestV4.FilmStockDminId)).ToInt32() == 112,
            "develop_export_v4_film_stock_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV5>(
                nameof(NativeDevelopExportRequestV5.PointCurveRgb)).ToInt32() == 128,
            "develop_export_v5_point_curve_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV6>(
                nameof(NativeDevelopExportRequestV6.ColorMixerHue)).ToInt32() == 4256,
            "develop_export_v6_color_mixer_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV7>(
                nameof(NativeDevelopExportRequestV7.ColorGradingShadowsHue)).ToInt32() == 4352,
            "develop_export_v7_color_grading_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV8>(
                nameof(NativeDevelopExportRequestV8.DefectRemovalStrength)).ToInt32() == 4400,
            "develop_export_v8_grain_mend_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV9>(
                nameof(NativeDevelopExportRequestV9.NoiseReductionStrength)).ToInt32() == 4408,
            "develop_export_v9_noise_reduction_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV9>(
                nameof(NativeDevelopExportRequestV9.NoiseReductionFilmProfile)).ToInt32() == 4432,
            "develop_export_v9_noise_reduction_profile_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV10>(
                nameof(NativeDevelopExportRequestV10.TextureGrain)).ToInt32() == 4440,
            "develop_export_v10_texture_offset");
          context.Check(
              Marshal.OffsetOf<NativeDevelopExportRequestV10>(
                  nameof(NativeDevelopExportRequestV10.TextureVignette)).ToInt32() == 4456,
              "develop_export_v10_vignette_offset");
          context.Check(
              Marshal.OffsetOf<NativeDevelopExportRequestV11>(
                  nameof(NativeDevelopExportRequestV11.BwToningMode)).ToInt32() == 4464,
              "develop_export_v11_bw_toning_offset");
          context.Check(
              Marshal.OffsetOf<NativeDevelopExportRequestV11>(
                  nameof(NativeDevelopExportRequestV11.StraightenAngle)).ToInt32() == 4544,
              "develop_export_v11_straighten_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV12>(
                nameof(NativeDevelopExportRequestV12.LocalAdjustments)).ToInt32() == 4552,
            "develop_export_v12_adjustment_pointer_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV12>(
                nameof(NativeDevelopExportRequestV12.LocalPoints)).ToInt32() == 4584,
            "develop_export_v12_point_pointer_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV13>(
                nameof(NativeDevelopExportRequestV13.Warmth)).ToInt32() == 4600,
            "develop_export_v13_warmth_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV13>(
                nameof(NativeDevelopExportRequestV13.BluePrimary)).ToInt32() == 4628,
            "develop_export_v13_blue_primary_offset");
        context.Check(
            Marshal.OffsetOf<NativeDefectRegionEditV1>(
                nameof(NativeDefectRegionEditV1.Strength)).ToInt32() == 32,
            "defect_region_edit_strength_offset");
        context.Check(
            Marshal.OffsetOf<NativeDefectRegionEditV1>(
                nameof(NativeDefectRegionEditV1.PreferredAngleDegrees)).ToInt32() == 48,
            "defect_region_edit_angle_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV18>(
                nameof(NativeDevelopExportRequestV18.DefectRegionEdits)).ToInt32() == 4664,
            "develop_export_v18_defect_edits_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV18>(
                nameof(NativeDevelopExportRequestV18.DefectMaskBytes)).ToInt32() == 4680,
            "develop_export_v18_defect_mask_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV19>(
                nameof(NativeDevelopExportRequestV19.DefectSourceFileBytes)).ToInt32() == 4696,
            "develop_export_v19_defect_source_size_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV19>(
                nameof(NativeDevelopExportRequestV19.DefectSourceSha256)).ToInt32() == 4704,
            "develop_export_v19_defect_source_sha_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV20>(
                nameof(NativeDevelopExportRequestV20.DefectCloneEdits)).ToInt32() == 4720,
            "develop_export_v20_clone_edit_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV20>(
                nameof(NativeDevelopExportRequestV20.DefectCloneStrokes)).ToInt32() == 4736,
            "develop_export_v20_clone_stroke_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV20>(
                nameof(NativeDevelopExportRequestV20.DefectClonePoints)).ToInt32() == 4752,
            "develop_export_v20_clone_point_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV20>(
                nameof(NativeDevelopExportRequestV20.DefectEditOrder)).ToInt32() == 4768,
            "develop_export_v20_edit_order_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV21>(
                nameof(NativeDevelopExportRequestV21.DefectBrushEdits)).ToInt32() == 4784,
            "develop_export_v21_brush_edit_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV21>(
                nameof(NativeDevelopExportRequestV21.DefectBrushStrokes)).ToInt32() == 4800,
            "develop_export_v21_brush_stroke_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV21>(
                nameof(NativeDevelopExportRequestV21.DefectBrushPoints)).ToInt32() == 4816,
            "develop_export_v21_brush_point_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV24>(
                nameof(NativeDevelopExportRequestV24.DefectInfraredEdits)).ToInt32() == 4832,
            "develop_export_v24_infrared_edit_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV24>(
                nameof(NativeDevelopExportRequestV24.DefectInfraredAttenuationBytes)).ToInt32() ==
                4848,
            "develop_export_v24_attenuation_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV25>(
                nameof(NativeDevelopExportRequestV25.DefectInfraredItems)).ToInt32() == 4864,
            "develop_export_v25_infrared_item_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV26>(
                nameof(NativeDevelopExportRequestV26.OutputSharpeningStrength)).ToInt32() ==
                4880,
            "develop_export_v26_output_sharpening_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV27>(
                nameof(NativeDevelopExportRequestV27.PrimaryCalibrationRedHue)).ToInt32() ==
                4896,
            "develop_export_v27_primary_calibration_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV28>(
                nameof(NativeDevelopExportRequestV28.JpegQuality)).ToInt32() == 4928,
            "develop_export_v28_jpeg_quality_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV29>(
                nameof(NativeDevelopExportRequestV29.OutputLongEdge)).ToInt32() == 4944,
            "develop_export_v29_long_edge_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV30>(
                nameof(NativeDevelopExportRequestV30.TiffCompression)).ToInt32() == 4960,
            "develop_export_v30_tiff_compression_offset");
        context.Check(
            Marshal.OffsetOf<NativeDevelopExportResultV2>(
                nameof(NativeDevelopExportResultV2.AppliedDminRed)).ToInt32() == 136,
            "develop_export_v2_applied_dmin_offset");
    }
}
