using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 배치가 여는 칸 수는 <b>기계에서 나와야</b> 합니다. 여기서 그 규칙을 못 박습니다.
/// </summary>
/// <remarks>
/// 특히 <b>램 8GB · 내장 그래픽</b> 노트북입니다. 그 기계는 앱의 프레임 캐시와 내장 GPU 의
/// 작업 텍스처가 <b>같은 8GB</b> 를 나눠 쓰므로, 칸을 하나만 더 열어도 스왑으로 갑니다.
/// 예전 규칙은 예약이 1GB 고정이라 코어가 여덟이면 세 칸을 열었습니다.
/// </remarks>
internal static class ExportConcurrencyTests
{
    private const ulong Gigabyte = 1024UL * 1024UL * 1024UL;

    private static GpuCacheInfo Gpu(bool hasGpu, bool integrated) =>
        new(hasGpu, integrated, "test", 0UL, 0UL, 0UL, 0UL, 0UL);

    public static void Run()
    {
        // 램 8GB · 내장 그래픽. 코어가 넷이든 여덟이든 한 칸입니다.
        Check(
            DevelopExportCoordinator.ResolveMaximumConcurrentExports(
                4, 8UL * Gigabyte, Gpu(hasGpu: true, integrated: true)) == 1,
            "8GB integrated laptop opens one export slot");
        Check(
            DevelopExportCoordinator.ResolveMaximumConcurrentExports(
                8, 8UL * Gigabyte, Gpu(hasGpu: true, integrated: true)) == 1,
            "more cores do not open more slots when the memory is not there");

        // GPU 를 아예 못 읽어도 같은 자리입니다 — 모르는 것을 근거로 칸을 늘리지 않습니다.
        Check(
            DevelopExportCoordinator.ResolveMaximumConcurrentExports(
                8, 8UL * Gigabyte, null) == 1,
            "an unreadable adapter is treated as no discrete GPU");

        // 설치 메모리를 못 읽으면 한 칸입니다.
        Check(
            DevelopExportCoordinator.ResolveMaximumConcurrentExports(
                16, 0UL, Gpu(hasGpu: true, integrated: false)) == 1,
            "unknown installed memory opens one slot");

        // 4GB 기계도 살아 있어야 합니다. 하한은 늘 한 칸입니다.
        Check(
            DevelopExportCoordinator.ResolveMaximumConcurrentExports(
                2, 4UL * Gigabyte, Gpu(hasGpu: true, integrated: true)) == 1,
            "a 4GB machine still exports, one at a time");

        // 램이 넉넉하고 전용 GPU 가 있으면 실측 최적인 네 칸까지 엽니다.
        Check(
            DevelopExportCoordinator.ResolveMaximumConcurrentExports(
                16, 32UL * Gigabyte, Gpu(hasGpu: true, integrated: false)) == 4,
            "a 32GB workstation with a discrete GPU opens four slots");

        // 코어가 적으면 램이 남아도 코어가 상한입니다.
        Check(
            DevelopExportCoordinator.ResolveMaximumConcurrentExports(
                4, 32UL * Gigabyte, Gpu(hasGpu: true, integrated: false)) == 2,
            "cores cap the slots when memory is plentiful");

        // 어떤 조합에서도 한 칸 아래로 내려가거나 네 칸 위로 올라가지 않습니다.
        foreach (int cores in new[] { 1, 2, 4, 8, 16, 32 })
        {
            foreach (ulong gigabytes in new[] { 2UL, 4UL, 8UL, 16UL, 32UL, 64UL, 128UL })
            {
                foreach (GpuCacheInfo? adapter in new GpuCacheInfo?[]
                {
                    null,
                    Gpu(hasGpu: false, integrated: false),
                    Gpu(hasGpu: true, integrated: true),
                    Gpu(hasGpu: true, integrated: false),
                })
                {
                    int slots = DevelopExportCoordinator.ResolveMaximumConcurrentExports(
                        cores, gigabytes * Gigabyte, adapter);
                    Check(
                        slots is >= 1 and <= 4,
                        $"slots stay in range for {cores} cores / {gigabytes}GB");
                }
            }
        }
    }
}
