using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// <see cref="MemoryStressDiagnostics"/> 의 <b>한 프레임을 지나는 부분</b>과 보고입니다.
/// </summary>
/// <remarks>
/// 재는 쪽(<c>RunSize</c>)과 나눠 둡니다 — 한 파일이 500줄을 넘으면 어느 쪽을 고치는지
/// 눈으로 못 가립니다.
/// </remarks>
internal static partial class MemoryStressDiagnostics
{
    /// <summary>한 프레임이 실제 앱에서 지나는 여섯 경로를 그대로 지납니다.</summary>
    private static void ExerciseOneFrame(
        PumpDispatcher dispatcher,
        LibraryHostService host,
        ThumbnailService thumbnails,
        PreviewCoordinator coordinator,
        DevelopPanelState panel,
        LibraryFrameSnapshot frame,
        int index,
        string paths)
    {
        // ② 라이브러리뷰 썸네일
        //
        // **결과가 나올 때까지 기다립니다.** `WaitUntilIdleAsync` 는 디스크 큐만 기다리므로
        // 그것만 믿으면 렌더가 끝나기 전에 다음 장으로 넘어가고, 캐시가 비어 있어 다음
        // 바퀴가 전부 다시 그립니다 - 그러면 제품이 아니라 시험이 새는 것을 재게 됩니다.
        if (paths.Contains('t', StringComparison.Ordinal))
        {
            thumbnails.Request(frame);
            WaitFor("library-thumbnail", frame.Id, () => thumbnails.TryGet(frame.Id) is not null);
        }
        // ④ 현상뷰·인화뷰 developed 프록시
        if (paths.Contains('d', StringComparison.Ordinal))
        {
            thumbnails.RequestDeveloped(frame, 2048);
            WaitFor(
                "developed-proxy", frame.Id, () => thumbnails.TryGetDeveloped(frame, out _));
        }
        // ③ 현상뷰 프리뷰 (정착까지 기다립니다)
        if (paths.Contains('p', StringComparison.Ordinal))
        {
            GrainMendPreviewLatency latency =
                GrainMendPreviewLatencyProbe.Measure(dispatcher, coordinator, frame);
            if (latency.Failure is { Length: > 0 } failure)
            {
                Console.Error.WriteLine($"preview refused {frame.Id}: {failure}");
            }
        }
        // ⑥ 현상 프로세스와 현상 타깃 - 두 장에 한 번씩 바꿉니다.
        if (paths.Contains('r', StringComparison.Ordinal) && panel.Select(frame.Id))
        {
            _ = panel.SetDevelopmentProcess(
                (index % 2) == 0 ? DevelopmentProcess.C41 : DevelopmentProcess.E6);
            _ = DevelopDefaultsCommands.ApplyTarget(
                host,
                frame,
                (index % 3) switch
                {
                    0 => DevelopTarget.Main,
                    1 => DevelopTarget.Noritsu,
                    _ => DevelopTarget.Sp3000,
                });
        }
        // ⑤ 인화뷰 투영
        if (paths.Contains('n', StringComparison.Ordinal))
        {
            _ = PrintSourceSelection.Eligible(host.Frames).Count;
        }
        thumbnails.WaitUntilIdleAsync().GetAwaiter().GetResult();
    }

    /// <summary>조건이 참이 될 때까지 기다립니다. 시간이 지나면 그대로 진행합니다.</summary>
    /// <summary>엔진이 보는 메모리 내역입니다. 사람이 읽을 줄로 냅니다.</summary>
    internal static string MemoryReportText()
    {
        Negaflow.Interop.MemoryReport? report = Negaflow.Interop.MemoryReportBridge.TryRead();
        if (report is not { } value)
        {
            return "memory report unavailable";
        }
        Negaflow.Interop.GpuCacheInfo? gpu = Negaflow.Interop.GpuCacheBridge.TryRead();
        static string Mb(ulong bytes) => $"{bytes / (1024.0 * 1024.0):N0} MB";
        System.Text.StringBuilder text = new();
        text.AppendLine($"프로세스 private       {Mb(value.ProcessPrivateBytes)}");
        text.AppendLine($"자동 상한(프로세스)    {Mb(value.AutomaticProcessCeilingBytes)}");
        text.AppendLine(
            $"  디코드 원본          {Mb(value.DecodedSourceResidentBytes)} / " +
            $"{Mb(value.DecodedSourceBudgetBytes)}");
        text.AppendLine(
            $"  프리뷰 프록시        {Mb(value.PreviewProxyResidentBytes)} / " +
            $"{Mb(value.PreviewProxyBudgetBytes)}");
        text.AppendLine(
            $"  현상본 표시(managed) {Mb(value.DevelopedDisplayResidentBytes)} / " +
            $"{Mb(value.DevelopedDisplayBudgetBytes)}");
        text.AppendLine(
            $"  GPU 작업 텍스처      {Mb(value.GpuPoolResidentBytes)} / " +
            $"{Mb(value.GpuPoolLimitBytes)}");
        text.AppendLine(
            $"  GPU 스테이징(RAM)    {Mb(value.GpuSystemMemoryBytes)}  " +
            "(아래 '캐시 아닌 몫' 에 포함)");
        text.AppendLine($"  캐시 아닌 몫         {Mb(value.NonCacheOverheadBytes)}");
        if (gpu is { HasGpu: true } info)
        {
            text.AppendLine(
                $"GPU {info.AdapterDescription} " +
                $"{(info.IsIntegrated ? "내장" : "외장")} " +
                $"VRAM {Mb(info.DedicatedVideoMemoryBytes)} " +
                $"DXGI예산 {Mb(info.VideoMemoryBudgetBytes)} " +
                $"자동한도 {Mb(info.AutomaticLimitBytes)}");
        }
        else
        {
            text.AppendLine("GPU 없음");
        }
        return text.ToString().TrimEnd();
    }

    // 기다리다 못 받으면 **어느 경로가** 못 끝냈는지 남깁니다. 앞 판은 조용히 120초를
    // 흘려보내서, 48MP 가 멈춘 것인지 느린 것인지 구별할 수 없었습니다.
    private static void WaitFor(string what, string frameId, Func<bool> ready)
    {
        System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
        while (!ready() && clock.Elapsed < TimeSpan.FromSeconds(120))
        {
            Thread.Sleep(5);
        }
        if (!ready())
        {
            Console.Error.WriteLine(
                $"[대기 실패] {what} {frameId} {clock.Elapsed.TotalSeconds:N0}초");
        }
    }

    private sealed class StressThumbnailCodec : IThumbnailCodec
    {
        public byte[]? EncodeJpeg(byte[] bgra, int width, int height) => [0xFF, 0xD8];
    }

    private static long PrivateBytes()
    {
        using System.Diagnostics.Process process =
            System.Diagnostics.Process.GetCurrentProcess();
        process.Refresh();
        return process.PrivateMemorySize64;
    }

    private static void TryDeleteTree(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }
}
