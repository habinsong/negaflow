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

            // 선언하지 않은 사진 자리의 못 읽는 기록은 라이브러리를 막지 않습니다 — macOS 는 알 수 없는
            // 파일을 두고 엽니다. 쓰레기는 한 번 보관한 뒤 치우고(남기면 그 사진의 새 편집이 거부됩니다),
            // 더 새 버전·권한·입출력 오류는 지우지 않고 그대로 둡니다.
            bool preserved = false;
            foreach (Guid frameId in cleanupTargets.ToArray())
            {
                DefectSidecarReadResult read = DefectSidecarFile.ReadFile(
                    DefectSidecarStore.PathFor(roots, frameId),
                    frameId);
                if (read.Snapshot is not null || read.Error == DefectSidecarError.NotFound)
                {
                    continue;
                }
                bool garbage = read.Error is DefectSidecarError.InvalidContent or
                    DefectSidecarError.InvalidSnapshot or DefectSidecarError.InvalidFrameId or
                    DefectSidecarError.ConflictingSameRevision;
                if (!garbage || !(preserved || (preserved = CatalogSidelinedFiles.Preserve(roots))))
                {
                    cleanupTargets.Remove(frameId);
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

            // 먼저 선언을 차례대로 훑어 읽을 파일을 모으고, 모은 것을 한꺼번에 복호합니다
            // (`DefectSidecarFile.ReadFiles`). 선언이 어긋난 줄을 만나면 거기서 모으기를 멈추고,
            // 그 앞 파일의 오류가 먼저 나가도록 복호 결과를 본 뒤에 그 오류를 돌려줍니다 - 한 장씩
            // 읽던 때와 같은 오류가 같은 차례로 나갑니다.
            DefectSidecarError declarationError = DefectSidecarError.None;
            HashSet<Guid> frameIds = [];
            List<Guid> pendingIds = [];
            List<string> pendingPaths = [];
            List<(bool Stamped, long Length, long Ticks)> pendingStamps = [];
            foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
            {
                if (!DeclaresDefectEdits(frame, out bool hasEdits))
                {
                    declarationError = DefectSidecarError.InvalidContent;
                    break;
                }
                if (!hasEdits)
                {
                    continue;
                }
                if (!Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
                    frameId == Guid.Empty ||
                    !frameIds.Add(frameId))
                {
                    declarationError = DefectSidecarError.InvalidFrameId;
                    break;
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
                pendingIds.Add(frameId);
                pendingPaths.Add(path);
                pendingStamps.Add((stamped, length, ticks));
            }

            DefectSidecarReadResult[] reads =
                DefectSidecarFile.ReadFiles(pendingPaths, pendingIds);
            for (int index = 0; index < reads.Length; ++index)
            {
                if (reads[index].Snapshot is null)
                {
                    return reads[index].Error;
                }
                // 복호 중에 파일이 바뀌었으면 어느 내용을 통과시킨 것인지 알 수 없으므로
                // 캐시에 넣지 않습니다 - 다음 gate 에서 다시 읽습니다.
                (bool stamped, long length, long ticks) = pendingStamps[index];
                if (stamped &&
                    DefectSidecarValidationCache.TryStamp(
                        pendingPaths[index],
                        out long afterLength,
                        out long afterTicks) &&
                    afterLength == length &&
                    afterTicks == ticks)
                {
                    DefectSidecarValidationCache.Record(pendingPaths[index], length, ticks);
                }
            }
            return declarationError;
        }
    }

    /// <summary>
    /// 선언의 모양만 봅니다 — <c>hasDefectEdits</c> 가 bool 이고, 선언한 사진 id 가 서로 다른
    /// GUID 인지. 기록 파일은 읽지 않습니다. 열기는 이것만 막고, 읽지 못하는 기록은 그 사진만
    /// "복원 대기" 로 둡니다(macOS <c>DefectRecipeRestoration</c>). 예전에는 기록 하나를 못 읽어도
    /// 라이브러리 전체를 열지 않았습니다.
    /// </summary>
    public static DefectSidecarError ValidateDeclarationShape(CatalogSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        HashSet<Guid> frameIds = [];
        foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
        {
            if (!DeclaresDefectEdits(frame, out bool hasEdits))
            {
                return DefectSidecarError.InvalidContent;
            }
            if (hasEdits &&
                (!Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
                 frameId == Guid.Empty ||
                 !frameIds.Add(frameId)))
            {
                return DefectSidecarError.InvalidFrameId;
            }
        }
        return DefectSidecarError.None;
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
