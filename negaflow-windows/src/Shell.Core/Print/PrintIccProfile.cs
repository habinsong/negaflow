namespace Negaflow.Shell.Print;

/// <summary>
/// ICC 프로파일이 인화에 쓸 수 있는 것인지 봅니다. macOS
/// <c>SoftProof.rgbOutputColorSpace(fromICCData:)</c> 와 같은 판정입니다.
/// </summary>
/// <remarks>
/// macOS 는 <c>CGColorSpace(iccData:)</c> 를 만들어 <c>model == .rgb</c> 이고
/// <c>supportsOutput</c> 인지만 봅니다. 즉 <b>데이터 공간이 RGB 이고 출력에 쓸 수 있는가</b>
/// 입니다.
///
/// 전에는 매체 흰색·검정(<c>wtpt</c>·<c>bkpt</c>)을 읽어 보고 실패하면 거절했습니다. 그
/// 판정은 <b>표 기반 인화소 프로파일</b>을 통째로 거절합니다 — 실제 인화소가 주는
/// <c>prtr</c>/RGB/Lab + <c>A2B0</c>·<c>B2A0</c> 프로파일이 여기에 걸려 "인화소의 RGB ICC
/// 프로파일이 필요합니다" 만 뜨고 아무것도 불러오지 못했습니다. 매체 값은 용지·잉크 흉내에만
/// 쓰이며, 없으면 프로파일만 보는 쪽으로 물러나면 됩니다.
/// </remarks>
public static class PrintIccProfile
{
    /// <summary>ICC 머리말 길이입니다.</summary>
    private const int HeaderLength = 128;

    private const int DeviceClassOffset = 12;
    private const int ColorSpaceOffset = 16;

