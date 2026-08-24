using System.Buffers.Binary;
using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class DevelopExportRoutingContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        bool currentEntryPointReported = false;
        try
        {
            NativeDevelopResultTranslator.Translate(
                NativeDevelopExportLimits.StatusInvalidArgument,
                default(NativeDevelopExportResultV3),
                NativeGrainMendDetect.CurrentEntryPoint);
        }
        catch (NativeBootstrapException exception)
        {
            currentEntryPointReported =
                NativeGrainMendDetect.CurrentEntryPoint ==
                    "nf_develop_detect_grain_mend_v7" &&
                exception.Message.Contains(
                    NativeGrainMendDetect.CurrentEntryPoint,
                    StringComparison.Ordinal) &&
                !exception.Message.Contains(
                    "nf_develop_detect_grain_mend_v4",
                    StringComparison.Ordinal);
        }
        context.Check(
            currentEntryPointReported,
            "grain_mend_detection_diagnostics_name_the_current_entry_point");

        context.Check(
            NativeGrainMendDetect.CurrentEntryPoint == "nf_develop_detect_grain_mend_v7",
            "grain_mend_product_path_uses_single_detection_review_handle");

        string temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-develop-export-{Guid.NewGuid():N}");
        string absentSource = Path.Combine(temporaryRoot, "absent.tif");
        string destination = Path.Combine(temporaryRoot, "out.png");
        Directory.CreateDirectory(temporaryRoot);

        VerifyManagedGrainMendPayloadValidation(context);
        VerifyManagedGrainMendV7(context, temporaryRoot);

        // A missing source must be reported as an observation failure, not as a
        // malformed request, so the shell can tell a user error from a bug.
        DevelopExportResult missing = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
        });
        context.Check(!missing.Succeeded, "develop_export_missing_source_fails");
        context.Check(
            missing.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_missing_source_stage");
        context.Check(missing.FailureName.Length > 0, "develop_export_failure_name_present");
        context.Check(missing.FailureName != "ok", "develop_export_failure_name_not_ok");
        context.Check(!File.Exists(destination), "develop_export_failure_writes_nothing");

        DevelopExportResult autoMissing = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            BaseEstimationMode = DevelopBaseEstimationMode.Auto,
        });
        context.Check(
            autoMissing.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_auto_reaches_source_observation");

        DevelopExportResult digital = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            FilmLookSourceKind = DevelopSourceKind.RenderedDigital,
            FilmEmulation = FilmEmulationProfile.Vision3_500T,
        });
        context.Check(!digital.Succeeded, "develop_export_digital_source_fails");
        context.Check(
            digital.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_vision3_digital_source_stage");
        context.Check(
            digital.FailureName != "ok",
            "develop_export_digital_source_name");

        DevelopExportResult outputSharpening = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            OutputSharpening = 0.80F,
            OutputSharpeningMedium = OutputSharpeningMedium.MattePaper,
            OutputSharpeningDpi = 300,
        });
        context.Check(
            outputSharpening.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_output_sharpening_reaches_source_observation");

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
        context.Check(
            local.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_local_mask_reaches_source_observation");
    }

    private static void VerifyManagedGrainMendPayloadValidation(ContractTestContext context)
    {
        NativeGrainMendDetectionV4 extension = default;
        extension.V3.V2.StructSize = (uint)sizeof(NativeGrainMendDetectionV4);
        extension.AutomaticCandidatePixelFraction = 0.25;
        NativeDevelopPreviewRender.ValidateGrainMendDetectionExtension(extension);
        extension.Reserved = 1U;
        context.CheckThrows<NativeBootstrapException>(
            () => NativeDevelopPreviewRender.ValidateGrainMendDetectionExtension(extension),
            "grain_mend_v7_rejects_malformed_extension_fields");

        NativeGrainMendDetectionV2 detection = new()
        {
            StructSize = (uint)sizeof(NativeGrainMendDetectionV2),
            Width = 4U,
            Height = 4U,
            AcceptedPixels = 1UL,
            MaskByteCount = 16UL,
            SourceWidth = 8U,
            SourceHeight = 8U,
            RoiX = 2U,
            RoiY = 2U,
            RoiWidth = 4U,
            RoiHeight = 4U,
        };
        NativeDevelopGrainMendDetect.ValidateDetectionGeometry(
            detection, 1UL, 1UL, 0.25);
        NativeGrainMendDetectionV2 invalidDetection = detection;
        invalidDetection.RoiWidth = 3U;
        context.CheckThrows<NativeBootstrapException>(
            () => NativeDevelopGrainMendDetect.ValidateDetectionGeometry(
                invalidDetection, 1UL, 1UL, 0.25),
            "grain_mend_v7_rejects_mismatched_detection_roi_geometry");
        invalidDetection = detection;
        invalidDetection.RoiX = 7U;
        context.CheckThrows<NativeBootstrapException>(
            () => NativeDevelopGrainMendDetect.ValidateDetectionGeometry(
                invalidDetection, 1UL, 1UL, 0.25),
            "grain_mend_v7_rejects_out_of_source_detection_roi");
        invalidDetection = detection;
        invalidDetection.MaskByteCount = 15UL;
        context.CheckThrows<NativeBootstrapException>(
            () => NativeDevelopGrainMendDetect.ValidateDetectionGeometry(
                invalidDetection, 1UL, 1UL, 0.25),
            "grain_mend_v7_rejects_inconsistent_detection_mask_size");
        invalidDetection = detection;
        invalidDetection.AcceptedPixels = 17UL;
        context.CheckThrows<NativeBootstrapException>(
            () => NativeDevelopGrainMendDetect.ValidateDetectionGeometry(
                invalidDetection, 1UL, 1UL, 0.25),
            "grain_mend_v7_rejects_unbounded_accepted_pixels");
        context.CheckThrows<NativeBootstrapException>(
            () => NativeDevelopGrainMendDetect.ValidateDetectionGeometry(
                detection, 1UL, 1UL, double.NaN),
            "grain_mend_v7_rejects_nonfinite_candidate_fraction");
        context.CheckThrows<NativeBootstrapException>(
            () => NativeDevelopGrainMendDetect.ValidateDetectionGeometry(
                detection, 0UL, 0UL, 0.0),
            "grain_mend_v7_rejects_pixels_without_components");

        NativeGrainMendComponentV1 component = new()
        {
            StructSize = (uint)sizeof(NativeGrainMendComponentV1),
            Classification = (uint)GrainMendDefectClass.Dust,
            Confidence = 0.75,
            Area = 1UL,
            MinimumX = 1U,
            MinimumY = 1U,
            MaximumX = 1U,
            MaximumY = 1U,
            PreviewPointOffset = 0UL,
            PreviewPointCount = 1UL,
        };
        NativeGrainMendPreviewPointV1 point = new() { X = 1U, Y = 1U };
        context.Check(
            NativeDevelopGrainMendDetect.ReadComponents(
                [component], 1UL, [point], 1UL, 4U, 4U).Count == 1,
            "grain_mend_v7_accepts_complete_component_payload");

        NativeGrainMendComponentV1 malformed = component;
        malformed.StructSize = 0U;
        CheckMalformedComponent(context, malformed, point,
            "grain_mend_v7_rejects_component_struct_size");
        malformed = component;
        malformed.Classification = 7U;
        CheckMalformedComponent(context, malformed, point,
            "grain_mend_v7_rejects_unknown_component_classification");
        malformed = component;
        malformed.Confidence = double.PositiveInfinity;
        CheckMalformedComponent(context, malformed, point,
            "grain_mend_v7_rejects_nonfinite_component_confidence");
        malformed = component;
        malformed.Confidence = -0.01;
        CheckMalformedComponent(context, malformed, point,
            "grain_mend_v7_rejects_out_of_range_component_confidence");
        malformed = component;
        malformed.Area = 0UL;
        CheckMalformedComponent(context, malformed, point,
            "grain_mend_v7_rejects_empty_component_area");
        malformed = component;
        malformed.MinimumX = 2U;
        CheckMalformedComponent(context, malformed, point,
            "grain_mend_v7_rejects_reversed_component_bbox");
        malformed = component;
        malformed.MaximumX = 4U;
        CheckMalformedComponent(context, malformed, point,
            "grain_mend_v7_rejects_out_of_bounds_component_bbox");
        malformed = component;
        malformed.Area = 2UL;
        CheckMalformedComponent(context, malformed, point,
            "grain_mend_v7_rejects_area_larger_than_component_bbox");
        malformed = component;
        malformed.PreviewPointOffset = 1UL;
        CheckMalformedComponent(context, malformed, point,
            "grain_mend_v7_rejects_noncontiguous_preview_offset");
        NativeGrainMendPreviewPointV1 malformedPoint = new() { X = 4U, Y = 1U };
        CheckMalformedComponent(context, component, malformedPoint,
            "grain_mend_v7_rejects_out_of_bounds_preview_point");
        malformedPoint = new NativeGrainMendPreviewPointV1 { X = 2U, Y = 1U };
        CheckMalformedComponent(context, component, malformedPoint,
            "grain_mend_v7_rejects_preview_point_outside_component_bbox");
        context.CheckThrows<NativeBootstrapException>(
            () => NativeDevelopGrainMendDetect.ReadComponents(
                [component], 1UL, [point, point], 2UL, 4U, 4U),
            "grain_mend_v7_rejects_trailing_preview_payload");

        NativeGrainMendAcceptedRegionV1 accepted = new()
        {
            StructSize = (uint)sizeof(NativeGrainMendAcceptedRegionV1),
            Status = 0U,
            RoiX = 3U,
            RoiY = 3U,
            Width = 2U,
            Height = 2U,
            MaskByteCount = 16UL,
            IncludedComponentCount = 1UL,
        };
        GrainMendReviewProposal.ValidateAcceptedDescriptor(
            accepted, 2U, 2U, 4U, 4U, 1);
        context.Check(true, "grain_mend_v7_accepts_contained_accepted_region");

        NativeGrainMendAcceptedRegionV1 malformedAccepted = accepted;
        malformedAccepted.StructSize = 0U;
        CheckMalformedAcceptedRegion(context, malformedAccepted,
            "grain_mend_v7_rejects_accepted_struct_size");
        malformedAccepted = accepted;
        malformedAccepted.RoiX = 1U;
        CheckMalformedAcceptedRegion(context, malformedAccepted,
            "grain_mend_v7_rejects_accepted_region_left_of_proposal");
        malformedAccepted = accepted;
        malformedAccepted.RoiY = 1U;
        CheckMalformedAcceptedRegion(context, malformedAccepted,
            "grain_mend_v7_rejects_accepted_region_above_proposal");
        malformedAccepted = accepted;
        malformedAccepted.RoiX = 5U;
        CheckMalformedAcceptedRegion(context, malformedAccepted,
            "grain_mend_v7_rejects_accepted_region_right_of_proposal");
        malformedAccepted = accepted;
        malformedAccepted.RoiY = 5U;
        CheckMalformedAcceptedRegion(context, malformedAccepted,
            "grain_mend_v7_rejects_accepted_region_below_proposal");
    }

    private static void CheckMalformedComponent(
        ContractTestContext context,
        NativeGrainMendComponentV1 component,
        NativeGrainMendPreviewPointV1 point,
        string name) =>
        context.CheckThrows<NativeBootstrapException>(
            () => NativeDevelopGrainMendDetect.ReadComponents(
                [component], 1UL, [point], 1UL, 4U, 4U),
            name);

    private static void CheckMalformedAcceptedRegion(
        ContractTestContext context,
        NativeGrainMendAcceptedRegionV1 accepted,
        string name) =>
        context.CheckThrows<NativeBootstrapException>(
            () => GrainMendReviewProposal.ValidateAcceptedDescriptor(
                accepted, 2U, 2U, 4U, 4U, 1),
            name);

    private static void VerifyManagedGrainMendV7(
        ContractTestContext context,
        string temporaryRoot)
    {
        const uint width = 320U;
        const uint height = 320U;
        string source = Path.Combine(temporaryRoot, "grain-mend-v7.tif");
        WriteSyntheticDefectTiff(source, width, height);
        GrainMendDetectionResult detected = NativeDevelopExporter.DetectGrainMend(
            new DevelopExportRequest
            {
                SourcePath = source,
                DestinationPath = Path.Combine(temporaryRoot, "grain-mend-v7.png"),
                BaseEstimationMode = DevelopBaseEstimationMode.Auto,
                DefectRemovalStrength = 1.0,
            },
            detectionOptions: new GrainMendDetectionOptions(1.0, 1.0, 0.0, false, false));

        IGrainMendReviewProposal? proposal = detected.ReviewProposal;
        context.Check(
            detected.Result.Succeeded && proposal is not null &&
            detected.Width == width && detected.Height == height &&
            detected.Defects.Count > 0 &&
            detected.Defects.All(component => component.Points.Count > 0),
            "grain_mend_v7_managed_detect_copies_one_exact_review_payload");
        if (proposal is null)
        {
            return;
        }

        try
        {
            GrainMendPreviewPoint point = proposal.Components[0].Points[0];
            context.Check(
                proposal.TryHit(
                    checked((int)point.X), checked((int)point.Y), 3U, out int component) &&
                component >= 0 && component < proposal.Components.Count,
                "grain_mend_v7_managed_hit_uses_native_component_ownership");

            byte[] excluded = new byte[proposal.Components.Count];
            GrainMendAcceptedRegion? accepted = proposal.BuildAccepted(excluded);
            context.Check(
                accepted is not null && accepted.Width > 0U && accepted.Height > 0U &&
                accepted.RgbaMask.LongLength ==
                    checked((long)accepted.Width * accepted.Height * 4L) &&
                accepted.IncludedComponentCount == (ulong)proposal.Components.Count &&
                accepted.RgbaMask.Any(value => value != 0),
                "grain_mend_v7_managed_accept_copies_exact_rgba_region");

            Array.Fill(excluded, (byte)1);
            context.Check(
                proposal.BuildAccepted(excluded) is null,
                "grain_mend_v7_managed_all_excluded_is_explicitly_empty");
        }
        finally
        {
            proposal.Dispose();
        }

        bool disposed = false;
        try
        {
            proposal.TryHit(0, 0, 0U, out _);
        }
        catch (ObjectDisposedException)
        {
            disposed = true;
        }
        context.Check(disposed, "grain_mend_v7_managed_review_release_is_terminal");
    }

    private static void WriteSyntheticDefectTiff(string path, uint width, uint height)
    {
        const int pixelOffset = 170;
        int pixelBytes = checked((int)((ulong)width * height * 6UL));
        byte[] bytes = new byte[checked(pixelOffset + pixelBytes)];
        bytes[0] = (byte)'I';
        bytes[1] = (byte)'I';
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(2), 42);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(4), 8U);
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(8), 12);
        int entry = 10;
        WriteEntry(bytes, ref entry, 256U, 4U, 1U, width);
        WriteEntry(bytes, ref entry, 257U, 4U, 1U, height);
        WriteEntry(bytes, ref entry, 258U, 3U, 3U, 158U);
        WriteEntry(bytes, ref entry, 259U, 3U, 1U, 1U);
        WriteEntry(bytes, ref entry, 262U, 3U, 1U, 2U);
        WriteEntry(bytes, ref entry, 273U, 4U, 1U, pixelOffset);
        WriteEntry(bytes, ref entry, 274U, 3U, 1U, 1U);
        WriteEntry(bytes, ref entry, 277U, 3U, 1U, 3U);
        WriteEntry(bytes, ref entry, 278U, 4U, 1U, height);
        WriteEntry(bytes, ref entry, 279U, 4U, 1U, checked((uint)pixelBytes));
        WriteEntry(bytes, ref entry, 284U, 3U, 1U, 1U);
        WriteEntry(bytes, ref entry, 339U, 3U, 3U, 164U);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(entry), 0U);
        for (int index = 0; index < 3; ++index)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(158 + (index * 2)), 16);
            BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(164 + (index * 2)), 1);
        }

        uint scratchX = width / 2U;
        int target = pixelOffset;
        for (uint y = 0U; y < height; ++y)
        {
            for (uint x = 0U; x < width; ++x)
            {
                bool scratch = (x == scratchX || x + 1U == scratchX) &&
                    y >= (height * 5U) / 8U && y < (height * 7U) / 8U;
                ushort red = scratch
                    ? ushort.MaxValue
                    : checked((ushort)(9_000U + (x * 24_000U) / (width - 1U)));
                ushort green = scratch
                    ? ushort.MaxValue
                    : checked((ushort)(12_000U + (y * 20_000U) / (height - 1U)));
                ushort blue = scratch
                    ? ushort.MaxValue
                    : checked((ushort)(10_000U + ((x + y) * 16_000U) /
                        (width + height - 2U)));
                BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(target), red);
                BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(target + 2), green);
                BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(target + 4), blue);
                target += 6;
            }
        }
        File.WriteAllBytes(path, bytes);
    }

    private static void WriteEntry(
        byte[] bytes,
        ref int offset,
        uint tag,
        uint type,
        uint count,
        uint value)
    {
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(offset), checked((ushort)tag));
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(offset + 2), checked((ushort)type));
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(offset + 4), count);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(offset + 8), value);
        offset += 12;
    }
}
