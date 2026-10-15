using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeNeutralWhiteBalancePickV1
{
    internal uint StructSize;
    internal uint Status;
    internal double ReferenceRed;
    internal double ReferenceGreen;
    internal double ReferenceBlue;
    internal double Warmth;
    internal double Tint;
}

/// <summary>중립 스포이드의 결과입니다.</summary>
public enum NeutralWhiteBalancePickOutcome
{
    /// <summary>찍은 점을 중립으로 만드는 온도·틴트를 얻었습니다.</summary>
    Picked,

    /// <summary>현상하지 못했습니다.</summary>
    Unavailable,

    /// <summary>그 점은 너무 어둡거나 클리핑에 가까워 색을 믿을 수 없습니다.</summary>
    Rejected,
}

/// <summary>
/// 사용자가 캔버스에서 찍은 점을 무채색으로 만드는 온도·틴트입니다. macOS
/// <c>AppModel.pickNeutralWhiteBalance</c> 자리입니다.
/// </summary>
/// <remarks>
/// 값은 화면 정착 프리뷰와 같은 입력으로 색 모델 직전까지 현상한 화이트밸런스 입력에서 잽니다.
/// 그래서 지금 온도·틴트와 무관하게 같은 점은 같은 답입니다. <see cref="Warmth"/>·<see cref="Tint"/>
/// 는 룩 프리셋 몫까지 더한 <b>합</b>입니다 — 저장할 사용자 값은 프리셋 몫을 빼야 합니다.
/// </remarks>
public readonly record struct NeutralWhiteBalancePick(
    NeutralWhiteBalancePickOutcome Outcome,
    double Warmth,
    double Tint)
{
    /// <param name="unitX">변형 전 원본 정규 좌표(0…1).</param>
    /// <param name="unitY">변형 전 원본 정규 좌표(0…1, y 아래로).</param>
    public static unsafe NeutralWhiteBalancePick Sample(DevelopExportRequest request, double unitX, double unitY)
    {
        NativeNeutralWhiteBalancePickV1 raw = new() { StructSize = (uint)sizeof(NativeNeutralWhiteBalancePickV1) };
        DevelopExportResult result = NativeDevelopPreviewRender.Render(request, 0U, 0U, Span<byte>.Empty,
            null, null, null, neutralPick: &raw, pickX: unitX, pickY: unitY).Result;
        if (!result.Succeeded) { return new(NeutralWhiteBalancePickOutcome.Unavailable, 0, 0); }
        return raw.Status switch
        {
            0U when double.IsFinite(raw.Warmth) && double.IsFinite(raw.Tint) =>
                new(NeutralWhiteBalancePickOutcome.Picked, raw.Warmth, raw.Tint),
            2U => new(NeutralWhiteBalancePickOutcome.Rejected, 0, 0),
            _ => new(NeutralWhiteBalancePickOutcome.Unavailable, 0, 0),
        };
    }
}
