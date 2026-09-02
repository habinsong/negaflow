using Negaflow.Interop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 셸이 엔진에 <b>무엇을</b> 거는지의 시험입니다.
/// </summary>
/// <remarks>
/// <para>
/// 이것이 설치 앱이 자동 상한을 뚫던 진짜 원인이었습니다. 셸이 자동 모드에서도 자기가
/// 계산한 장수(이 기계에서 16 / 32)를 엔진에 걸었고, 엔진은 0 이 아니면 "사용자가 고른 값"
/// 으로 보고 <c>장수 × 190MB</c> 로만 예산을 잡습니다 — 그 길에는 "프로세스 private 에서
/// 캐시 몫을 뺀 간접비" 차감이 없습니다. 실측으로 앱이 9.7GB 까지 갔습니다.
/// </para>
/// <para>
/// 그래서 <b>자동이면 0</b> 이어야 합니다. 0 이 "엔진이 알아서" 입니다.
/// </para>
/// </remarks>
internal static class FrameCacheEngineLimitsTests
{
    internal static void Run()
    {
        if (!File.Exists(Path.Combine(AppContext.BaseDirectory, "Negaflow.Native.dll")))
        {
            return;
        }

        string root = Path.Combine(
            Path.GetTempPath(), "negaflow-engine-limits-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            using PumpDispatcher dispatcher = new();
            ThumbnailService cache = new(
                new NativeDevelopExporterAdapter(),
                new EngineLimitsCodec(),
                dispatcher,
                Path.Combine(root, "Thumbnails"));

            cache.ApplyResidencySettings(new FrameCacheResidencySettings());
            MemoryReport? automatic = MemoryReportBridge.TryRead();
            Check(automatic is not null, "엔진 메모리 보고를 읽습니다");
            Check(
                automatic is { EngineCleanedRawFrames: 0U, EngineDevelopedFrames: 0U },
                "자동이면 엔진에 0 을 겁니다");
            Check(
                automatic is { } a && a.DecodedSourceBudgetBytes + a.PreviewProxyBudgetBytes +
                    a.DevelopedDisplayBudgetBytes <= a.AutomaticProcessCeilingBytes,
                "자동 예산 합계는 프로세스 상한 안입니다");

            cache.ApplyResidencySettings(new FrameCacheResidencySettings
            {
                Mode = FrameCacheResidencyMode.Manual,
                ManualCleanedRaw = 5,
                ManualDeveloped = 9,
            });
            MemoryReport? manual = MemoryReportBridge.TryRead();
            Check(
                manual is { EngineCleanedRawFrames: 5U, EngineDevelopedFrames: 9U },
                "수동이면 고른 장수를 그대로 겁니다");

            // 다른 시험이 이어 돌므로 자동으로 되돌립니다.
            cache.ApplyResidencySettings(new FrameCacheResidencySettings());
            cache.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
        finally
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
            }
        }
    }

    private sealed class EngineLimitsCodec : IThumbnailCodec
    {
        public byte[]? EncodeJpeg(byte[] bgra, int width, int height) => [0xFF, 0xD8];
    }
}
