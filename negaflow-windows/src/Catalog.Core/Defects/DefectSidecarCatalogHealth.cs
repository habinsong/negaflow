namespace Negaflow.Catalog;

internal sealed record DefectSidecarCatalogEntry(
    string CatalogFrameId,
    Guid FrameId,
    string Path,
    DefectRecipeSnapshot Snapshot);

internal readonly record struct DefectCatalogHealthResult(
    IReadOnlyList<DefectSidecarCatalogEntry>? Entries,
    DefectSidecarError Error)
{
    public bool IsHealthy => Error == DefectSidecarError.None && Entries is not null;

    public static DefectCatalogHealthResult Healthy(
        IReadOnlyList<DefectSidecarCatalogEntry> entries) =>
        new(entries, DefectSidecarError.None);

    public static DefectCatalogHealthResult Failure(DefectSidecarError error) =>
        new(null, error);
}

/// <summary>
/// catalog 가 선언한 defect sidecar 가 실제로 있고 읽히는지 확인합니다. 하나라도
/// 어긋나면 목록을 내지 않습니다 - 반쪽짜리 목록으로 복구를 시작하면 더 나빠집니다.
/// </summary>
internal static class DefectSidecarCatalogHealth
{
    public static DefectSidecarError CleanupUndeclaredFrameSidecars(
        StorageRootSet roots,
        CatalogSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (DefectSidecarStore.Gate)
        {
            if (!DefectSidecarFile.HasValidRoots(roots))
            {
                return DefectSidecarError.InvalidStorageRoots;
            }
            if (File.Exists(roots.DefectRecipeRoot) ||
                StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot))
            {
                return DefectSidecarError.ReparsePointNotAllowed;
            }

            List<Guid> cleanupTargets = [];
            HashSet<Guid> frameIds = [];
            foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
            {
                bool hasEdits = false;
                if (frame.Payload.TryGetPropertyValue(
                        "hasDefectEdits",
                        out System.Text.Json.Nodes.JsonNode? node) &&
                    node is not null)
                {
                    if (node is not System.Text.Json.Nodes.JsonValue value ||
                        !value.TryGetValue(out hasEdits))
                    {
                        return DefectSidecarError.InvalidContent;
                    }
                }
                if (!Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
                    frameId == Guid.Empty)
                {
                    if (hasEdits)
                    {
                        return DefectSidecarError.InvalidFrameId;
                    }
                    continue;
                }
                if (!frameIds.Add(frameId))
                {
                    return DefectSidecarError.InvalidFrameId;
                }
                if (!hasEdits)
                {
                    cleanupTargets.Add(frameId);
                }
            }

            foreach (Guid frameId in cleanupTargets)
            {
                DefectSidecarReadResult read = DefectSidecarFile.ReadFile(
                    DefectSidecarStore.PathFor(roots, frameId),
                    frameId);
                if (read.Snapshot is null && read.Error != DefectSidecarError.NotFound)
                {
                    return read.Error;
                }
            }
            foreach (Guid frameId in cleanupTargets)
            {
                DefectSidecarDeleteResult cleaned =
                    DefectSidecarStore.CleanupUndeclared(roots, frameId);
                if (!cleaned.IsSuccess)
                {
                    return cleaned.Error;
                }
            }
            return DefectSidecarError.None;
        }
    }

    /// <summary>
    /// 선언된 sidecar 가 전부 읽히는지만 확인합니다. <see cref="ValidateCatalogDeclarations"/>
    /// 와 달리 snapshot 을 모으지 않고, <see cref="DefectSidecarValidationCache"/> 로 이미
    /// 검증한 파일의 재복호를 건너뜁니다. commit gate 처럼 목록이 필요 없는 쪽이 씁니다.
    /// </summary>
    public static DefectSidecarError ValidateDeclaredSidecars(
        StorageRootSet roots,
        CatalogSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (DefectSidecarStore.Gate)
        {
            if (!DefectSidecarFile.HasValidRoots(roots))
            {
                return DefectSidecarError.InvalidStorageRoots;
            }
            if (File.Exists(roots.DefectRecipeRoot) ||
                StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot))
            {
                return DefectSidecarError.ReparsePointNotAllowed;
            }

            HashSet<Guid> frameIds = [];
            foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
            {
                if (!DeclaresDefectEdits(frame, out bool hasEdits))
                {
                    return DefectSidecarError.InvalidContent;
                }
                if (!hasEdits)
                {
                    continue;
                }
                if (!Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
                    frameId == Guid.Empty ||
                    !frameIds.Add(frameId))
                {
                    return DefectSidecarError.InvalidFrameId;
                }

                string path = DefectSidecarStore.PathFor(roots, frameId);
                bool stamped = DefectSidecarValidationCache.TryStamp(
                    path,
                    out long length,
                    out long ticks);
                if (stamped &&
                    DefectSidecarValidationCache.IsValidated(path, length, ticks))
                {
                    continue;
                }
                DefectSidecarReadResult read = DefectSidecarFile.ReadFile(path, frameId);
                if (read.Snapshot is null)
                {
                    return read.Error;
                }
                // 복호 중에 파일이 바뀌었으면 어느 내용을 통과시킨 것인지 알 수 없으므로
                // 캐시에 넣지 않습니다 - 다음 gate 에서 다시 읽습니다.
                if (stamped &&
                    DefectSidecarValidationCache.TryStamp(
                        path,
                        out long afterLength,
                        out long afterTicks) &&
                    afterLength == length &&
                    afterTicks == ticks)
                {
                    DefectSidecarValidationCache.Record(path, length, ticks);
                }
            }
            return DefectSidecarError.None;
        }
    }

    /// <summary>
    /// `hasDefectEdits` 를 읽습니다. 값이 bool 이 아니면 <c>false</c> 를 내고, 없으면
    /// 선언하지 않은 것으로 봅니다.
    /// </summary>
    private static bool DeclaresDefectEdits(CatalogEntityRow frame, out bool hasEdits)
    {
        hasEdits = false;
        if (!frame.Payload.TryGetPropertyValue(
                "hasDefectEdits",
                out System.Text.Json.Nodes.JsonNode? node) ||
            node is null)
        {
            return true;
        }
        return node is System.Text.Json.Nodes.JsonValue value &&
            value.TryGetValue(out hasEdits);
    }

    public static DefectCatalogHealthResult ValidateCatalogDeclarations(
        StorageRootSet roots,
        CatalogSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (DefectSidecarStore.Gate)
        {
            if (!DefectSidecarFile.HasValidRoots(roots))
            {
                return DefectCatalogHealthResult.Failure(
                    DefectSidecarError.InvalidStorageRoots);
            }
            if (File.Exists(roots.DefectRecipeRoot) ||
                StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot))
            {
                return DefectCatalogHealthResult.Failure(
                    DefectSidecarError.ReparsePointNotAllowed);
            }

            List<DefectSidecarCatalogEntry> entries = [];
            HashSet<Guid> frameIds = [];
            foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
            {
                if (!frame.Payload.TryGetPropertyValue(
                        "hasDefectEdits",
                        out System.Text.Json.Nodes.JsonNode? node) ||
                    node is null)
                {
                    continue;
                }
                if (node is not System.Text.Json.Nodes.JsonValue value ||
                    !value.TryGetValue(out bool hasEdits))
                {
                    return DefectCatalogHealthResult.Failure(
                        DefectSidecarError.InvalidContent);
                }
                if (!hasEdits)
                {
                    continue;
                }
                if (!Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
                    frameId == Guid.Empty ||
                    !frameIds.Add(frameId))
                {
                    return DefectCatalogHealthResult.Failure(
                        DefectSidecarError.InvalidFrameId);
                }

                string path = DefectSidecarStore.PathFor(roots, frameId);
                DefectSidecarReadResult read = DefectSidecarFile.ReadFile(path, frameId);
                if (read.Snapshot is not { } recipe)
                {
                    return DefectCatalogHealthResult.Failure(read.Error);
                }
                entries.Add(new DefectSidecarCatalogEntry(
                    frame.Id,
                    frameId,
                    path,
                    recipe));
            }
            entries.Sort((left, right) => StringComparer.Ordinal.Compare(
                left.CatalogFrameId,
                right.CatalogFrameId));
            return DefectCatalogHealthResult.Healthy(entries);
        }
    }
}
