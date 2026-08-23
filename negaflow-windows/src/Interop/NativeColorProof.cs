using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>색역 판정, 필름 베이스 스포이드, 소프트 프루프 용지 읽기입니다.</summary>
internal static partial class NativeColorProof
{
    private const string LibraryName = NativeMethods.LibraryName;

    [LibraryImport(LibraryName, EntryPoint = "nf_gamut_check_supported_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_gamut_check_supported_v1(
        uint outputColorSpace,
        uint* supported);

    [LibraryImport(LibraryName, EntryPoint = "nf_pick_film_base_v1", StringMarshalling = StringMarshalling.Utf16)]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_pick_film_base_v1(
        string sourcePath,
        double unitX,
        double unitY,
        uint filmType,
        NativeFilmBasePickV1* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_soft_proof_convert_bgra_icc_v1")]
    internal static unsafe partial uint nf_soft_proof_convert_bgra_icc_v1(
        byte* pixels,
        uint width,
        uint height,
        uint strideBytes,
        byte* destinationIcc,
        uint destinationIccSize);

    [LibraryImport(LibraryName, EntryPoint = "nf_gamut_check_mask_icc_v1")]
    internal static unsafe partial uint nf_gamut_check_mask_icc_v1(
        byte* pixels,
        uint width,
        uint height,
        uint strideBytes,
        byte* destinationIcc,
        uint destinationIccSize,
        byte* mask,
        uint maskSize);

    [LibraryImport(LibraryName, EntryPoint = "nf_read_soft_proof_media_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_read_soft_proof_media_v1(
        byte* iccBytes,
        uint iccByteCount,
        NativeSoftProofMediaV1* result);
}
