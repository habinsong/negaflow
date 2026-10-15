using System;

namespace Negaflow.Interop;

/// <summary>
/// 자동 보정이 제안하는 현상 설정입니다.
/// </summary>
/// <remarks>
/// 현재 값에 **더하는 것이 아니라 대입**합니다. 그래서 두 번 눌러도 한 번 누른 것과 결과가
/// 같습니다. 모든 값은 엔진이 받아들이는 범위 안이므로 호출자가 clamp 할 필요가 없습니다.
/// </remarks>
public sealed class AutoAdjustSettings
{
    /// <summary>
    /// 값 운반자이므로 공개 생성자를 둡니다 — 셸이 자동 보정 적용 규칙을 네이티브 엔진 없이
    /// 시험할 수 있어야 합니다.
    /// </summary>
    public AutoAdjustSettings(
        double exposure,
        double contrast,
        double highlights,
        double shadows,
        double whites,
        double blacks,
        double density,
        double vibrance,
        double warmth,
        double tint)
    {
        Exposure = exposure;
        Contrast = contrast;
        Highlights = highlights;
        Shadows = shadows;
        Whites = whites;
        Blacks = blacks;
        Density = density;
        Vibrance = vibrance;
        Warmth = warmth;
        Tint = tint;
    }

    public double Exposure { get; }

    public double Contrast { get; }

    /// <summary>복구 전용이라 항상 0 이하입니다.</summary>
    public double Highlights { get; }

    /// <summary>복구 전용이라 항상 0 이상입니다.</summary>
    public double Shadows { get; }

    public double Whites { get; }

    public double Blacks { get; }

    public double Density { get; }

    /// <summary>올리기만 합니다.</summary>
    public double Vibrance { get; }

    public double Warmth { get; }

    public double Tint { get; }
}

/// <summary>
/// 중립 현상본을 읽어 자동 보정 값을 계산합니다.
/// </summary>
public static unsafe class NativeAutoAdjust
{
    private const uint StatusOk = 0;
    private const uint StatusInvalidArgument = 1;
    private const uint StatusStructTooSmall = 2;

    /// <summary>
    /// <paramref name="pixels"/> 는 <see cref="NativeDevelopExporter.Preview"/> 가 채운
    /// BGRA8 비트맵입니다 — 셸이 이미 그릴 줄 아는 것을 그대로 넘깁니다.
    /// </summary>
    /// <remarks>
    /// 톤 슬라이더를 0 으로 둔 **중립 현상본**을 넘겨야 합니다. 이미 보정이 들어간 그림을
    /// 넘기면 그 위에 다시 보정을 얹는 값이 나옵니다.
    /// </remarks>
    public static AutoAdjustSettings Compute(
        ReadOnlySpan<byte> pixels,
        uint width,
        uint height)
    {
        uint strideBytes = CheckBitmap(pixels, width, height);
        NativeAutoAdjustResultV1 raw = Empty();
        uint status;
        fixed (byte* buffer = pixels)
        {
            status = NativeAutoAdjustEntry.nf_auto_adjust_v1(buffer, width, height, strideBytes, &raw);
        }
        ThrowOnFailure(status, "nf_auto_adjust_v1");
        return ToSettings(raw);
    }

    /// <summary>
    /// <see cref="Compute(ReadOnlySpan{byte}, uint, uint)"/> 와 같되 필름 종류를 받습니다. 자동 톤은
    /// 노출 뒤 백분위를 엔진과 같은 노출 숄더로 예측하는데, 숄더의 헤드룸이 흑백 네거티브만 다릅니다.
    /// </summary>
    public static AutoAdjustSettings Compute(
        ReadOnlySpan<byte> pixels,
        uint width,
        uint height,
        bool blackAndWhiteNegative)
    {
        uint strideBytes = CheckBitmap(pixels, width, height);
        NativeAutoAdjustResultV1 raw = Empty();
        uint status;
        fixed (byte* buffer = pixels)
        {
            status = NativeAutoAdjustEntry.nf_auto_adjust_v2(
                buffer, width, height, strideBytes, blackAndWhiteNegative ? 1U : 0U, &raw);
        }
        ThrowOnFailure(status, "nf_auto_adjust_v2");
        return ToSettings(raw);
    }

    /// <summary>
    /// 자동 톤 폐루프 한 번입니다. <paramref name="first"/> 를 프레임의 나머지 설정과 함께 실제로
    /// 적용해 렌더한 비트맵을 넘기면, 노출(밝힌 경우만)과 화이트를 바로잡은 값을 돌려줍니다. 나머지
    /// 값은 <paramref name="first"/> 그대로입니다.
    /// </summary>
    public static AutoAdjustSettings Refine(
        ReadOnlySpan<byte> pixels,
        uint width,
        uint height,
        bool blackAndWhiteNegative,
        AutoAdjustSettings first)
    {
        ArgumentNullException.ThrowIfNull(first);
        uint strideBytes = CheckBitmap(pixels, width, height);
        NativeAutoAdjustResultV1 given = Empty();
        given.Exposure = first.Exposure;
        given.Contrast = first.Contrast;
        given.Highlights = first.Highlights;
        given.Shadows = first.Shadows;
        given.Whites = first.Whites;
        given.Blacks = first.Blacks;
        given.Density = first.Density;
        given.Vibrance = first.Vibrance;
        given.Warmth = first.Warmth;
        given.Tint = first.Tint;
        NativeAutoAdjustResultV1 raw = Empty();
        uint status;
        fixed (byte* buffer = pixels)
        {
            status = NativeAutoAdjustEntry.nf_auto_tone_refine_v1(
                buffer, width, height, strideBytes, blackAndWhiteNegative ? 1U : 0U, &given, &raw);
        }
        ThrowOnFailure(status, "nf_auto_tone_refine_v1");
        return ToSettings(raw);
    }

    private static uint CheckBitmap(ReadOnlySpan<byte> pixels, uint width, uint height)
    {
        ArgumentOutOfRangeException.ThrowIfZero(width);
        ArgumentOutOfRangeException.ThrowIfZero(height);
        uint strideBytes = checked(width * 4U);
        if (pixels.Length < (long)strideBytes * height)
        {
            throw new ArgumentException(
                "The bitmap is smaller than the stated dimensions.",
                nameof(pixels));
        }
        return strideBytes;
    }

    private static NativeAutoAdjustResultV1 Empty()
    {
        NativeAutoAdjustResultV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeAutoAdjustResultV1);
        return raw;
    }

    private static void ThrowOnFailure(uint status, string entryPoint)
    {
        if (status == StatusOk)
        {
            return;
        }
        throw new NativeBootstrapException(
            NativeBootstrapFailure.NativeCallFailed,
            status switch
            {
                StatusInvalidArgument => $"{entryPoint} rejected the bitmap as malformed.",
                StatusStructTooSmall => $"{entryPoint} rejected the struct size.",
                _ => $"{entryPoint} failed with status {status}.",
            });
    }

    private static AutoAdjustSettings ToSettings(NativeAutoAdjustResultV1 raw) =>
        new(
            raw.Exposure,
            raw.Contrast,
            raw.Highlights,
            raw.Shadows,
            raw.Whites,
            raw.Blacks,
            raw.Density,
            raw.Vibrance,
            raw.Warmth,
            raw.Tint);
}
