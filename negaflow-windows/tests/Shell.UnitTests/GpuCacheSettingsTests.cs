using Negaflow.Interop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// GPU 메모리 캐시 설정의 시험입니다.
/// </summary>
/// <remarks>
/// 여기 있는 것들은 **실제로 났던 잘못**을 고정한 것입니다 — 첫 판에서 슬라이더 상·하한에
/// <c>512MB</c>·<c>32GB</c> 라는 바이트 상수를 박았습니다. VRAM 이 다른 기계에서는 그대로
/// 거짓말이 되고, 저장된 값이 GPU 를 바꾼 뒤 조용히 깎입니다.
/// </remarks>
internal static class GpuCacheSettingsTests
{
    private static GpuCacheInfo Discrete(ulong budgetGigabytes) => new(
        HasGpu: true,
        IsIntegrated: false,
        AdapterDescription: "test",
        DedicatedVideoMemoryBytes: budgetGigabytes * 1024UL * 1024UL * 1024UL,
        VideoMemoryBudgetBytes: budgetGigabytes * 1024UL * 1024UL * 1024UL,
        AutomaticLimitBytes: budgetGigabytes * 1024UL * 1024UL * 1024UL * 60UL / 100UL,
        EffectiveLimitBytes: budgetGigabytes * 1024UL * 1024UL * 1024UL * 60UL / 100UL,
        ResidentBytes: 0UL);

    internal static void Run()
    {
        const ulong gigabyte = 1024UL * 1024UL * 1024UL;

        // 상·하한이 기계 용량을 따라갑니다. 큰 카드면 둘 다 커집니다.
        GpuCacheInfo small = Discrete(4UL);
        GpuCacheInfo large = Discrete(24UL);
        int smallMaximum = GpuCacheSettings.MaximumMegabytesFor(small, 16UL * gigabyte);
        int largeMaximum = GpuCacheSettings.MaximumMegabytesFor(large, 16UL * gigabyte);
        Check(smallMaximum == 4 * 1024, "4GB 카드의 상한은 4GB");
        Check(largeMaximum == 24 * 1024, "24GB 카드의 상한은 24GB");
        Check(
            GpuCacheSettings.MinimumMegabytesFor(small, 16UL * gigabyte) <
                GpuCacheSettings.MinimumMegabytesFor(large, 16UL * gigabyte),
            "하한도 기계를 따라갑니다");
        Check(
            GpuCacheSettings.MinimumMegabytesFor(small, 16UL * gigabyte) %
                GpuCacheSettings.StepMegabytes == 0,
            "하한은 눈금에 맞습니다");

        // 내장은 VRAM 이 시스템 RAM 이므로 설치 RAM 에서 상한을 잡습니다.
        GpuCacheInfo integrated = Discrete(0UL) with { IsIntegrated = true };
        Check(
            GpuCacheSettings.MaximumMegabytesFor(integrated, 32UL * gigabyte) == 8 * 1024,
            "내장 상한은 설치 RAM 의 1/4");

        // 자동은 엔진이 준 값을 그대로 씁니다 - 셸이 다시 계산하지 않습니다.
        Check(
            GpuCacheSettings.AutomaticMegabytes(large) ==
                (int)(large.AutomaticLimitBytes / (1024UL * 1024UL)),
            "자동값은 엔진 값 그대로");

        // 자동 모드는 엔진에 0 을 겁니다 - 셸이 잡은 값을 밀어 넣으면 GPU 를 바꿨을 때
        // 예전 기계의 값이 그대로 걸립니다.
        GpuCacheSettings automatic = new();
        Check(automatic.LimitBytesToApply() == 0L, "자동은 0 을 겁니다");
        GpuCacheSettings manual = new()
        {
            Mode = GpuCacheMode.Manual,
            ManualMegabytes = 2048,
        };
        Check(
            manual.LimitBytesToApply() == 2048L * 1024L * 1024L,
            "수동은 고른 값을 그대로 겁니다");
        Check(
            (manual with { Mode = GpuCacheMode.Automatic }).LimitBytesToApply() == 0L,
            "수동값이 남아 있어도 자동이면 0");

        // 정규화는 **음수만** 거릅니다. 기계 용량을 모르는 자리에서 상수로 자르면
        // GPU 를 바꾼 뒤 저장값이 조용히 깎입니다.
        Check(
            (manual with { ManualMegabytes = -5 }).Normalize().ManualMegabytes == 0,
            "음수는 저장값 없음으로");
        Check(
            (manual with { ManualMegabytes = 65536 }).Normalize().ManualMegabytes == 65536,
            "큰 값도 정규화가 자르지 않습니다");

        // 되돌리기는 지금 자동값으로 갑니다.
        Check(
            manual.ResetManualToAutomatic(large).ManualMegabytes ==
                GpuCacheSettings.AutomaticMegabytes(large),
            "되돌리면 자동값");
    }
}
