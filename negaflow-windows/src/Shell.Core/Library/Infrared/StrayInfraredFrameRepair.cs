using Negaflow.Catalog;

namespace Negaflow.Shell;

internal sealed record StrayInfraredFrameRepairPlan(
    IReadOnlyList<FrameInfraredAttachment> Attachments,
    IReadOnlyList<string> RemovedFrameIds,
    IReadOnlyDictionary<string, string> ReplacementFrameIdByRemovedFrameId)
{
    internal static StrayInfraredFrameRepairPlan Empty { get; } =
        new([], [], new Dictionary<string, string>());

    internal IReadOnlyList<LibraryFrameSnapshot> Project(
        IReadOnlyList<LibraryFrameSnapshot> frames)
    {
        HashSet<string> removed = RemovedFrameIds.ToHashSet(StringComparer.Ordinal);
        Dictionary<string, string> infraredByFrameId = Attachments.ToDictionary(
            attachment => attachment.FrameId,
            attachment => attachment.InfraredPath,
            StringComparer.Ordinal);
        return [.. frames
            .Where(frame => !removed.Contains(frame.Id))
            .Select(frame => infraredByFrameId.TryGetValue(frame.Id, out string? infraredPath)
                ? frame with { InfraredPath = infraredPath }
                : frame)];
    }
}

/// <summary>
/// 과거 importer가 독립 사진으로 만든 IR row를 본 스캔에 다시 붙이는 import 전 복구 계획입니다.
/// 파일은 건드리지 않으며 macOS <c>repairStrayInfraredFrames</c>와 같은 순서로 pairing을 소비합니다.
/// </summary>
internal static class StrayInfraredFrameRepair
{
    internal static StrayInfraredFrameRepairPlan Plan(
        IReadOnlyList<LibraryFrameSnapshot> frames)
    {
        ArgumentNullException.ThrowIfNull(frames);
        InfraredImportPairing.Resolution pairing = InfraredImportPairing.Resolve(
            [.. frames.Select(frame => frame.SourcePath)]);
        if (pairing.PairedInfraredPaths.Count == 0)
        {
            return StrayInfraredFrameRepairPlan.Empty;
        }

        Dictionary<string, string> pendingInfrared = new(
            pairing.InfraredByBaseIdentity,
            StringComparer.OrdinalIgnoreCase);
        List<FrameInfraredAttachment> attachments = [];
        Dictionary<string, string> baseFrameIdByInfraredIdentity = new(
            StringComparer.OrdinalIgnoreCase);
        foreach (LibraryFrameSnapshot frame in frames)
        {
            string identity = InfraredImportPairing.ImportIdentity(frame.SourcePath);
            if (!pendingInfrared.Remove(identity, out string? infraredPath))
            {
                continue;
            }
            baseFrameIdByInfraredIdentity[
                InfraredImportPairing.ImportIdentity(infraredPath)] = frame.Id;
            if (frame.InfraredPath is null)
            {
                attachments.Add(new FrameInfraredAttachment(frame.Id, infraredPath));
            }
        }

        HashSet<string> strayIdentities = pairing.PairedInfraredPaths
            .Select(InfraredImportPairing.ImportIdentity)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        string[] removedFrameIds = [.. frames
            .Where(frame => strayIdentities.Contains(
                InfraredImportPairing.ImportIdentity(frame.SourcePath)))
            .Select(frame => frame.Id)];
        HashSet<string> removedFrameIdSet = removedFrameIds.ToHashSet(StringComparer.Ordinal);
        Dictionary<string, string> replacementByRemovedFrameId = frames
            .Where(frame => removedFrameIdSet.Contains(frame.Id))
            .Where(frame => baseFrameIdByInfraredIdentity.ContainsKey(
                InfraredImportPairing.ImportIdentity(frame.SourcePath)))
            .ToDictionary(
                frame => frame.Id,
                frame => baseFrameIdByInfraredIdentity[
                    InfraredImportPairing.ImportIdentity(frame.SourcePath)],
                StringComparer.Ordinal);
        return new(attachments, removedFrameIds, replacementByRemovedFrameId);
    }
}
