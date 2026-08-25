using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeMemoryReportV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal ulong ProcessPrivateBytes;
    internal ulong DecodedSourceResidentBytes;
    internal ulong DecodedSourceBudgetBytes;
    internal ulong PreviewProxyResidentBytes;
    internal ulong PreviewProxyBudgetBytes;
    internal ulong DevelopedDisplayResidentBytes;
    internal ulong DevelopedDisplayBudgetBytes;
    internal ulong GpuPoolResidentBytes;
    internal ulong GpuPoolLimitBytes;
    internal ulong GpuSystemMemoryBytes;
    internal ulong NonCacheOverheadBytes;
    internal ulong AutomaticProcessCeilingBytes;
}

/// <summary>지금 이 프로세스의 메모리 내역입니다.</summary>
/// <remarks>
/// 캐시가 저마다 자기 예산 안에 있어도 프로세스 총량은 상한을 넘을 수 있습니다 — 실측으로
/// 31.8GB 기계에서 자동 상한 8.27GB 인데 앱은 8.77GB 였고, 그 차이는 코드(432MB)·런타임·
/// WinUI·D3D11 스테이징(297MB) 처럼 <b>어느 예산에도 없던 몫</b>이었습니다. 그 몫을 눈으로
/// 봐야 예산이 제대로 도는지 판정할 수 있습니다.
/// </remarks>
public readonly record struct MemoryReport(
    ulong ProcessPrivateBytes,
    ulong DecodedSourceResidentBytes,
    ulong DecodedSourceBudgetBytes,
    ulong PreviewProxyResidentBytes,
    ulong PreviewProxyBudgetBytes,
    ulong DevelopedDisplayResidentBytes,
    ulong DevelopedDisplayBudgetBytes,
    ulong GpuPoolResidentBytes,
    ulong GpuPoolLimitBytes,
    ulong GpuSystemMemoryBytes,
    ulong NonCacheOverheadBytes,
    ulong AutomaticProcessCeilingBytes);

public static class MemoryReportBridge
{
    public static unsafe MemoryReport? TryRead()
    {
        NativeMemoryReportV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeMemoryReportV1);
        try
        {
            if (NativeLimits.nf_get_memory_report_v1(ref raw) != 0)
            {
                return null;
            }
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }
        return new MemoryReport(
            raw.ProcessPrivateBytes,
            raw.DecodedSourceResidentBytes,
            raw.DecodedSourceBudgetBytes,
            raw.PreviewProxyResidentBytes,
            raw.PreviewProxyBudgetBytes,
            raw.DevelopedDisplayResidentBytes,
            raw.DevelopedDisplayBudgetBytes,
            raw.GpuPoolResidentBytes,
            raw.GpuPoolLimitBytes,
            raw.GpuSystemMemoryBytes,
            raw.NonCacheOverheadBytes,
            raw.AutomaticProcessCeilingBytes);
    }
}
