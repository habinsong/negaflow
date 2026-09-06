using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using static Negaflow.Interop.NativeDevelopRequestV18V34;

namespace Negaflow.Interop;

internal static unsafe partial class NativeDevelopInput
{
    internal static bool RequiresV39(DevelopExportRequest request) =>
        request.BaseScale != 1.0 || request.InputGammaMode != 0U;

    internal static void Validate(DevelopExportRequest request)
    {
        if (!double.IsFinite(request.BaseScale) || request.BaseScale is < 0.5 or > 1.5 ||
            !ValidGamma(request.InputGammaMode, request.InputGammaValue))
        {
            throw new ArgumentOutOfRangeException(nameof(request), "Invalid input gamma or base scale.");
        }
    }

    internal static bool ValidGamma(uint mode, double value) =>
        (mode == 0U && value == 0.0) || (mode == 1U && double.IsFinite(value) && value is >= 0.10 and <= 4.0);

    internal static NativeDevelopExportRequestV39 Build(
        NativeDevelopExportRequestV36 v36, DevelopExportRequest request,
        byte* outputProfile = null, uint outputProfileSize = 0U)
    {
        Validate(request);
        NativeDevelopExportRequestV38 v38 = BuildRequestV38(
            BuildRequestV37(v36, outputProfile, outputProfileSize), request.ProxyInputLongEdge);
        v38.V37.V36.V35.V34.V33.V32.V31.V30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16
            .V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV39);
        return new() { V38 = v38, BaseScale = request.BaseScale,
            InputGammaMode = request.InputGammaMode, InputGammaValue = request.InputGammaValue };
    }

    internal static NativeDevelopExportRequestV34 BuildDisplayRequest(NativeDevelopExportRequestV27 v27, DevelopExportRequest request) =>
        BuildRequestV34(BuildRequestV33(
            BuildRequestV32(BuildRequestV31(BuildRequestV30(BuildRequestV29(BuildRequestV28(v27, request), request), request), request), request),
            request, null, null, null, null, null, null, null, null), request);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_pick_film_base_v2")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Pick(NativeDevelopExportRequestV39* request, double unitX, double unitY,
        NativeDevelopRunStateV1* state, NativeDevelopExportResultV3* result, NativeFilmBasePickV1* picked);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_develop_export_v39")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Export(NativeDevelopExportRequestV39* request,
        NativeDevelopRunStateV1* state, NativeDevelopExportResultV3* result);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_develop_preview_v39")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Preview(NativeDevelopExportRequestV39* request,
        NativeSoftProofV1* proof, uint width, uint height, byte* pixels, uint capacity,
        NativeDevelopRunStateV1* state, NativeDevelopExportResultV3* result);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_develop_preview_background_v2")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Background(NativeDevelopExportRequestV39* request,
        uint width, uint height, byte* pixels, uint capacity,
        NativeDevelopRunStateV1* state, NativeDevelopExportResultV3* result);

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_develop_detect_grain_mend_v8")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint Detect(NativeDevelopExportRequestV39* request,
        NativeGrainMendDetectParametersV3* parameters, NativeDevelopRunStateV1* state,
        NativeGrainMendDetectionV4* detection, NativeDevelopExportResultV3* result, nint* review);
}
