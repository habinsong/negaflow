using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using static Negaflow.Interop.NativeDevelopRequestV18V34;

namespace Negaflow.Interop;

internal static unsafe partial class NativeDevelopInput
{
    internal static bool RequiresV39(DevelopExportRequest request) =>
        request.AutoBalance || request.BaseScale != 1.0 || request.InputGammaMode != 0U ||
        request.ChannelRange is not null || request.MeasureRangeShape;

    internal static void Validate(DevelopExportRequest request)
    {
        if (!double.IsFinite(request.BaseScale) || request.BaseScale is < 0.5 or > 1.5 ||
            !ValidGamma(request.InputGammaMode, request.InputGammaValue))
        {
            throw new ArgumentOutOfRangeException(nameof(request), "Invalid input gamma or base scale.");
        }
        if (request.ChannelRange is { } range && !ValidChannelRange(range))
        {
            throw new ArgumentOutOfRangeException(nameof(request), "Invalid channel range.");
        }
    }

    // macOS `ChannelRangeCalibration.allowedMultiplier` 와 같은 범위입니다. native 도 같은 범위를 검증합니다.
    internal static bool ValidChannelRange(DevelopChannelRange range) =>
        range.Red is >= 0.5F and <= 2.0F && range.Green is >= 0.5F and <= 2.0F &&
        range.Blue is >= 0.5F and <= 2.0F;

    internal static bool ValidGamma(uint mode, double value) =>
        (mode == 0U && value == 0.0) || (mode == 1U && double.IsFinite(value) && value is >= 0.10 and <= 4.0);

    internal static NativeDevelopExportRequestV41 Build(
        NativeDevelopExportRequestV36 v36, DevelopExportRequest request,
        byte* outputProfile = null, uint outputProfileSize = 0U)
    {
        Validate(request);
        NativeDevelopExportRequestV38 v38 = BuildRequestV38(
            BuildRequestV37(v36, outputProfile, outputProfileSize), request.ProxyInputLongEdge);
        v38.V37.V36.V35.V34.V33.V32.V31.V30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16
            .V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV41);
        DevelopChannelRange range = request.ChannelRange ?? default;
        return new() { V40 = new() { V39 = new() { V38 = v38, BaseScale = request.BaseScale,
            InputGammaMode = request.InputGammaMode, InputGammaValue = request.InputGammaValue },
            AutoBalance = request.AutoBalance ? 1U : 0U },
            ChannelRangePresent = request.ChannelRange is null ? 0U : 1U,
            MeasureRangeShape = request.MeasureRangeShape ? 1U : 0U,
            ChannelRangeRed = range.Red, ChannelRangeGreen = range.Green, ChannelRangeBlue = range.Blue };
    }

    internal static NativeDevelopExportRequestV34 BuildDisplayRequest(NativeDevelopExportRequestV27 v27, DevelopExportRequest request) =>
        BuildRequestV34(BuildRequestV33(
            BuildRequestV32(BuildRequestV31(BuildRequestV30(BuildRequestV29(BuildRequestV28(v27, request), request), request), request), request),
            request, null, null, null, null, null, null, null, null), request);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_pick_film_base_v2")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Pick(NativeDevelopExportRequestV41* request, double unitX, double unitY,
        NativeDevelopRunStateV1* state, NativeDevelopExportResultV3* result, NativeFilmBasePickV1* picked);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_pick_neutral_white_balance_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint PickNeutral(NativeDevelopExportRequestV41* request, double unitX, double unitY,
        NativeDevelopRunStateV1* state, NativeDevelopExportResultV3* result, NativeNeutralWhiteBalancePickV1* picked);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_develop_export_v39")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Export(NativeDevelopExportRequestV41* request,
        NativeDevelopRunStateV1* state, NativeDevelopExportResultV3* result);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_develop_preview_v39")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Preview(NativeDevelopExportRequestV41* request,
        NativeSoftProofV1* proof, uint width, uint height, byte* pixels, uint capacity,
        NativeDevelopRunStateV1* state, NativeDevelopExportResultV3* result);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_develop_preview_background_v2")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Background(NativeDevelopExportRequestV41* request,
        uint width, uint height, byte* pixels, uint capacity,
        NativeDevelopRunStateV1* state, NativeDevelopExportResultV3* result);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_develop_detect_grain_mend_v8")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Detect(NativeDevelopExportRequestV41* request,
        NativeGrainMendDetectParametersV3* parameters, NativeDevelopRunStateV1* state,
        NativeGrainMendDetectionV4* detection, NativeDevelopExportResultV3* result, nint* review);
}
