using System.Diagnostics;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

/// <summary>한 recipe 가 실제로 화소를 바꾸는지 잰 결과입니다.</summary>
internal sealed record DefectPixelDelta(
    int RequestedWidth,
    int RequestedHeight,
    bool BaselineSucceeded,
    bool RepairedSucceeded,
    string RepairedStage,
    string? FailureName,
    long BaselineMilliseconds,
    long RepairedMilliseconds,
    long DifferingBytes,
    int MaximumDifference);

/// <summary>
/// recipe 있는 요청과 없는 요청을 같은 크기로 그려 바이트를 견줍니다. 대조군(같은 요청 두 번)이
/// 0 이어야 차이가 수리의 증거가 됩니다 — 그렇지 않으면 출력이 결정적이지 않다는 뜻입니다.
/// </summary>
internal static class DefectPixelProbe
{
    /// <summary>
    /// 작게 줄이면 먼지가 축소에 씻겨 나갑니다. 한 크기만 보고 "안 바뀐다"고 말하지 않도록
    /// 원본 크기까지 함께 잽니다.
    /// </summary>
    internal static IReadOnlyList<(int Width, int Height)> Sizes(
        LibraryFrameSnapshot frame) =>
    [
        (900, 700),
        (1600, 1200),
        ((int)(frame.SourceMetadata?.PixelWidth ?? 0U),
         (int)(frame.SourceMetadata?.PixelHeight ?? 0U)),
    ];

    /// <summary>
    /// <paramref name="recipe"/> 를 얹은 frame 과 얹지 않은 frame 을 견줍니다. 요청을 만들지
    /// 못하면 null 입니다 — 그 자체가 결과이므로 삼키지 않습니다.
    /// </summary>
    public static IReadOnlyList<DefectPixelDelta>? Preview(
        LibraryFrameSnapshot frame,
        DefectRecipeSnapshot? recipe,
        IDevelopExporter exporter)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(exporter);
        if (!TryBuildPair(frame, recipe, out DevelopExportRequest? with, out DevelopExportRequest? without))
        {
            return null;
        }

        List<DefectPixelDelta> deltas = [];
        foreach ((int width, int height) in Sizes(frame))
        {
            if (width <= 0 || height <= 0)
            {
                continue;
            }
            byte[] baseline = new byte[checked(width * height * 4)];
            byte[] repaired = new byte[baseline.Length];
            Stopwatch baselineClock = Stopwatch.StartNew();
            DevelopExportResult baselineResult =
                exporter.Preview(without!, (uint)width, (uint)height, baseline);
            baselineClock.Stop();
            Stopwatch repairedClock = Stopwatch.StartNew();
            DevelopExportResult repairedResult =
                exporter.Preview(with!, (uint)width, (uint)height, repaired);
            repairedClock.Stop();
            (long differing, int maximum) = Compare(baseline, repaired);
            deltas.Add(new DefectPixelDelta(
                width,
                height,
                baselineResult.Succeeded,
                repairedResult.Succeeded,
                repairedResult.FailedStage.ToString(),
                repairedResult.FailureName,
                baselineClock.ElapsedMilliseconds,
                repairedClock.ElapsedMilliseconds,
                differing,
                maximum));
        }
        return deltas;
    }

    /// <summary>
    /// 같은 요청을 두 번 미리 그려 견줍니다. 0 이 아니면 preview 출력이 결정적이지 않아
    /// 위의 차이가 수리의 증거가 되지 못합니다.
    /// </summary>
    public static long Control(
        LibraryFrameSnapshot frame,
        IDevelopExporter exporter,
        int width,
        int height)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(exporter);
        if (width <= 0 || height <= 0 ||
            !TryBuildPair(frame, null, out _, out DevelopExportRequest? without))
        {
            return -1L;
        }
        byte[] first = new byte[checked(width * height * 4)];
        byte[] second = new byte[first.Length];
        if (!exporter.Preview(without!, (uint)width, (uint)height, first).Succeeded ||
            !exporter.Preview(without!, (uint)width, (uint)height, second).Succeeded)
        {
            return -1L;
        }
        return Compare(first, second).Differing;
    }

    private static bool TryBuildPair(
        LibraryFrameSnapshot frame,
        DefectRecipeSnapshot? recipe,
        out DevelopExportRequest? with,
        out DevelopExportRequest? without)
    {
        with = DevelopRequestFactory.Create(
            frame with { DefectRecipe = recipe },
            TempDestination("with")).Request;
        without = DevelopRequestFactory.Create(
            frame with { DefectRecipe = null },
            TempDestination("without")).Request;
        return with is not null && without is not null;
    }

    private static string TempDestination(string label) =>
        Path.Combine(Path.GetTempPath(), $"defect-tools-{label}-{Guid.NewGuid():N}.png");

    private static (long Differing, int Maximum) Compare(byte[] left, byte[] right)
    {
        long differing = 0L;
        int maximum = 0;
        for (int index = 0; index < left.Length; ++index)
        {
            int difference = Math.Abs(left[index] - right[index]);
            if (difference == 0)
            {
                continue;
            }
            ++differing;
            maximum = Math.Max(maximum, difference);
        }
        return (differing, maximum);
    }
}
