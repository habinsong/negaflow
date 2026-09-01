using System.Security.Cryptography;
using System.Text.Json;

namespace Negaflow.Catalog;

/// <summary>
/// 세대 하나가 지금 어떤 상태인지입니다. macOS <c>LibraryBackupGeneration.State</c> 자리이되,
/// Windows 검증은 전부 맞거나 아니거나이므로 등급이 넷이 아니라 셋입니다.
/// </summary>
public enum CatalogBackupGenerationState
{
    /// <summary>매니페스트·체크섬·결함 기록이 모두 맞습니다. 복원할 수 있습니다.</summary>
    Verified,

    /// <summary>매니페스트는 읽었지만 내용이 어긋납니다. 복원하면 안 됩니다.</summary>
    Damaged,

    /// <summary>매니페스트조차 읽지 못했습니다 — 만들다 만 세대일 수 있습니다.</summary>
    Unreadable,
}

/// <summary>
/// 사용자에게 보여 줄 백업 세대 한 건입니다. <see cref="Id"/> 는 폴더 이름이며
/// <see cref="CatalogSession.ScheduleRestore"/> 가 그대로 받습니다.
/// </summary>
public sealed record CatalogBackupGeneration(
    string Id,
    ulong? Sequence,
    DateTimeOffset? CreatedAt,
    int? FrameCount,
    int? DefectRecipeCount,
    int? CatalogVersion,
    CatalogBackupGenerationState State)
{
    /// <summary>
    /// 이 세대로 되돌릴 수 있는지입니다. <c>false</c> 인 세대는 <b>왜</b> 안 되는지를
    /// <see cref="State"/> 로 보여 주어야 합니다 — 이유 없이 비활성인 버튼은 버그로 보입니다.
    /// </summary>
    public bool IsRestorable => State == CatalogBackupGenerationState.Verified;
}

/// <summary>
/// 백업 세대를 사용자에게 보여 주기 위해 훑습니다. 지원 번들만이 아니라 복구 화면과
/// 설정 · 디스크 탭도 이 목록을 봅니다.
/// </summary>
public static class CatalogBackupInspector
{
    /// <summary>새 것이 먼저 옵니다. 폴더를 못 읽으면 빈 목록입니다.</summary>
    public static IReadOnlyList<CatalogBackupGeneration> Enumerate(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        List<CatalogBackupGeneration> generations = [];
        try
        {
            if (!Directory.Exists(roots.BackupRoot))
            {
                return generations;
            }
            foreach (string directory in Directory.EnumerateDirectories(
                roots.BackupRoot,
                "backup-*",
                SearchOption.TopDirectoryOnly))
            {
                generations.Add(Inspect(directory));
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return generations;
        }
        return [.. generations
            .OrderByDescending(generation => generation.Sequence ?? 0)
            .ThenByDescending(generation => generation.Id, StringComparer.Ordinal)];
    }

    private static CatalogBackupGeneration Inspect(string directory)
    {
        string id = Path.GetFileName(directory);
        CatalogBackupValidationResult validated = CatalogBackupStore.ValidateGeneration(directory);
        if (validated.Manifest is { } manifest)
        {
            return Describe(id, manifest, CatalogBackupGenerationState.Verified);
        }
        // 검증에 실패해도 매니페스트만 따로 읽어 봅니다 — 언제 만든 몇 장짜리였는지는
        // 알려 줄 수 있어야 사용자가 무엇을 잃는지 압니다.
        return TryReadManifest(directory, out CatalogBackupManifest damaged)
            ? Describe(id, damaged, CatalogBackupGenerationState.Damaged)
            : new CatalogBackupGeneration(
                id,
                null,
                null,
                null,
                null,
                null,
                CatalogBackupGenerationState.Unreadable);
    }

    private static CatalogBackupGeneration Describe(
        string id,
        CatalogBackupManifest manifest,
        CatalogBackupGenerationState state) =>
        new(
            id,
            manifest.Sequence,
            manifest.CreatedAt,
            manifest.FrameCount,
            manifest.DefectFrameIds.Count,
            manifest.CatalogVersion,
            state);

    private static bool TryReadManifest(string directory, out CatalogBackupManifest manifest)
    {
        manifest = default!;
        try
        {
            string manifestPath = Path.Combine(directory, CatalogBackupStore.ManifestFileName);
            return CatalogBackupFiles.IsRegularFile(manifestPath) &&
                CatalogBackupCodec.TryDeserializeManifest(
                    File.ReadAllBytes(manifestPath),
                    out manifest);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or JsonException or CryptographicException)
        {
            return false;
        }
    }
}
