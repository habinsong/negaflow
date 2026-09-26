using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>카탈로그 수동 복구·재설치가 멈춘 자리입니다.</summary>
public enum LibraryCatalogMaintenanceError
{
    None,

    /// <summary>라이브러리가 열려 있지 않거나 지금은 할 수 없습니다(스캔·내보내기 중 등).</summary>
    Unavailable,

    /// <summary>
    /// 메모리 recipe 로 결함 기록을 다시 쓰지 못했습니다. 읽기 권한이 없거나 더 새 버전인
    /// 기록은 여기서 멈추고 건드리지 않습니다.
    /// </summary>
    DefectRecipeRewriteFailed,

    /// <summary>카탈로그를 저장하지 못했습니다.</summary>
    CatalogSaveFailed,

    /// <summary>검증된 백업 세대를 만들지 못했습니다.</summary>
    BackupFailed,

    /// <summary>그 세대를 다음 실행의 예약 복원으로 걸지 못했습니다.</summary>
    ScheduleFailed,
}

public readonly record struct LibraryCatalogMaintenanceResult(
    LibraryCatalogMaintenanceError Error,
    CatalogStoreError CatalogError = CatalogStoreError.None,
    DefectSidecarError SidecarError = DefectSidecarError.None)
{
    public bool IsSuccess => Error == LibraryCatalogMaintenanceError.None;
}

