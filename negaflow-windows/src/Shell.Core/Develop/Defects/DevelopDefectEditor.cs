using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

internal readonly record struct DevelopDefectEditResult(
    LibraryFrameError Error,
    bool Changed);

/// <summary>
/// Builds and persists GrainMend defect edits for one selected frame. Selection state and
/// UI refresh remain owned by <see cref="DevelopPanelState"/>.
/// </summary>
internal sealed class DevelopDefectEditor
{
    private delegate bool TryMapPoint(
        LibraryFrameSnapshot frame,
        DefectPoint display,
        out DefectPoint raw);

    private readonly LibraryHostService host;

    public DevelopDefectEditor(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        this.host = host;
    }

    public DevelopDefectEditResult AddBrushStroke(
        LibraryFrameSnapshot? frame,
        IReadOnlyList<DefectPoint> displayPoints,
        double thickness)
    {
        ArgumentNullException.ThrowIfNull(displayPoints);
        return AddBrushStrokes(frame, [new DefectStroke(displayPoints, thickness)]);
    }

    public DevelopDefectEditResult AddBrushStrokes(
        LibraryFrameSnapshot? frame,
        IReadOnlyList<DefectStroke> displayStrokes)
    {
        ArgumentNullException.ThrowIfNull(displayStrokes);
        if (frame is null ||
            !Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
            frame.SourceMetadata is not { PixelWidth: > 0U, PixelHeight: > 0U } metadata ||
            displayStrokes.Count == 0)
        {
            return new(LibraryFrameError.MissingId, false);
        }

        List<DefectStroke> rawStrokes = new(displayStrokes.Count);
        foreach (DefectStroke stroke in displayStrokes)
        {
            List<DefectPoint> rawPoints = new(stroke.Points.Count);
            foreach (DefectPoint point in stroke.Points)
            {
                if (!DevelopDefectCoordinateMapper.TryMapBrushDisplayToRaw(
                        frame, point, out DefectPoint raw))
                {
                    return new(LibraryFrameError.InvalidDefectRecipe, false);
                }
                rawPoints.Add(raw);
            }
            rawStrokes.Add(new DefectStroke(rawPoints, stroke.Thickness));
        }

        DefectSize baseSize = new(metadata.PixelWidth, metadata.PixelHeight);
        LibraryFrameError error = host.AppendDefectStroke(
            frame.Id,
            (identity, existing, nextRevision) => WithRevision(
                DefectStrokeRecipeBuilder.AppendBrushStrokes(
                    frameId, identity, existing, rawStrokes, baseSize),
                nextRevision));
        return new(error, error == LibraryFrameError.None);
    }

    public DevelopDefectEditResult AddCloneStroke(
        LibraryFrameSnapshot? frame,
        IReadOnlyList<DefectPoint> displayPoints,
        DefectPoint displaySourceAnchor,
        DefectPoint? alignedRawOffset,
        out DefectPoint usedRawOffset,
        double diameter,
        double hardness,
        double minimumDiameter,
        double maximumDiameter)
    {
        ArgumentNullException.ThrowIfNull(displayPoints);
        usedRawOffset = default;
        if (displayPoints.Count == 0 ||
            frame is null ||
            !DevelopDefectCoordinateMapper.TryMapCloneDisplayToRaw(
                frame, displayPoints[0], out DefectPoint firstTarget) ||
            !double.IsFinite(diameter) || !double.IsFinite(hardness))
        {
            return new(LibraryFrameError.InvalidDefectRecipe, false);
        }

        DefectPoint offset;
        if (alignedRawOffset is { } aligned)
        {
            offset = aligned;
        }
        else if (DevelopDefectCoordinateMapper.TryMapCloneDisplayToRaw(
            frame, displaySourceAnchor, out DefectPoint anchor))
        {
            offset = new DefectPoint(anchor.X - firstTarget.X, anchor.Y - firstTarget.Y);
        }
        else
        {
            return new(LibraryFrameError.InvalidDefectRecipe, false);
        }
        if (!double.IsFinite(offset.X) || !double.IsFinite(offset.Y))
        {
            return new(LibraryFrameError.InvalidDefectRecipe, false);
        }

        double clampedDiameter = Math.Clamp(diameter, minimumDiameter, maximumDiameter);
        double clampedHardness = Math.Clamp(hardness, 0.0, 1.0);
        DevelopDefectEditResult result = AddStroke(
            frame,
            displayPoints,
            DevelopDefectCoordinateMapper.TryMapCloneDisplayToRaw,
            (frameId, identity, existing, points, baseSize) =>
                DefectStrokeRecipeBuilder.AppendCloneStroke(
                    frameId,
                    identity,
                    existing,
                    points,
                    clampedDiameter,
                    offset.X,
                    offset.Y,
                    baseSize,
                    clampedHardness));
        if (result.Error == LibraryFrameError.None)
        {
            usedRawOffset = offset;
        }
        return result;
    }

