namespace Negaflow.Interop.ContractTests;

/// <summary>
/// 프로세스 기준 메모리 예산의 ABI 계약입니다.
/// </summary>
/// <remarks>
/// 구조체가 어긋나면 값이 조용히 밀려 읽힙니다 — 예산은 그 값으로 캐시를 자르므로, 밀린
/// 값 하나가 캐시를 통째로 굶기거나 상한을 통째로 풀어 버립니다. 여기서 보는 것은 값 자체가
/// 아니라 <b>서로 맞물리는 모양</b>입니다.
/// </remarks>
internal static class MemoryBudgetContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        if (MemoryReportBridge.TryRead() is not { } report)
        {
            context.Check(false, "memory_report_readable");
            return;
        }

        context.Check(report.ProcessPrivateBytes > 0UL, "memory_report_private_positive");
        context.Check(
            report.AutomaticProcessCeilingBytes > 0UL, "memory_report_ceiling_positive");
        context.Check(
            report.NonCacheOverheadBytes <= report.ProcessPrivateBytes,
            "memory_report_overhead_within_private");
        // 세 예산의 합이 상한을 넘으면 프로세스가 상한 안에 있을 수 없습니다.
        context.Check(
            report.DecodedSourceBudgetBytes + report.PreviewProxyBudgetBytes +
                report.DevelopedDisplayBudgetBytes <= report.AutomaticProcessCeilingBytes,
            "memory_report_budgets_within_ceiling");

        // 엔진 한도가 0/0 이어야 프로세스 기준 예산이 돕니다. 여기는 셸이 아직 아무 것도
        // 걸지 않은 상태이므로 자동이어야 합니다.
        context.Check(
            report is { EngineCleanedRawFrames: 0U, EngineDevelopedFrames: 0U },
            "memory_report_engine_limits_start_automatic");

        // 표시본 캐시가 많이 들고 있다고 알리면 남는 예산이 줄어야 합니다.
        ulong? idle = DisplayCacheBudgetBridge.Sync(0L);
        ulong? crowded = DisplayCacheBudgetBridge.Sync(
            (long)(report.AutomaticProcessCeilingBytes / 2UL));
        context.Check(idle is > 0UL, "display_cache_budget_positive");
        context.Check(
            idle is { } free && crowded is { } tight && tight <= free,
            "display_cache_budget_shrinks_when_crowded");
        _ = DisplayCacheBudgetBridge.Sync(0L);

        GpuCacheInfo? gpu = GpuCacheBridge.TryRead();
        context.Check(gpu is not null, "gpu_cache_info_readable");
        if (gpu is { HasGpu: true } info)
        {
            context.Check(info.AutomaticLimitBytes > 0UL, "gpu_cache_automatic_positive");
            context.Check(
                info.AdapterDescription.Length > 0, "gpu_cache_adapter_named");
            context.Check(GpuCacheBridge.Apply(0L), "gpu_cache_limit_applies");
        }
    }
}
