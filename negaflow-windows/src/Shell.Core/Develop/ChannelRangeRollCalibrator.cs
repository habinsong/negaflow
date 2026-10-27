using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 롤 교정입니다. 렌더가 프레임마다 한 번 잰 채널 범위 모양(<see cref="LibraryFrameSnapshot.RangeShape"/>)을
/// 같은 묶음(물리 롤, 없으면 원본이 놓인 같은 폴더)에서 모아 중앙값 하나로 정하고, 그 값을 아직 교정이
/// 없는 묶음 구성원에게 찍습니다. macOS <c>AppModel+ChannelRangeCalibration</c> 과 같은 규칙입니다.
/// </summary>
/// <remarks>
/// 찍은 값은 프레임에 남고 이후 표본이 늘어도 바뀌지 않습니다 — 같은 입력과 같은 레시피가 같은
/// 그림이어야 하기 때문입니다. 표본이 모자라거나(<see cref="ChannelRangeCalibration.MinimumFrameCount"/>
/// 미만) 필름이 섞여 흩어짐이 크면 아무것도 찍지 않고 세 채널이 같은 범위인 옛 동작으로 둡니다.
/// </remarks>
public static class ChannelRangeRollCalibrator
{
    /// <summary>같은 장치·필름의 프레임이 모이는 단위입니다. 스캐너 TIFF 와 가져온 파일은 센서 경로가 달라 섞지 않습니다.</summary>
    internal readonly record struct Group(string Container, FrameSourceKind Source);

    internal readonly record struct Member(
        ChannelRangeRgb? Shape,
        ChannelRangeRgb? Stamped,
        bool ContributesShape);

    internal static Group GroupOf(string? physicalRollId, string sourcePath, FrameSourceKind source)
    {
        string container = physicalRollId is not null
            ? "roll:" + physicalRollId
            : "folder:" + (Path.GetDirectoryName(sourcePath) ?? string.Empty).ToUpperInvariant();
        return new Group(container, source);
    }

    /// <summary>
    /// 묶음의 교정값입니다. 이미 찍힌 값이 있으면 그것을 따르고(가장 많은 값, 동률이면 앞선 값), 없으면
    /// 측정 표본의 중앙값입니다. 표본이 모자라면 null 입니다.
    /// </summary>
    internal static ChannelRangeRgb? Resolve(IReadOnlyList<Member> members)
    {
        List<(ChannelRangeRgb Value, int Count)> tally = [];
        foreach (Member member in members)
        {
            if (member.Stamped is not { } stamped)
            {
                continue;
            }
            int index = tally.FindIndex(entry => entry.Value == stamped);
            if (index < 0)
            {
                tally.Add((stamped, 1));
            }
            else
            {
                tally[index] = (stamped, tally[index].Count + 1);
            }
        }
        if (tally.Count > 0)
        {
            (ChannelRangeRgb Value, int Count) best = tally[0];
            foreach ((ChannelRangeRgb Value, int Count) entry in tally)
            {
                if (entry.Count > best.Count)
                {
                    best = entry;
                }
            }
            return best.Value;
        }
        return ChannelRangeCalibration.Combine(
            members.Where(member => member.ContributesShape && member.Shape is not null)
                .Select(member => member.Shape!.Value));
    }

    /// <summary>
    /// <paramref name="frameId"/> 가 속한 묶음의 교정값을 정해 아직 교정이 없는 구성원에게 찍습니다.
    /// 찍은 프레임 수를 돌려줍니다. 컬러 네거티브가 아니거나 표본이 모자라면 0 입니다.
    /// </summary>
    public static int Calibrate(LibraryHostService host, string frameId)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(frameId);
        IReadOnlyList<LibraryFrameSnapshot> frames = host.Frames;
        LibraryFrameSnapshot? frame = frames.FirstOrDefault(
            candidate => string.Equals(candidate.Id, frameId, StringComparison.Ordinal));
        if (frame is null || !IsColorNegative(frame))
        {
            return 0;
        }

        Dictionary<string, string> rollOfFrame = new(StringComparer.Ordinal);
        foreach (LibraryRollSnapshot roll in host.Rolls)
        {
            if (roll.Kind != LibraryRollKind.Physical)
            {
                continue;
            }
            foreach (string id in roll.FrameIds)
            {
                rollOfFrame[id] = roll.Id;
            }
        }
        Group GroupFor(LibraryFrameSnapshot candidate) =>
            GroupOf(rollOfFrame.GetValueOrDefault(candidate.Id), candidate.SourcePath, candidate.SourceKind);

        Group target = GroupFor(frame);
        List<LibraryFrameSnapshot> members = [.. frames.Where(candidate =>
            IsColorNegative(candidate) && candidate.SourceKind == frame.SourceKind &&
            GroupFor(candidate) == target)];
        ChannelRangeRgb? resolved = Resolve([.. members.Select(member =>
            new Member(member.RangeShape, member.ChannelRange, !member.IsVirtualCopy))]);
        if (resolved is not { } range)
        {
            return 0;
        }

        List<string> unstamped = [.. members.Where(member => member.ChannelRange is null).Select(member => member.Id)];
        if (unstamped.Count == 0)
        {
            return 0;
        }
        return host.EditFrameRecords(unstamped, record => ChannelRangeWriter.Apply(record, range)) ==
            LibraryFrameError.None
            ? unstamped.Count
            : 0;
    }

    private static bool IsColorNegative(LibraryFrameSnapshot frame) =>
        frame.Route.FilmType == FilmType.ColorNegative && !frame.IsPreviewScan;
}
