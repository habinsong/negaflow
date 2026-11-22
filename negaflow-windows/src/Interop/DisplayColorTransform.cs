using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>
/// sRGB 로 그린 미리보기를 모니터 ICC 공간으로 옮기는 표입니다. 프로파일마다 한 번 만들고,
/// 그릴 때마다 <see cref="Apply"/> 로 BGRA 화소를 옮깁니다.
/// </summary>
/// <remarks>
/// Advanced Color 가 꺼진 Windows 는 앱 화소를 sRGB 로 보고 그대로 화면에 보냅니다. 광색역
/// 모니터에서 과포화로 보이는 이유입니다. 켜져 있으면 OS 가 옮기고 프로파일 API 는 sRGB 를
/// 돌려주므로 표가 항등이 되고 <see cref="TryCreate"/> 는 null 을 돌려줍니다.
/// </remarks>
public sealed unsafe partial class DisplayColorTransform : IDisposable
{
    private const string LibraryName = NativeMethods.LibraryName;
    private nint handle;

    private DisplayColorTransform(nint handle) => this.handle = handle;

    /// <summary>
    /// 모니터 프로파일로 표를 만듭니다. 항등이거나 만들 수 없으면 null 입니다 — 둘 다 화소를
    /// 그대로 그리면 됩니다.
    /// </summary>
    public static DisplayColorTransform? TryCreate(ReadOnlySpan<byte> monitorProfile)
    {
        if (monitorProfile.Length < 128)
        {
            return null;
        }
        nint created = 0;
        uint identity = 0U;
        uint nativeError = 0U;
        uint status;
        fixed (byte* profile = monitorProfile)
        {
            status = nf_display_color_transform_create_v1(
                profile, (uint)monitorProfile.Length, &created, &identity, &nativeError);
        }
        if (status != 0U || created == 0)
        {
            return null;
        }
        if (identity != 0U)
        {
            nf_display_color_transform_destroy_v1(created);
            return null;
        }
        return new DisplayColorTransform(created);
    }

    /// <summary>
    /// 소프트 프루프 왕복표(sRGB → <paramref name="proofProfile"/> → sRGB)를 만듭니다.
    /// <paramref name="identity"/> 가 true 면 프루프가 화소를 바꾸지 않으므로 아무것도 할 필요가
    /// 없습니다. 만들 수 없으면 null 이고 identity 는 false 입니다.
    /// </summary>
    public static DisplayColorTransform? TryCreateProof(ReadOnlySpan<byte> proofProfile, out bool identity)
    {
        identity = false;
        if (proofProfile.Length < 128)
        {
            return null;
        }
        nint created = 0;
        uint isIdentity = 0U;
        uint nativeError = 0U;
        uint status;
        fixed (byte* profile = proofProfile)
        {
            status = nf_proof_color_transform_create_v1(
                profile, (uint)proofProfile.Length, &created, &isIdentity, &nativeError);
        }
        if (status != 0U || created == 0)
        {
            return null;
        }
        if (isIdentity != 0U)
        {
            identity = true;
            nf_display_color_transform_destroy_v1(created);
            return null;
        }
        return new DisplayColorTransform(created);
    }

    /// <summary>
    /// BGRA8 을 옮깁니다. 알파는 그대로입니다. <paramref name="source"/> 와
    /// <paramref name="destination"/> 은 같은 배열이어도 됩니다.
    /// </summary>
    public bool Apply(ReadOnlySpan<byte> source, Span<byte> destination, int width, int height)
    {
        int bytes = width * height * 4;
        if (handle == 0 || width <= 0 || height <= 0 ||
            source.Length < bytes || destination.Length < bytes)
        {
            return false;
        }
        fixed (byte* input = source)
        fixed (byte* output = destination)
        {
            return nf_display_color_transform_apply_bgra_v1(
                handle, input, output, (uint)width, (uint)height, (uint)(width * 4)) == 0U;
        }
    }

    public void Dispose()
    {
        nint current = handle;
        handle = 0;
        if (current != 0)
        {
            nf_display_color_transform_destroy_v1(current);
        }
    }

    [LibraryImport(LibraryName, EntryPoint = "nf_display_color_transform_create_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    private static partial uint nf_display_color_transform_create_v1(
        byte* monitorIcc,
        uint monitorIccSize,
        nint* transform,
        uint* isIdentity,
        uint* nativeErrorCode);

    [LibraryImport(LibraryName, EntryPoint = "nf_proof_color_transform_create_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    private static partial uint nf_proof_color_transform_create_v1(
        byte* proofIcc,
        uint proofIccSize,
        nint* transform,
        uint* isIdentity,
        uint* nativeErrorCode);

    [LibraryImport(LibraryName, EntryPoint = "nf_display_color_transform_apply_bgra_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    private static partial uint nf_display_color_transform_apply_bgra_v1(
        nint transform,
        byte* source,
        byte* destination,
        uint width,
        uint height,
        uint strideBytes);

    [LibraryImport(LibraryName, EntryPoint = "nf_display_color_transform_destroy_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    private static partial void nf_display_color_transform_destroy_v1(nint transform);
}
