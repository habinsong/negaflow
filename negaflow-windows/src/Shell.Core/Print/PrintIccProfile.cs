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
}
