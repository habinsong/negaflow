using System.Security.Cryptography;
using System.Text.Json;

namespace Negaflow.Catalog;

/// <summary>
/// live SQLite의 물리 형식과 분리된 검증 가능 logical backup generation을 만듭니다.
/// </summary>
internal static class CatalogBackupStore
{
    public const int DefaultRetentionCount = 3;

    internal const string CatalogFileName = "library.json";
    internal const string ManifestFileName = "manifest.json";
    internal const string DefectsDirectoryName = "defects";

    public static CatalogBackupCreateResult Create(
        StorageRootSet roots,
        DateTimeOffset createdAt,
        int retentionCount,
        Action<string>? beforeValidation = null)
    {
        ArgumentNullException.ThrowIfNull(roots);
        if (retentionCount < 1)
        {
            return CatalogBackupCreateResult.Failure(CatalogBackupError.InvalidRetention);
        }
        if (!CatalogBackupFiles.HasValidRoots(roots))
        {
            return CatalogBackupCreateResult.Failure(
                CatalogBackupError.InvalidStorageRoots);
        }

        CatalogReadResult read = SqliteCatalogStore.Read(roots.CatalogPath);
        if (read.Snapshot is not { } snapshot ||
            !CatalogBackupCodec.TryGetDefectFrameIds(snapshot, out IReadOnlyList<string>? defectFrameIds))
        {
            return CatalogBackupCreateResult.Failure(CatalogBackupError.InvalidCatalog);
        }
        DefectCatalogHealthResult defectHealth =
            DefectSidecarCatalogHealth.ValidateCatalogDeclarations(roots, snapshot);
        if (defectHealth.Entries is not { } defectEntries)
        {
            return CatalogBackupCreateResult.Failure(
                CatalogBackupError.DefectSidecarUnavailable);
        }
        return CreateGeneration(
            roots, snapshot, defectFrameIds, defectEntries, fromMemory: false,
            createdAt, retentionCount, beforeValidation);
    }

