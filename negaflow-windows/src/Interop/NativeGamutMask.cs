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
        // **프로파일마다 한 번 만든 왕복표**로 옮깁니다. 프레임마다 ICM 을 부르면 슬라이더를 끄는
        // 동안 미리보기 한 장에 수십 ms 가 더 듭니다. 표를 못 만들면 아래 ICM 직접 변환으로
        // 물러납니다.
        // 표를 고르는 일과 **쓰는 일을 같은 잠금 안에서** 합니다. 잠금 밖에서 쓰면 다른 프로파일로
        // 들어온 스레드(현상 미리보기와 인화 미리보기)가 표를 바꾸며 이전 표를 해제하는 동안 그
        // 네이티브 표를 읽게 됩니다(해제 후 사용). 적용은 네이티브 안에서 행 블록 병렬이라 두
        // 미리보기가 잠깐 줄을 서는 비용뿐입니다.
        lock (ProofGate)
        {
            if (ProofTableLocked(destinationIcc, out bool identity) is { } table)
            {
                Span<byte> region = pixels[..(width * height * 4)];
                return table.Apply(region, region, width, height);
            }
            if (identity)
            {
                return true;
            }
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

    private static readonly Lock ProofGate = new();
    private static string proofKey = string.Empty;
    private static DisplayColorTransform? proofTable;
    private static bool proofIdentity;

    /// <summary>
    /// 마지막으로 쓴 프로파일의 왕복표입니다. 프로파일이 바뀌면 다시 만듭니다.
    /// <see cref="ProofGate"/> 를 쥔 채로만 부르고, 돌려받은 표도 그 안에서만 씁니다.
    /// </summary>
    private static DisplayColorTransform? ProofTableLocked(ReadOnlySpan<byte> icc, out bool identity)
    {
        string key = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(icc));
        if (!string.Equals(key, proofKey, StringComparison.Ordinal))
        {
            proofTable?.Dispose();
            proofTable = DisplayColorTransform.TryCreateProof(icc, out proofIdentity);
            proofKey = key;
        }
        identity = proofIdentity;
        return proofTable;
    }

    /// <summary>
    /// BGRA8 화소에서 색역 밖 화소를 골라 그 자리를 macOS 와 같은 빨강으로 덮습니다.
    /// 표시한 화소 수를 내며, 판정할 수 없으면 <see langword="null"/> 입니다.
    /// </summary>
    public static long? Mark(
        Span<byte> pixels,
        int width,
        int height,
        ReadOnlySpan<byte> destinationIcc) =>
        Mark(pixels, pixels, width, height, destinationIcc);

    /// <summary>
    /// <paramref name="judged"/> 화소로 판정하고 표시는 <paramref name="pixels"/> 에 칠합니다.
    /// 프루프 왕복을 거친 화소는 이미 목적지 색역 안으로 눌려 있어 판정할 것이 남지 않으므로,
    /// 판정은 왕복 <b>전</b> 화소로 해야 합니다(macOS 도 프루프 전 그림으로 판정합니다).
    /// </summary>
    public static long? Mark(
        Span<byte> pixels,
        ReadOnlySpan<byte> judged,
        int width,
        int height,
        ReadOnlySpan<byte> destinationIcc)
    {
        if (width <= 0 || height <= 0 ||
            destinationIcc.Length == 0 ||
            pixels.Length < (long)width * height * 4 ||
            judged.Length < (long)width * height * 4)
        {
            return null;
        }
        byte[] mask = new byte[(long)width * height];
        uint status;
        fixed (byte* pixelBytes = judged)
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
            // 투명 화소(원근 보정의 빈 곳)는 사진이 아니라 표시하지 않습니다(macOS 와 같음).
            if (mask[index] == 0 || judged[(index * 4) + 3] == 0)
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
