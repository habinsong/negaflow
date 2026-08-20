using Negaflow.Shell;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// macOS <c>FrameCacheManager</c> · <c>FrameCacheBudget</c> · <c>FrameCachePolicy</c> 이식본의
/// 시험입니다.
/// </summary>
/// <remarks>
/// 이것이 없어서 <c>ThumbnailService.developed</c> 가 방문한 프레임의 전체 해상도 BGRA 를
/// 영구히 들고 있었습니다. 3600×2406 이면 프레임당 34.6MB 라, 사진을 옮겨 다니면 그대로
/// 쌓여 네이티브 할당이 실패하고 앱이 죽었습니다.
/// </remarks>
internal static class FrameResidencyTests
{
    public static void Run()
    {
        VerifyFifoEviction();
        VerifySelectedFrameIsNeverEvicted();
        VerifyBudgetMatchesMacOS();
    }

    private static void VerifyFifoEviction()
    {
        List<string> evicted = [];
        FrameResidency residency = new(limit: 3);
        foreach (string id in new[] { "a", "b", "c" })
        {
            residency.MarkResident(id, evicted.Add);
        }
        Check(evicted.Count == 0, "frame_residency_keeps_up_to_limit");

        residency.MarkResident("d", evicted.Add);
        Check(
            evicted.Count == 1 && evicted[0] == "a",
            "frame_residency_evicts_the_oldest_first");

        // macOS `markDevelopedResident` 는 FIFO **재등록**입니다 — 다시 쓴 것은 뒤로 갑니다.
        residency.MarkResident("b", evicted.Add);
        residency.MarkResident("e", evicted.Add);
        Check(
            evicted.Count == 2 && evicted[1] == "c",
            "frame_residency_re_registration_protects_the_reused_frame");
    }

    private static void VerifySelectedFrameIsNeverEvicted()
    {
        List<string> evicted = [];
        FrameResidency residency = new(limit: 2) { SelectedFrameId = "selected" };
        residency.MarkResident("selected", evicted.Add);
        residency.MarkResident("x", evicted.Add);
        residency.MarkResident("y", evicted.Add);
        residency.MarkResident("z", evicted.Add);
        Check(
            !evicted.Contains("selected"),
            "frame_residency_never_evicts_the_selected_frame");
        Check(
            evicted.Contains("x") && evicted.Contains("y"),
            "frame_residency_still_evicts_the_others");
    }

    private static void VerifyBudgetMatchesMacOS()
    {
        // macOS FrameCacheBudget: 8GB 이하는 최소 한도(cleanedRaw 2 · developed 3).
        FrameCacheLimits small = FrameCacheBudget.AutomaticLimits(
            8UL * 1024UL * 1024UL * 1024UL);
        Check(
            small.CleanedRaw == FrameCacheBudget.MinimumCleanedRaw &&
                small.Developed == FrameCacheBudget.MinimumDeveloped,
            "frame_cache_budget_conservative_below_8gb");

        // 16GB 에서 25%, 16GB 늘 때마다 2.5%p, 96GB 이상에서 35% 로 멈춥니다.
        Check(
            Math.Abs(
                FrameCacheBudget.AutomaticMemoryFraction(16UL * 1024UL * 1024UL * 1024UL) -
                    FrameCacheBudget.AutomaticMinimumFraction) < 1e-9,
            "frame_cache_budget_fraction_is_25_percent_at_16gb");
        Check(
            Math.Abs(
                FrameCacheBudget.AutomaticMemoryFraction(96UL * 1024UL * 1024UL * 1024UL) -
                    FrameCacheBudget.AutomaticMaximumFraction) < 1e-9,
            "frame_cache_budget_fraction_stops_at_35_percent");
        Check(
            Math.Abs(
                FrameCacheBudget.AutomaticMemoryFraction(128UL * 1024UL * 1024UL * 1024UL) -
                    FrameCacheBudget.AutomaticMaximumFraction) < 1e-9,
            "frame_cache_budget_fraction_is_capped_above_96gb");

        // macOS FrameCachePolicy 의 압력 단계별 한도.
        FrameCachePolicy policy = new(new FrameCacheLimits(cleanedRaw: 6, developed: 12));
        FrameCacheLimits warning = policy.LimitsFor(FrameCachePressureLevel.Warning);
        Check(
            warning.CleanedRaw == 1 && warning.Developed == 2,
            "frame_cache_policy_warning_limits");
        FrameCacheLimits critical = policy.LimitsFor(FrameCachePressureLevel.Critical);
        Check(
            critical.CleanedRaw == 0 && critical.Developed == 1,
            "frame_cache_policy_critical_limits");
    }
}
