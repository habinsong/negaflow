namespace Negaflow.Interop;

/// <summary>
/// 인화소 프로파일이 재현하지 못하는 화소를 표시합니다. macOS
/// <c>DestinationGamutWarning.makeOverlay(for:context:settings:)</c> 자리입니다.
/// </summary>
/// <remarks>
/// <para>
/// 판정은 Windows ICM 의 진짜 gamut-check 변환입니다. 근사하지 않으며, 변환을 만들지 못하면
/// <b>아무것도 표시하지 않습니다</b> — macOS 도 같은 계약입니다.
/// </para>
/// <para>
/// 목적지는 반드시 <b>인화소가 준 프로파일</b>이어야 합니다. sRGB 화소를 sRGB(또는 그보다
/// 넓은 공간) 기준으로 판정하면 색역 밖 화소가 나올 수 없어 경고가 한 점도 그려지지
/// 않습니다.
/// </para>
/// </remarks>
public static unsafe class NativeGamutMask
{
    /// <summary>macOS 오버레이 색입니다 — 빨강, 알파 166.</summary>
    public const byte OverlayAlpha = 166;

    /// <summary>마지막 판정에서 표시가 걸린 첫 행과 끝 행입니다. 진단용입니다.</summary>
    public static int FirstMarkedRow { get; private set; } = -1;

    public static int LastMarkedRow { get; private set; } = -1;

    /// <summary>
    /// 화면 화소를 인화지 프로파일로 갔다가 되돌립니다 — 소프트 프루프의 본체입니다.
    /// 인화지가 못 내는 색이 눌려 보입니다. 되지 않으면 화소를 건드리지 않습니다.
    /// </summary>
    public static bool Proof(
        Span<byte> pixels,
        int width,
        int height,
        ReadOnlySpan<byte> destinationIcc)
    {
        if (width <= 0 || height <= 0 ||
            destinationIcc.Length == 0 ||
            pixels.Length < (long)width * height * 4)
        {
            return false;
        }
        fixed (byte* pixelBytes = pixels)
        fixed (byte* iccBytes = destinationIcc)
        {
            return NativeColorProof.nf_soft_proof_convert_bgra_icc_v1(
                pixelBytes,
                (uint)width,
                (uint)height,
                (uint)(width * 4),
                iccBytes,
                (uint)destinationIcc.Length) == 0U;
        }
    }

    /// <summary>
    /// BGRA8 화소에서 색역 밖 화소를 골라 그 자리를 macOS 와 같은 빨강으로 덮습니다.
    /// 표시한 화소 수를 내며, 판정할 수 없으면 <see langword="null"/> 입니다.
    /// </summary>
    public static long? Mark(
        Span<byte> pixels,
        int width,
        int height,
        ReadOnlySpan<byte> destinationIcc)
    {
        if (width <= 0 || height <= 0 ||
            destinationIcc.Length == 0 ||
            pixels.Length < (long)width * height * 4)
        {
            return null;
        }
        byte[] mask = new byte[(long)width * height];
        uint status;
        fixed (byte* pixelBytes = pixels)
        fixed (byte* iccBytes = destinationIcc)
        fixed (byte* maskBytes = mask)
        {
            status = NativeColorProof.nf_gamut_check_mask_icc_v1(
                pixelBytes,
                (uint)width,
                (uint)height,
                (uint)(width * 4),
                iccBytes,
                (uint)destinationIcc.Length,
                maskBytes,
                (uint)mask.Length);
        }
        if (status != 0U)
        {
            return null;
        }
        // macOS 는 R=255 를 알파 166 으로 얹습니다. 같은 합성을 여기서 미리 해 둡니다.
        const double alpha = OverlayAlpha / 255.0;
        const double keep = 1.0 - alpha;
        long marked = 0;
        FirstMarkedRow = -1;
        LastMarkedRow = -1;
        for (int index = 0; index < mask.Length; ++index)
        {
            if (mask[index] == 0)
            {
                continue;
            }
            ++marked;
            int row = index / width;
            if (FirstMarkedRow < 0)
            {
                FirstMarkedRow = row;
            }
            LastMarkedRow = row;
            int at = index * 4;
            pixels[at] = (byte)(pixels[at] * keep);
            pixels[at + 1] = (byte)(pixels[at + 1] * keep);
            pixels[at + 2] = (byte)((pixels[at + 2] * keep) + (255.0 * alpha));
        }
        return marked;
    }
}