    public DevelopDefectEditResult AcceptRegion(
        LibraryFrameSnapshot? frame,
        DefectEditItem edit) =>
        AcceptRegionCore(frame, edit, null, null);

    public DevelopDefectEditResult AcceptRegion(
        LibraryFrameSnapshot? frame,
        DefectEditItem edit,
        GrainMendDetectionToken detectionToken,
        DefectRecipeSnapshot? expectedRecipe)
    {
        ArgumentNullException.ThrowIfNull(detectionToken);
        return AcceptRegionCore(frame, edit, detectionToken, expectedRecipe);
    }

    private DevelopDefectEditResult AcceptRegionCore(
        LibraryFrameSnapshot? frame,
        DefectEditItem edit,
        GrainMendDetectionToken? detectionToken,
        DefectRecipeSnapshot? expectedRecipe)
    {
        ArgumentNullException.ThrowIfNull(edit);
        if (frame is null || !Guid.TryParseExact(frame.Id, "D", out Guid frameId))
        {
            return new(LibraryFrameError.MissingId, false);
        }

        LibraryFrameError error = host.AppendDefectStroke(
            frame.Id,
            (identity, existing, nextRevision) =>
            {
                if (detectionToken is not null &&
                    (!detectionToken.MatchesPersistedSource(
                        frame.Id,
                        frame.SourcePath,
                        identity) ||
                    !SameRecipe(existing, expectedRecipe)))
                {
                    return null;
                }
                try
                {
                    return DefectRecipeSnapshot.Create(
                        frameId,
                        nextRevision,
                        identity,
                        existing is null ? [edit] : [.. existing.Items, edit]);
                }
                catch (Exception failure) when (failure is ArgumentException or OverflowException)
                {
                    return null;
                }
            });
        return new(error, error == LibraryFrameError.None);
    }

    private static bool SameRecipe(
        DefectRecipeSnapshot? left,
        DefectRecipeSnapshot? right)
    {
        if (ReferenceEquals(left, right))
        {
            return true;
        }
        return left is not null && right is not null &&
            left.FrameId == right.FrameId &&
            left.FingerprintVersion == right.FingerprintVersion &&
            left.RecipeRevision == right.RecipeRevision &&
            string.Equals(left.RecipeSha256, right.RecipeSha256, StringComparison.Ordinal) &&
            left.SourceIdentity == right.SourceIdentity;
    }

    /// <summary>
    /// 목록 전체를 한 번에 갈아 끼웁니다. <paramref name="map"/> 이 null 을 내면 바뀐 것이 없다는
    /// 뜻이고 아무것도 쓰지 않습니다 — 같은 값을 다시 쓰면 개정 번호만 오르고 원본 해시를
    /// 다시 내느라 시간만 듭니다.
    /// </summary>
    public DevelopDefectEditResult ReplaceItems(
        LibraryFrameSnapshot? frame,
        Func<DefectRecipeSnapshot, IReadOnlyList<DefectEditItem>?> map,
        LibraryDefectHistoryMode historyMode = LibraryDefectHistoryMode.PreservingInfrared)
    {
        ArgumentNullException.ThrowIfNull(map);
        if (frame is null || !Guid.TryParseExact(frame.Id, "D", out Guid frameId))
        {
            return new(LibraryFrameError.MissingId, false);
        }
        if (frame.DefectRecipe is not { } recipe || map(recipe) is not { } items)
        {
            return new(LibraryFrameError.None, false);
        }

        LibraryFrameError error = host.AppendDefectStroke(
            frame.Id,
            (identity, _, nextRevision) =>
            {
                try
                {
                    return DefectRecipeSnapshot.Create(
                        frameId,
                        nextRevision,
                        identity,
                        items);
                }
                catch (Exception failure) when (failure is ArgumentException or OverflowException)
                {
                    return null;
                }
            },
            historyMode);
        return new(error, error == LibraryFrameError.None);
    }

    public static bool HasEdits(LibraryFrameSnapshot? frame, DefectEditKind kind) =>
        frame?.DefectRecipe?.Items.Any(item => item.Kind == kind) == true;

    public static bool HasEdits(LibraryFrameSnapshot? frame, DefectEditLabelKind label) =>
        frame?.DefectRecipe?.Items.Any(item => item.Label.Kind == label) == true;

    public DevelopDefectEditResult RemoveEdits(
        LibraryFrameSnapshot? frame,
        DefectEditKind kind) =>
        RemoveEdits(frame, item => item.Kind == kind);

    public DevelopDefectEditResult RemoveEdits(
        LibraryFrameSnapshot? frame,
        DefectEditLabelKind label) =>
        RemoveEdits(frame, item => item.Label.Kind == label);

    public DevelopDefectEditResult RemoveNonInfraredEdits(LibraryFrameSnapshot? frame) =>
        RemoveEdits(frame, item => item.Kind != DefectEditKind.Infrared);