    /// <summary>인화 프루프에 쓸 수 있는 RGB 출력 프로파일인지.</summary>
    public static bool IsRgbOutput(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }
        try
        {
            using FileStream stream = File.OpenRead(path);
            Span<byte> header = stackalloc byte[HeaderLength];
            return stream.ReadAtLeast(header, HeaderLength, throwOnEndOfStream: false)
                    >= HeaderLength &&
                IsRgbOutput(header);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    /// <summary>머리말만 보고 판정합니다. 파일 없이 검사할 때 씁니다.</summary>
    public static bool IsRgbOutput(ReadOnlySpan<byte> header)
    {
        if (header.Length < HeaderLength)
        {
            return false;
        }
        if (!Signature(header, ColorSpaceOffset).Equals("RGB ", StringComparison.Ordinal))
        {
            return false;
        }
        // 출력에 쓸 수 있는 종류입니다. 인화소는 `prtr`, 화면 프로파일은 `mntr`, 색 공간
        // 프로파일은 `spac` 이며 셋 다 목적지로 쓸 수 있습니다. 입력 전용(`scnr`)과
        // 연결(`link`·`abst`·`nmcl`)은 목적지가 될 수 없습니다.
        string deviceClass = Signature(header, DeviceClassOffset);
        return deviceClass is "prtr" or "mntr" or "spac";
    }

    private static string Signature(ReadOnlySpan<byte> header, int offset) =>
        System.Text.Encoding.ASCII.GetString(header.Slice(offset, 4));
    /// <summary>
    /// PCS XYZ(D50) → 선형 sRGB. ICC sRGB 색소(Bradford 로 D50 에 맞춘 값)의 역행렬입니다(macOS
    /// <c>SoftProof.xyzD50ToLinearSRGB</c>, 네이티브 <c>xyz_d50_to_linear_srgb</c> 와 같은 값). XYZ/D50
    /// 비율을 그대로 RGB 배율로 쓰던 앞 판은 따뜻한 용지의 색조를 노랑 쪽으로 틀었습니다.
    /// </summary>
    private static readonly double[,] XyzD50ToLinearSrgb =
    {
        { 3.133856368, -1.61686677, -0.490614773 },
        { -0.978768563, 1.916141553, 0.033454116 },
        { 0.071945168, -0.228991277, 1.405242674 },
    };

    private static double[] LinearSrgb(double[] xyz, double ceiling)
    {
        double[] rgb = new double[3];
        for (int row = 0; row < 3; ++row)
        {
            double value = (XyzD50ToLinearSrgb[row, 0] * xyz[0]) +
                (XyzD50ToLinearSrgb[row, 1] * xyz[1]) +
                (XyzD50ToLinearSrgb[row, 2] * xyz[2]);
            rgb[row] = Math.Clamp(value, 0, ceiling);
        }
        return rgb;
    }

    /// <summary>
    /// 프로파일의 매체 흰색과 잉크 검정입니다. macOS
    /// <c>SoftProof.mediaTags(fromICCData:)</c> + <c>paperWhiteRGB</c> · <c>blackInkRGB</c> 를
    /// 그대로 옮긴 것입니다.
    /// </summary>
    /// <remarks>
    /// 태그 표를 직접 걷습니다. 시스템 판독기에 맡기면 인화소가 주는 <b>표(LUT) 기반</b>
    /// 프로파일에서 아무것도 돌려주지 않아, 프로파일을 걸어도 용지와 사진이 그대로였습니다.
    /// </remarks>
    public static (double[] White, double[] Black)? ReadMedia(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }
        byte[] data;
        try
        {
            data = File.ReadAllBytes(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
        return ReadMedia(data);
    }

    /// <summary>같은 판독을 바이트에서 합니다.</summary>
    public static (double[] White, double[] Black)? ReadMedia(ReadOnlySpan<byte> data)
    {
        if (data.Length < 132)
        {
            return null;
        }
        long count = ReadUInt32(data, 128);
        if (count < 0 || data.Length < 132 + (count * 12))
        {
            return null;
        }
        double[]? white = null;
        double[]? black = null;
        double[]? red = null;
        double[]? green = null;
        double[]? blue = null;
        var signatures = new HashSet<string>(StringComparer.Ordinal);
        for (int index = 0; index < count; ++index)
        {
            int entry = 132 + (index * 12);
            string signature = System.Text.Encoding.ASCII.GetString(data.Slice(entry, 4));
            long offset = ReadUInt32(data, entry + 4);
            long size = ReadUInt32(data, entry + 8);
            if (size <= 0 || offset + size > data.Length)
            {
                continue;
            }
            signatures.Add(signature);
            if (size < 20)
            {
                continue;
            }
            switch (signature)
            {
                case "wtpt":
                    white = ReadXyz(data, (int)offset);
                    break;
                case "bkpt":
                    black = ReadXyz(data, (int)offset);
                    break;
                case "rXYZ":
                    red = ReadXyz(data, (int)offset);
                    break;
                case "gXYZ":
                    green = ReadXyz(data, (int)offset);
                    break;
                case "bXYZ":
                    blue = ReadXyz(data, (int)offset);
                    break;
                default:
                    continue;
            }
        }
        // ICC v2 행렬/TRC 프로파일은 `wtpt` 에 적응하지 않은 흰색(D65)을 적어도 됩니다. 그대로
        // D50 으로 나누면 프루프가 파랗게 물듭니다. 행렬/TRC RGB 프로파일은 색소 합, 곧 정의상
        // PCS 흰색을 씁니다 — 네이티브 `color::read_soft_proof_media`, macOS
        // `SoftProof.mediaTags` 와 같은 규칙입니다. 인화소 LUT 프로파일은 그대로 `wtpt` 입니다.
        bool matrixTrc =
            System.Text.Encoding.ASCII.GetString(data.Slice(16, 4)) == "RGB " &&
            signatures.IsSupersetOf(["rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC"]);
        if (matrixTrc && red is not null && green is not null && blue is not null)
        {
            white = [red[0] + green[0] + blue[0], red[1] + green[1] + blue[1], red[2] + green[2] + blue[2]];
        }
        if (white is null && black is null)
        {
            return null;
        }
        return (
            // macOS: 흰색은 [0, 1.2], 검정은 [0, 0.3] 으로 묶고 1e-3 안이면 맞춤.
            white is null ? [1, 1, 1] : Snap(LinearSrgb(white, 1.2), 1),
            black is null ? [0, 0, 0] : Snap(LinearSrgb(black, 0.3), 0));
    }

    /// <summary>
    /// 색소 합은 s15Fixed16 반올림 때문에 D50 에서 2e-4 안쪽으로 어긋납니다. 세 채널이 모두
    /// 1e-3 안이면 정확한 값으로 맞춥니다(네이티브 `soft_proof_neutral_tolerance`).
    /// </summary>
    private static double[] Snap(double[] channels, double reference) =>
        channels.All(channel => Math.Abs(channel - reference) <= 1.0e-3)
            ? [reference, reference, reference]
            : channels;

    private static double[]? ReadXyz(ReadOnlySpan<byte> data, int offset)
    {
        if (offset + 20 > data.Length ||
            !System.Text.Encoding.ASCII.GetString(data.Slice(offset, 4))
                .Equals("XYZ ", StringComparison.Ordinal))
        {
            return null;
        }
        return
        [
            ReadS15Fixed16(data, offset + 8),
            ReadS15Fixed16(data, offset + 12),
            ReadS15Fixed16(data, offset + 16),
        ];
    }

    private static long ReadUInt32(ReadOnlySpan<byte> data, int offset) =>
        ((long)data[offset] << 24) | ((long)data[offset + 1] << 16) |
        ((long)data[offset + 2] << 8) | data[offset + 3];

    private static double ReadS15Fixed16(ReadOnlySpan<byte> data, int offset)
    {
        long raw = ReadUInt32(data, offset);
        if (raw >= 2147483648L)
        {
            raw -= 4294967296L;
        }
        return raw / 65536.0;
    }
}
