using System.Runtime.InteropServices;
using System.Text;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 이 프로세스가 커밋한 private 영역을 <b>크기별로</b> 셉니다.
/// </summary>
/// <remarks>
/// 총량만 보면 "무엇이 들고 있는가" 를 못 가립니다. 화상 버퍼는 크기가 `가로×세로×바이트`
/// 로 딱 떨어지므로, 크기 히스토그램을 보면 어느 버퍼가 몇 장 살아 있는지 바로 드러납니다 —
/// 설치 앱에서 133MB 영역 29개가 3.6GB 를 먹고 있던 것을 이 방법으로 찾았습니다.
/// </remarks>
internal static class ProcessRegionMap
{
    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryBasicInformation
    {
        internal IntPtr BaseAddress;
        internal IntPtr AllocationBase;
        internal uint AllocationProtect;
        internal ushort PartitionId;
        internal IntPtr RegionSize;
        internal uint State;
        internal uint Protect;
        internal uint Type;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr VirtualQuery(
        IntPtr address, out MemoryBasicInformation buffer, IntPtr length);

    private const uint Committed = 0x1000;
    private const uint PrivateType = 0x20000;
    private const uint WriteCombine = 0x400;

    internal static string Report(long thresholdBytes = 32L * 1024L * 1024L)
    {
        SortedDictionary<long, (int Count, long Bytes)> buckets = [];
        long address = 0;
        long total = 0;
        long writeCombine = 0;
        IntPtr length = Marshal.SizeOf<MemoryBasicInformation>();
        while (address < 0x7FFFFFFF0000L)
        {
            if (VirtualQuery((IntPtr)address, out MemoryBasicInformation info, length) == 0)
            {
                break;
            }
            long size = info.RegionSize.ToInt64();
            if (size <= 0)
            {
                break;
            }
            if (info.State == Committed && info.Type == PrivateType)
            {
                total += size;
                if ((info.Protect & WriteCombine) != 0)
                {
                    writeCombine += size;
                }
                if (size >= thresholdBytes)
                {
                    long megabytes = size / (1024L * 1024L);
                    (int count, long bytes) = buckets.TryGetValue(megabytes, out var seen)
                        ? seen
                        : (0, 0L);
                    buckets[megabytes] = (count + 1, bytes + size);
                }
            }
            address += size;
        }

        StringBuilder text = new();
        text.AppendLine($"private 커밋 합계 {total / 1048576.0:N0} MB " +
            $"(write-combine {writeCombine / 1048576.0:N0} MB)");
        long large = 0;
        int regions = 0;
        foreach ((long megabytes, (int count, long bytes)) in buckets)
        {
            text.AppendLine($"  {megabytes,6} MB x {count,3} = {bytes / 1048576.0,8:N0} MB");
            large += bytes;
            regions += count;
        }
        text.AppendLine(
            $"  {thresholdBytes / 1048576} MB 이상 합계 {large / 1048576.0:N0} MB, 영역 {regions}개");
        return text.ToString().TrimEnd();
    }
}