    public static bool TryMapDisplayRectToRaw(
        LibraryFrameSnapshot? frame,
        DefectRect displayRect,
        out DefectRect rawRect)
    {
        rawRect = default;
        if (!double.IsFinite(displayRect.X) || !double.IsFinite(displayRect.Y) ||
            !double.IsFinite(displayRect.Width) || !double.IsFinite(displayRect.Height) ||
            displayRect.Width <= 0.0 || displayRect.Height <= 0.0)
        {
            return false;
        }

        DefectPoint[] corners =
        [
            new(displayRect.X, displayRect.Y),
            new(displayRect.X + displayRect.Width, displayRect.Y),
            new(displayRect.X, displayRect.Y + displayRect.Height),
            new(displayRect.X + displayRect.Width, displayRect.Y + displayRect.Height),
        ];
        double minX = 1.0;
        double minY = 1.0;
        double maxX = 0.0;
        double maxY = 0.0;
        foreach (DefectPoint corner in corners)
        {
            if (!TryMapToRaw(frame, corner, out DefectPoint raw))
            {
                return false;
            }
            minX = Math.Min(minX, raw.X);
            minY = Math.Min(minY, raw.Y);
            maxX = Math.Max(maxX, raw.X);
            maxY = Math.Max(maxY, raw.Y);
        }
        if (maxX <= minX || maxY <= minY)
        {
            return false;
        }
        rawRect = new DefectRect(minX, minY, maxX - minX, maxY - minY);
        return true;
    }

    private DevelopDefectEditResult AddStroke(
        LibraryFrameSnapshot? frame,
        IReadOnlyList<DefectPoint> displayPoints,
        TryMapPoint tryMap,
        Func<Guid, DefectSourceIdentity, DefectRecipeSnapshot?, IReadOnlyList<DefectPoint>,
            DefectSize, DefectRecipeSnapshot?> build)
    {
        if (frame is null ||
            !Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
            frame.SourceMetadata is not { } metadata ||
            metadata.PixelWidth == 0U || metadata.PixelHeight == 0U)
        {
            return new(LibraryFrameError.MissingId, false);
        }

        List<DefectPoint> rawPoints = new(displayPoints.Count);
        foreach (DefectPoint point in displayPoints)
        {
            if (tryMap(frame, point, out DefectPoint raw))
            {
                rawPoints.Add(raw);
            }
            else
            {
                return new(LibraryFrameError.InvalidDefectRecipe, false);
            }
        }
        if (rawPoints.Count == 0)
        {
            return new(LibraryFrameError.InvalidDefectRecipe, false);
        }

        DefectSize baseSize = new(metadata.PixelWidth, metadata.PixelHeight);
        LibraryFrameError error = host.AppendDefectStroke(
            frame.Id,
            (identity, existing, nextRevision) => WithRevision(
                build(frameId, identity, existing, rawPoints, baseSize),
                nextRevision));
        return new(error, error == LibraryFrameError.None);
    }

    private DevelopDefectEditResult RemoveEdits(
        LibraryFrameSnapshot? frame,
        Func<DefectEditItem, bool> matches)
    {
        if (frame is null || !Guid.TryParseExact(frame.Id, "D", out Guid frameId))
        {
            return new(LibraryFrameError.MissingId, false);
        }
        if (frame.DefectRecipe is not { } recipe || recipe.Items.All(item => !matches(item)))
        {
            return new(LibraryFrameError.None, false);
        }

        DefectEditItem[] remaining = [.. recipe.Items.Where(item => !matches(item))];
        LibraryFrameError error = host.AppendDefectStroke(
            frame.Id,
            (identity, _, nextRevision) =>
            {
                try
                {
                    return DefectRecipeSnapshot.Create(
                        frameId,
                        nextRevision,
                        identity,
                        remaining);
                }
                catch (Exception failure) when (failure is ArgumentException or OverflowException)
                {
                    return null;
                }
            });
        return new(error, error == LibraryFrameError.None);
    }

    private static DefectRecipeSnapshot? WithRevision(
        DefectRecipeSnapshot? recipe,
        ulong revision)
    {
        if (recipe is null || recipe.RecipeRevision == revision)
        {
            return recipe;
        }
        try
        {
            return DefectRecipeSnapshot.Create(
                recipe.FrameId,
                revision,
                recipe.SourceIdentity,
                recipe.Items);
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    private static bool TryMapToRaw(
        LibraryFrameSnapshot? frame,
        DefectPoint displayPoint,
        out DefectPoint rawPoint)
    {
        rawPoint = default;
        if (frame?.SourceMetadata is not { } metadata)
        {
            return false;
        }
        if (!DevelopDisplayGeometry.TryMapDisplayToRaw(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                displayPoint.X,
                displayPoint.Y,
                out double rawX,
                out double rawY))
        {
            return false;
        }
        rawPoint = new DefectPoint(rawX, rawY);
        return true;
    }
}
