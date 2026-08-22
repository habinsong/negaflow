using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeFrameCacheLimitsV1
{
    internal uint StructSize;
    internal uint CleanedRawFrames;
    internal uint DevelopedFrames;
}

/// <summary>
/// 설정 창 "메모리 캐시" 가 고른 상주 한도를 엔진 안의 두 캐시에 겁니다.
/// </summary>
/// <remarks>
/// <para>
/// 엔진은 디코드한 원본(macOS <c>cleanedRawImage</c>)과 프리뷰 raw 프록시(macOS
/// <c>developed</c> 몫)를 프로세스 안에 상주시킵니다. 그 두 캐시는 오랫동안 <b>설치 메모리만</b>
/// 보고 예산을 정했습니다 — 설정에서 자동·수동을 바꾸고 프레임 수를 올려도 엔진 쪽은 아무 것도
/// 달라지지 않았고, 바뀌는 것은 managed <c>ThumbnailService</c> 의 표시본 캐시뿐이었습니다.
/// </para>
/// <para>
/// macOS 는 <c>FrameCacheResidencyStore.onLimitsChange</c> 가 <c>FrameCacheManager</c> 에
/// 곧바로 한도를 겁니다. 이 형식이 Windows 에서 같은 일을 하는 자리입니다. 단위도 macOS 와 같은
/// <b>프레임 수</b>이며, 프레임 하나의 값(190MB · 170MB)은 엔진이 macOS 와 같은 상수로 셉니다.
/// </para>
/// </remarks>
public static class FrameCacheLimitsBridge
{
    /// <summary>
    /// 한도를 겁니다. 둘 다 0 이면 엔진이 자동으로 돌아갑니다.
    /// </summary>
    /// <returns>
    /// 걸었으면 <see langword="true"/>. 엔진을 못 불렀으면 <see langword="false"/> 이며,
    /// 그 경우 엔진은 자동 예산으로 계속 돕니다 — 캐시 상한 하나 때문에 앱을 세우지 않습니다.
    /// </returns>
    public static unsafe bool Apply(int cleanedRawFrames, int developedFrames)
    {
        NativeFrameCacheLimitsV1 raw = new()
        {
            StructSize = (uint)sizeof(NativeFrameCacheLimitsV1),
            CleanedRawFrames = (uint)Math.Max(0, cleanedRawFrames),
            DevelopedFrames = (uint)Math.Max(0, developedFrames),
        };
        try
        {
            return NativeLimits.nf_set_frame_cache_limits_v1(ref raw) == 0;
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        {
            return false;
        }
    }
}
