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
            GrainMendDetectionResult detected = NativeDevelopExporter.DetectGrainMend(
                request);
            if (!detected.Result.Succeeded || detected.ReviewProposal is not { } proposal)
            {
                detected.ReviewProposal?.Dispose();
                Console.WriteLine($"detect refused {detected.Result.FailureName}");
                return 1;
            }
            GrainMendReviewSession? review = null;
            try
            {
                review = GrainMendReviewSession.TryCreate(proposal, automatic: true);
                if (review?.BuildAcceptedEdit() is not { } edit)
                {
                    Console.WriteLine("region edit refused");
                    return 1;
                }
                accepted = edit;
            }
            finally
            {
                if (review is not null)
                {
                    review.Dispose();
                }
                else
                {
                    proposal.Dispose();
                }
            }

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
                Path.Combine(Path.GetTempPath(), $"defect-roundtrip-with-{Guid.NewGuid():N}.png")).Request
                is not { } withRecipe ||
            DevelopRequestFactory.Create(
                persisted with { DefectRecipe = null },
                Path.Combine(Path.GetTempPath(), $"defect-roundtrip-without-{Guid.NewGuid():N}.png")).Request
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
        foreach ((int width, int height) in new[]
                 {
                     (900, 700),
                     (1600, 1200),
                     (2400, 1800),
                     // 원본 크기로도 재 봅니다. 여기서 같으면 축소 탓이 아니라 preview 경로가
                     // recipe 를 버린 것입니다.
                     ((int)(persisted.SourceMetadata?.PixelWidth ?? 5088U),
                      (int)(persisted.SourceMetadata?.PixelHeight ?? 3401U)),
                 })
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
        // 미리보기는 5088x3401 을 900 안팎으로 줄입니다. 먼지가 축소에 씻겨 나가서 같아 보이는
        // 것인지, 수리 자체가 아무 일도 하지 않는 것인지를 가르려면 원본 해상도로 내보내
        // 견주어야 합니다.
        DevelopExportResult withoutRun = NativeDevelopExporter.Run(withoutRecipe);
        DevelopExportResult withRun = NativeDevelopExporter.Run(withRecipe);
        long exportDifferingBytes = -1;
        long withoutBytes = -1;
        long withBytes = -1;
        if (withoutRun.Succeeded && withRun.Succeeded &&
            File.Exists(withoutRecipe.DestinationPath) && File.Exists(withRecipe.DestinationPath))
        {
            byte[] withoutFile = File.ReadAllBytes(withoutRecipe.DestinationPath);
            byte[] withFile = File.ReadAllBytes(withRecipe.DestinationPath);
            withoutBytes = withoutFile.LongLength;
            withBytes = withFile.LongLength;
            exportDifferingBytes = 0;
            for (long index = 0; index < Math.Min(withoutBytes, withBytes); ++index)
            {
                if (withoutFile[index] != withFile[index])
                {
                    ++exportDifferingBytes;
                }
            }
        }
        // 대조군: 같은 요청을 두 번 내보내 견줍니다. 여기서도 바이트가 다르면 PNG 출력이
        // 결정적이지 않다는 뜻이고, 위의 export 차이는 수리의 증거가 되지 못합니다.
        long controlDifferingBytes = -1;
        if (withoutRun.Succeeded && File.Exists(withoutRecipe.DestinationPath) &&
            DevelopRequestFactory.Create(
                persisted with { DefectRecipe = null },
                Path.Combine(
                    Path.GetTempPath(),
                    $"defect-roundtrip-control-{Guid.NewGuid():N}.png")).Request
                is { } controlRequest)
        {
            DevelopExportResult again = NativeDevelopExporter.Run(controlRequest);
            if (again.Succeeded && File.Exists(controlRequest.DestinationPath))
            {
                byte[] first = File.ReadAllBytes(withoutRecipe.DestinationPath);
                byte[] second = File.ReadAllBytes(controlRequest.DestinationPath);
                controlDifferingBytes = first.LongLength == second.LongLength ? 0 : -2;
                if (controlDifferingBytes == 0)
                {
                    for (long index = 0; index < first.LongLength; ++index)
                    {
                        if (first[index] != second[index])
                        {
                            ++controlDifferingBytes;
                        }
                    }
                }
            }
        }

        Console.WriteLine(JsonSerializer.Serialize(new
        {
            stage = "export",
            controlDifferingBytes,
            withoutSucceeded = withoutRun.Succeeded,
            withSucceeded = withRun.Succeeded,
            withRun.ImageWidth,
            withRun.ImageHeight,
            failedStage = withRun.FailedStage.ToString(),
            withRun.FailureName,
            withoutBytes,
            withBytes,
            exportDifferingBytes,
        }));

        return persistedItems > 0 && (anyDifference || exportDifferingBytes > 0) ? 0 : 1;
    }
}