    /// <summary>
    /// 열린 문서의 <b>메모리 상태</b>로 세대를 만듭니다. 디스크의 카탈로그나 결함 기록이
    /// 어긋나 있어도 쓸 수 있어야 하는 자리(카탈로그 재설치)가 씁니다 — macOS 도 재설치는
    /// <c>makeManualBackupPayload()</c> 로 메모리 카탈로그와 recipe 를 담습니다.
    /// </summary>
    /// <param name="recipes">결함 편집을 선언한 사진마다의 recipe 입니다.</param>
    public static CatalogBackupCreateResult CreateFromMemory(
        StorageRootSet roots,
        CatalogSnapshot snapshot,
        IReadOnlyDictionary<Guid, DefectRecipeSnapshot> recipes,
        DateTimeOffset createdAt,
        int retentionCount)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentNullException.ThrowIfNull(recipes);
        if (retentionCount < 1)
        {
            return CatalogBackupCreateResult.Failure(CatalogBackupError.InvalidRetention);
        }
        if (!CatalogBackupFiles.HasValidRoots(roots))
        {
            return CatalogBackupCreateResult.Failure(
                CatalogBackupError.InvalidStorageRoots);
        }
        if (!CatalogBackupCodec.TryGetDefectFrameIds(snapshot, out IReadOnlyList<string>? defectFrameIds))
        {
            return CatalogBackupCreateResult.Failure(CatalogBackupError.InvalidCatalog);
        }
        List<DefectSidecarCatalogEntry> entries = [];
        foreach (string frameId in defectFrameIds)
        {
            if (!Guid.TryParseExact(frameId, "D", out Guid parsed) ||
                !recipes.TryGetValue(parsed, out DefectRecipeSnapshot? recipe) ||
                recipe.FrameId != parsed)
            {
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.DefectSidecarUnavailable);
            }
            entries.Add(new DefectSidecarCatalogEntry(frameId, parsed, string.Empty, recipe));
        }
        entries.Sort((left, right) => StringComparer.Ordinal.Compare(
            left.CatalogFrameId,
            right.CatalogFrameId));
        return CreateGeneration(
            roots, snapshot, defectFrameIds, entries, fromMemory: true,
            createdAt, retentionCount, beforeValidation: null);
    }

    /// <param name="fromMemory">
    /// 결함 기록을 디스크에서 복사하지 않고 <see cref="DefectSidecarCatalogEntry.Snapshot"/> 을
    /// sidecar 와 같은 바이트로 직렬화해 씁니다.
    /// </param>
    private static CatalogBackupCreateResult CreateGeneration(
        StorageRootSet roots,
        CatalogSnapshot snapshot,
        IReadOnlyList<string> defectFrameIds,
        IReadOnlyList<DefectSidecarCatalogEntry> defectEntries,
        bool fromMemory,
        DateTimeOffset createdAt,
        int retentionCount,
        Action<string>? beforeValidation)
    {
        string? stagingPath = null;
        bool promoted = false;
        try
        {
            if (File.Exists(roots.BackupRoot))
            {
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.InvalidStorageRoots);
            }
            Directory.CreateDirectory(roots.BackupRoot);
            if (StoragePathPolicy.IsExistingReparsePoint(roots.BackupRoot))
            {
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.InvalidStorageRoots);
            }

            if (!CatalogBackupGenerations.TryNextSequence(roots.BackupRoot, out ulong sequence))
            {
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.SequenceExhausted);
            }

            stagingPath = Path.Combine(
                roots.BackupRoot,
                $"staging-{Guid.NewGuid():N}.tmp");
            Directory.CreateDirectory(stagingPath);
            string defectsPath = Path.Combine(stagingPath, DefectsDirectoryName);
            Directory.CreateDirectory(defectsPath);

            byte[] catalogData = CatalogBackupCodec.SerializeCatalog(snapshot);
            string catalogPath = Path.Combine(stagingPath, CatalogFileName);
            CatalogBackupFiles.WriteDurable(catalogPath, catalogData);

            CatalogBackupFileRecord catalogRecord = CatalogBackupFiles.CreateFileRecord(
                CatalogFileName,
                catalogPath);
            List<CatalogBackupFileRecord> fileRecords = [catalogRecord];
            foreach (DefectSidecarCatalogEntry entry in defectEntries)
            {
                string fileName = DefectSidecarStore.FileName(entry.FrameId);
                string destination = Path.Combine(defectsPath, fileName);
                if (fromMemory)
                {
                    CatalogBackupFiles.WriteDurable(
                        destination,
                        DefectSidecarCodec.Serialize(entry.Snapshot));
                }
                else
                {
                    CatalogBackupFiles.CopyDurable(entry.Path, destination);
                }
                DefectSidecarReadResult copied = DefectSidecarFile.ReadFile(
                    destination,
                    entry.FrameId);
                if (copied.Snapshot is not { } copiedSnapshot ||
                    !DefectSidecarCodec.AreSameSnapshot(entry.Snapshot, copiedSnapshot))
                {
                    return CatalogBackupCreateResult.Failure(
                        CatalogBackupError.DefectSidecarUnavailable);
                }
                fileRecords.Add(CatalogBackupFiles.CreateFileRecord(
                    DefectSidecarStore.BackupRelativePath(entry.FrameId),
                    destination));
            }
            CatalogBackupManifest manifest = new(
                CatalogBackupManifest.CurrentVersion,
                sequence,
                createdAt.ToUniversalTime(),
                snapshot.Rows(CatalogEntityTable.Frames).Count,
                defectFrameIds,
                snapshot.CatalogVersion,
                fileRecords.OrderBy(
                    value => value.RelativePath,
                    StringComparer.Ordinal).ToArray());
            CatalogBackupFiles.WriteDurable(
                Path.Combine(stagingPath, ManifestFileName),
                CatalogBackupCodec.SerializeManifest(manifest));

            beforeValidation?.Invoke(stagingPath);
            CatalogBackupValidationResult validated = ValidateGeneration(stagingPath);
            if (!validated.IsValid || validated.Manifest?.Sequence != sequence)
            {
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.ValidationFailed);
            }

            string destinationPath = Path.Combine(
                roots.BackupRoot,
                CatalogBackupFiles.GenerationName(sequence, createdAt));
            if (File.Exists(destinationPath) || Directory.Exists(destinationPath) ||
                !CatalogBackupFiles.MoveDirectory(stagingPath, destinationPath))
            {
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.PromotionFailed);
            }
            promoted = true;
            CatalogBackupValidationResult promotedValidation = ValidateGeneration(
                destinationPath);
            if (!promotedValidation.IsValid ||
                promotedValidation.Manifest?.Sequence != sequence)
            {
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.ValidationFailed);
            }

            bool pruneFailed = !CatalogBackupGenerations.PruneValidatedGenerations(
                roots.BackupRoot,
                retentionCount);
            return CatalogBackupCreateResult.Success(
                destinationPath,
                sequence,
                pruneFailed);
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogBackupCreateResult.Failure(CatalogBackupError.AccessDenied);
        }
        catch (Exception error) when (error is
            IOException or NotSupportedException or JsonException or CryptographicException)
        {
            return CatalogBackupCreateResult.Failure(CatalogBackupError.IoFailure);
        }
        finally
        {
            if (!promoted && stagingPath is not null)
            {
                CatalogBackupGenerations.TryDeleteStaging(stagingPath, roots.BackupRoot);
            }
        }
    }

    internal static CatalogBackupValidationResult ValidateGeneration(string generationPath)
    {
        if (string.IsNullOrWhiteSpace(generationPath) ||
            !Path.IsPathFullyQualified(generationPath) ||
            !Directory.Exists(generationPath) ||
            StoragePathPolicy.IsExistingReparsePoint(generationPath))
        {
            return default;
        }

        try
        {
            string manifestPath = Path.Combine(generationPath, ManifestFileName);
            string catalogPath = Path.Combine(generationPath, CatalogFileName);
            string defectsPath = Path.Combine(generationPath, DefectsDirectoryName);
            if (!CatalogBackupFiles.IsRegularFile(manifestPath) ||
                !CatalogBackupFiles.IsRegularFile(catalogPath) ||
                !Directory.Exists(defectsPath) ||
                StoragePathPolicy.IsExistingReparsePoint(defectsPath))
            {
                return default;
            }

            HashSet<string> expectedTopLevel = new(
                [ManifestFileName, CatalogFileName, DefectsDirectoryName],
                StringComparer.Ordinal);
            string[] actualTopLevel = Directory.EnumerateFileSystemEntries(generationPath)
                .Select(Path.GetFileName)
                .Where(name => name is not null)
                .Cast<string>()
                .ToArray();
            if (actualTopLevel.Length != expectedTopLevel.Count ||
                actualTopLevel.Any(name => !expectedTopLevel.Contains(name)))
            {
                return default;
            }

            byte[] manifestData = File.ReadAllBytes(manifestPath);
            if (!CatalogBackupCodec.TryDeserializeManifest(manifestData, out CatalogBackupManifest manifest) ||
                manifest.Version != CatalogBackupManifest.CurrentVersion ||
                !manifestData.AsSpan().SequenceEqual(CatalogBackupCodec.SerializeManifest(manifest)))
            {
                return default;
            }

            byte[] catalogData = File.ReadAllBytes(catalogPath);
            if (!CatalogBackupCodec.TryDeserializeCatalog(catalogData, out CatalogSnapshot snapshot) ||
                !catalogData.AsSpan().SequenceEqual(CatalogBackupCodec.SerializeCatalog(snapshot)) ||
                snapshot.CatalogVersion != manifest.CatalogVersion ||
                snapshot.Rows(CatalogEntityTable.Frames).Count != manifest.FrameCount ||
                !CatalogBackupCodec.TryGetDefectFrameIds(snapshot, out IReadOnlyList<string> defectFrameIds) ||
                !defectFrameIds.SequenceEqual(
                    manifest.DefectFrameIds,
                    StringComparer.Ordinal))
            {
                return default;
            }

            Dictionary<string, CatalogBackupFileRecord> actualFiles =
                new(StringComparer.Ordinal)
                {
                    [CatalogFileName] = CatalogBackupFiles.CreateFileRecord(CatalogFileName, catalogPath),
                };
            HashSet<string> expectedDefectNames = new(StringComparer.OrdinalIgnoreCase);
            foreach (string catalogFrameId in defectFrameIds)
            {
                if (!Guid.TryParseExact(catalogFrameId, "D", out Guid frameId) ||
                    frameId == Guid.Empty)
                {
                    return default;
                }
                string fileName = DefectSidecarStore.FileName(frameId);
                if (!expectedDefectNames.Add(fileName))
                {
                    return default;
                }
                string path = Path.Combine(defectsPath, fileName);
                DefectSidecarReadResult sidecar = DefectSidecarFile.ReadFile(
                    path,
                    frameId);
                if (!sidecar.IsSuccess)
                {
                    return default;
                }
                string relativePath = DefectSidecarStore.BackupRelativePath(frameId);
                actualFiles[relativePath] = CatalogBackupFiles.CreateFileRecord(relativePath, path);
            }

            string[] actualDefectEntries = Directory.EnumerateFileSystemEntries(
                defectsPath,
                "*",
                SearchOption.TopDirectoryOnly).ToArray();
            if (actualDefectEntries.Length != expectedDefectNames.Count ||
                actualDefectEntries.Any(path =>
                    !CatalogBackupFiles.IsRegularFile(path) ||
                    !expectedDefectNames.Contains(Path.GetFileName(path))))
            {
                return default;
            }

            CatalogBackupFileRecord[] expectedRecords = actualFiles.Values
                .OrderBy(value => value.RelativePath, StringComparer.Ordinal)
                .ToArray();
            if (!manifest.Files.SequenceEqual(expectedRecords))
            {
                return default;
            }
            return new CatalogBackupValidationResult(snapshot, manifest);
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or NotSupportedException or
            JsonException or CryptographicException)
        {
            return default;
        }
    }
}