/// <summary>
/// 진단 패널의 카탈로그 수동 복구·재설치입니다. macOS
/// <c>AppModel+LibraryCatalogMaintenance</c> 를 Windows 문서 모델로 옮겼습니다.
/// </summary>
/// <remarks>
/// <para>
/// Windows 는 결함 recipe 를 메모리(<see cref="LibraryDocumentState.DefectRecipes"/>)에 들고
/// sidecar 와 카탈로그를 한 트랜잭션으로 씁니다. 그래서 macOS 의 "복원 대기" 가 메모리에 생기지
/// 않는 대신, 열린 뒤 디스크의 sidecar 가 사라지거나 깨지면 카탈로그 커밋 게이트
/// (<c>ValidateDeclaredSidecars</c>)가 이후의 저장을 <b>전부</b> 막습니다 — 종료 저장까지
/// 막혀 앱을 닫을 수도 없습니다. 수동 복구는 그 불일치를 메모리 기준으로 풉니다.
/// </para>
/// <para>
/// macOS 의 "복원 대기"(선언은 있는데 메모리 recipe 가 없는 사진)를 되살리거나 비우는 단계는
/// 옮기지 않았습니다. Windows 는 열 때 선언된 sidecar 를 모두 검사해 하나라도 못 읽으면 열기를
/// 거부하므로(<c>CatalogSession.Open</c> → <c>MissingAuthoritativeData</c>), 열린 라이브러리에는
/// 그런 사진이 없습니다. 열린 뒤 sidecar 가 사라지거나 깨지면 메모리 recipe 로 다시 쓰므로
/// 편집을 잃지 않고, 읽기 권한이 없거나 더 새 버전인 기록은 쓰기가 거부해 그대로 둡니다.
/// </para>
/// </remarks>
internal sealed class LibraryCatalogMaintenance(
    LibraryDocumentState state,
    Func<CatalogStoreError> save)
{
    private const string HasDefectEditsName = "hasDefectEdits";

    /// <summary>
    /// 수동 복구입니다. 카탈로그 파일은 그대로 두고, 결함 기록을 메모리 기준으로 다시 확정한 뒤
    /// 카탈로그를 저장합니다.
    /// </summary>
    internal LibraryCatalogMaintenanceResult Repair()
    {
        LibraryCatalogMaintenanceResult rewritten = RewriteMismatchedRecipes();
        if (!rewritten.IsSuccess)
        {
            return rewritten;
        }
        state.MarkDirty();
        CatalogStoreError saved = save();
        return saved == CatalogStoreError.None
            ? new(LibraryCatalogMaintenanceError.None)
            : new(LibraryCatalogMaintenanceError.CatalogSaveFailed, CatalogError: saved);
    }

    /// <summary>
    /// 재설치 준비입니다. 지금 메모리 라이브러리로 검증된 백업 세대를 만들고 다음 실행의 예약
    /// 복원으로 겁니다. 다음 실행이 열기 전에 카탈로그와 결함 폴더를 그 세대로 새로 깝니다.
    /// </summary>
    internal LibraryCatalogMaintenanceResult PrepareReinstall()
    {
        List<CatalogEntityRow> rows = [.. state.FrameRows().Where(row => !IsPreviewFrame(row.Payload))];
        Dictionary<Guid, DefectRecipeSnapshot> recipes = [];
        foreach (CatalogEntityRow row in rows)
        {
            if (DeclaresDefectEdits(row.Payload) &&
                state.DefectRecipes.TryGetValue(row.Id, out DefectRecipeSnapshot? recipe))
            {
                recipes[recipe.FrameId] = recipe;
            }
        }
        CatalogBackupCreateResult backup = state.Session.CreateBackupFromMemory(
            state.CreateSnapshot(rows),
            recipes);
        if (!backup.IsSuccess || backup.GenerationPath is not { Length: > 0 } generationPath)
        {
            return new(LibraryCatalogMaintenanceError.BackupFailed);
        }
        CatalogPendingRestoreScheduleResult scheduled = state.Session.ScheduleRestore(
            Path.GetFileName(generationPath));
        return scheduled.IsSuccess
            ? new(LibraryCatalogMaintenanceError.None)
            : new(LibraryCatalogMaintenanceError.ScheduleFailed);
    }

    /// <summary>
    /// 디스크 기록이 메모리 recipe 와 같은 세대가 아닌 사진만 다시 씁니다. 같은 revision 으로는
    /// revision floor 가 다시 쓰기를 막으므로, 이미 알려진 가장 높은 revision 보다 올려서 씁니다.
    /// </summary>
    private LibraryCatalogMaintenanceResult RewriteMismatchedRecipes()
    {
        bool changed = false;
        foreach ((string rowId, DefectRecipeSnapshot recipe) in state.DefectRecipes.ToArray())
        {
            if (!state.IndexById.TryGetValue(rowId, out int index) ||
                !DeclaresDefectEdits(state.Payloads[index]))
            {
                continue;
            }
            DefectSidecarReadResult disk = state.Session.ReadDefectRecipe(recipe.FrameId);
            if (disk.Snapshot is { } stored && IsSameGeneration(stored, recipe))
            {
                continue;
            }
            ulong known = Math.Max(
                Math.Max(recipe.RecipeRevision, state.DefectRevisions.Current(rowId)),
                state.Session.HighestKnownDefectRevision(recipe.FrameId));
            if (known == ulong.MaxValue)
            {
                return new(LibraryCatalogMaintenanceError.DefectRecipeRewriteFailed);
            }
            DefectRecipeSnapshot rewritten = DefectRecipeSnapshot.Create(
                recipe.FrameId,
                known + 1UL,
                recipe.SourceIdentity,
                recipe.Items);
            DefectSidecarWriteResult written = state.Session.RewriteDefectRecipeForRepair(rewritten);
            if (!written.IsSuccess || written.Kind == DefectSidecarWriteKind.SkippedNewer)
            {
                return new(
                    LibraryCatalogMaintenanceError.DefectRecipeRewriteFailed,
                    SidecarError: written.Error);
            }
            state.DefectRecipes[rowId] = rewritten;
            state.DefectRevisions.Observe(rowId, rewritten.RecipeRevision);
            changed = true;
        }
        if (changed)
        {
            state.ProjectFrames();
        }
        return new(LibraryCatalogMaintenanceError.None);
    }

    /// <summary>디스크 기록이 메모리 recipe 와 같은 내용·같은 revision 인지입니다.</summary>
    private static bool IsSameGeneration(DefectRecipeSnapshot stored, DefectRecipeSnapshot memory) =>
        stored.RecipeRevision == memory.RecipeRevision &&
        stored.FingerprintVersion == memory.FingerprintVersion &&
        string.Equals(stored.RecipeSha256, memory.RecipeSha256, StringComparison.Ordinal) &&
        stored.SourceIdentity == memory.SourceIdentity;

    private static bool DeclaresDefectEdits(JsonObject payload) =>
        payload.TryGetPropertyValue(HasDefectEditsName, out JsonNode? node) &&
        node is JsonValue value && value.TryGetValue(out bool declared) && declared;

    private static bool IsPreviewFrame(JsonObject payload) =>
        payload.TryGetPropertyValue(LibraryFrameReader.IsPreviewScanName, out JsonNode? value) &&
        value is JsonValue scalar && scalar.TryGetValue(out bool preview) && preview;
}
