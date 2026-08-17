using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// GrainMend 확정·영속성·preview 동일 recipe를 한 번에 실측합니다. 실제 스캔으로 검출하고,
/// 받아들이고, catalog를 닫았다 다시 열어 남아 있는지 보고, 그 recipe가 실제 ABI preview의
/// 화소를 바꾸는지까지 셉니다. 단위 시험의 대역이 아니라 실제 파일·실제 엔진입니다.
/// </summary>
internal static class DefectRoundTripDiagnostics
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length != 3 || args[0] != "--defect-roundtrip")
        {
            return false;
        }
        exitCode = Run(args[1], args[2]);
        return true;
    }

    private static int Run(string storageRoot, string frameId)
    {
        if (StorageRootResolver.ResolveForTests(Path.GetFullPath(storageRoot)).Roots is not
            { } roots)
        {
            Console.WriteLine("storage root refused");
            return 1;
        }

        DefectEditItem accepted;
        int acceptedItems;
        using (LibraryHostService host = new(new FakeDispatcher(accepts: true)))
        {
            if (host.Open(roots) != LibraryHostState.Open)
            {
                Console.WriteLine("catalog refused");
                return 1;
            }
            if (host.Frames.SingleOrDefault(frame =>
                    string.Equals(frame.Id, frameId, StringComparison.Ordinal)) is not { } frame)
            {
                Console.WriteLine("frame unavailable");
                return 1;
            }
            if (DevelopRequestFactory.Create(
                    frame,
                    Path.Combine(Path.GetTempPath(), "defect-roundtrip.png")).Request
                is not { } request)
            {
                Console.WriteLine("request refused");
                return 1;
            }

            // 1) 실제 스캔에서 자동 검출을 돌립니다.
            GrainMendDetectionResult sized = NativeDevelopExporter.DetectGrainMend(
                request,
                Span<byte>.Empty);
            if (!sized.Result.Succeeded || sized.MaskByteCount == 0UL)
            {
                Console.WriteLine($"detect refused {sized.Result.FailureName}");
                return 1;
            }
            byte[] mask = new byte[checked((int)sized.MaskByteCount)];
            GrainMendDetectionResult filled =
                NativeDevelopExporter.DetectGrainMend(request, mask);
            uint sourceWidth = frame.SourceMetadata?.PixelWidth ?? 0U;
            uint sourceHeight = frame.SourceMetadata?.PixelHeight ?? 0U;
            if (GrainMendRegionEdit.From(
                    mask,
                    (int)filled.Width,
                    (int)filled.Height,
                    sourceWidth,
                    sourceHeight,
                    0U,
                    0U,
                    sourceWidth,
                    sourceHeight,
                    filled.AcceptedPixels,
                    automatic: true) is not { } edit)
            {
                Console.WriteLine("region edit refused");
                return 1;
            }
            accepted = edit;

            // 2) 받아들입니다. 여기까지 와야 사진이 바뀝니다.
            DevelopPanelState panel = new(
                host,
                ToneLimits.Read(),
                NegativeLimits.Read());
            panel.Select(frameId);
            if (panel.AcceptDefectRegion(accepted) != LibraryFrameError.None)
            {
                Console.WriteLine("accept refused");
                return 1;
            }
            acceptedItems = host.Frames
                .Single(item => item.Id == frameId).DefectRecipe?.Items.Count ?? 0;
        }

        // 3) catalog 를 닫았다 다시 엽니다. 남아 있어야 영속성입니다.
        using LibraryHostService reopened = new(new FakeDispatcher(accepts: true));
        if (reopened.Open(roots) != LibraryHostState.Open ||
            reopened.Frames.SingleOrDefault(frame =>
                string.Equals(frame.Id, frameId, StringComparison.Ordinal)) is not { } persisted)
        {
            Console.WriteLine("reopen refused");
            return 1;
        }
        int persistedItems = persisted.DefectRecipe?.Items.Count ?? 0;

        // 4) 저장된 recipe 가 실제 preview 화소를 바꾸는지 셉니다.
        if (DevelopRequestFactory.Create(
                persisted,
                Path.Combine(Path.GetTempPath(), "defect-roundtrip-with.png")).Request
                is not { } withRecipe ||
            DevelopRequestFactory.Create(
                persisted with { DefectRecipe = null },
                Path.Combine(Path.GetTempPath(), "defect-roundtrip-without.png")).Request
                is not { } withoutRecipe)
        {
            Console.WriteLine("preview request refused");
            return 1;
        }
        // 저장된 항목이 실제로 무엇을 담고 있는지 먼저 밝힙니다. 꺼져 있거나 세기가 0 이면
        // 화소가 안 바뀌는 것이 당연하고, 그것은 파이프라인 문제가 아닙니다.
        DefectEditItem? item = persisted.DefectRecipe?.Items.FirstOrDefault();
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            stage = "persisted-item",
            acceptedItems,
            persistedItems,
            kind = item?.Kind.ToString(),
            label = item?.Label.Kind.ToString(),
            item?.Enabled,
            item?.Strength,
            item?.RegionWidth,
            item?.RegionHeight,
            regionMaskBytes = item?.RegionMask?.Data.Length ?? 0,
            item?.RegionRoi,
            projectedRegions = withRecipe.DefectRegions.Count,
            projectedOrder = withRecipe.DefectEditOrder.Count,
        }));

        NativeDevelopExporterAdapter exporter = new();
        bool anyDifference = false;
        // 미리보기를 크게 볼수록 작은 먼지가 살아남습니다. 한 크기만 보고 "안 바뀐다"고
        // 말하지 않기 위해 세 크기를 잽니다.
        foreach ((int width, int height) in new[] { (900, 700), (1600, 1200), (2400, 1800) })
        {
            byte[] baseline = new byte[width * height * 4];
            byte[] repaired = new byte[width * height * 4];
            DevelopExportResult baselineResult =
                exporter.Preview(withoutRecipe, (uint)width, (uint)height, baseline);
            DevelopExportResult repairedResult =
                exporter.Preview(withRecipe, (uint)width, (uint)height, repaired);
            long differingBytes = 0;
            int maximumDifference = 0;
            for (int index = 0; index < baseline.Length; ++index)
            {
                int difference = Math.Abs(baseline[index] - repaired[index]);
                if (difference == 0)
                {
                    continue;
                }
                ++differingBytes;
                maximumDifference = Math.Max(maximumDifference, difference);
            }
            anyDifference |= differingBytes > 0;
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                stage = "preview",
                requestedWidth = width,
                requestedHeight = height,
                baselineSucceeded = baselineResult.Succeeded,
                repairedSucceeded = repairedResult.Succeeded,
                imageWidth = repairedResult.ImageWidth,
                imageHeight = repairedResult.ImageHeight,
                repairedStage = repairedResult.FailedStage.ToString(),
                repairedResult.FailureName,
                differingBytes,
                maximumDifference,
            }));
        }
        return persistedItems > 0 && anyDifference ? 0 : 1;
    }
}
