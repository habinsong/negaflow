using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// live SQLite의 물리 형식과 분리된 검증 가능 logical backup generation을 만듭니다.
/// </summary>
internal static class CatalogBackupStore
{
    public const int DefaultRetentionCount = 3;

    private const string CatalogFileName = "library.json";
    private const string ManifestFileName = "manifest.json";
    private const string DefectsDirectoryName = "defects";
    private const uint MoveFileWriteThrough = 0x00000008;

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
        if (!HasValidRoots(roots))
        {
            return CatalogBackupCreateResult.Failure(
                CatalogBackupError.InvalidStorageRoots);
        }

        CatalogReadResult read = SqliteCatalogStore.Read(roots.CatalogPath);
        if (read.Snapshot is not { } snapshot ||
            !TryGetDefectFrameIds(snapshot, out IReadOnlyList<string>? defectFrameIds))
        {
            return CatalogBackupCreateResult.Failure(CatalogBackupError.InvalidCatalog);
        }
        DefectCatalogHealthResult defectHealth =
            DefectSidecarStore.ValidateCatalogDeclarations(roots, snapshot);
        if (defectHealth.Entries is not { } defectEntries)
        {
            return CatalogBackupCreateResult.Failure(
                CatalogBackupError.DefectSidecarUnavailable);
        }

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

            if (!TryNextSequence(roots.BackupRoot, out ulong sequence))
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

            byte[] catalogData = SerializeCatalog(snapshot);
            string catalogPath = Path.Combine(stagingPath, CatalogFileName);
            WriteDurable(catalogPath, catalogData);

            CatalogBackupFileRecord catalogRecord = CreateFileRecord(
                CatalogFileName,
                catalogPath);
            List<CatalogBackupFileRecord> fileRecords = [catalogRecord];
            foreach (DefectSidecarCatalogEntry entry in defectEntries)
            {
                string fileName = DefectSidecarStore.FileName(entry.FrameId);
                string destination = Path.Combine(defectsPath, fileName);
                CopyDurable(entry.Path, destination);
                DefectSidecarReadResult copied = DefectSidecarStore.ReadFile(
                    destination,
                    entry.FrameId);
                if (copied.Snapshot is not { } copiedSnapshot ||
                    !DefectSidecarCodec.AreSameSnapshot(entry.Snapshot, copiedSnapshot))
                {
                    return CatalogBackupCreateResult.Failure(
                        CatalogBackupError.DefectSidecarUnavailable);
                }
                fileRecords.Add(CreateFileRecord(
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
            WriteDurable(
                Path.Combine(stagingPath, ManifestFileName),
                SerializeManifest(manifest));

            beforeValidation?.Invoke(stagingPath);
            CatalogBackupValidationResult validated = ValidateGeneration(stagingPath);
            if (!validated.IsValid || validated.Manifest?.Sequence != sequence)
            {
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.ValidationFailed);
            }

            string destinationPath = Path.Combine(
                roots.BackupRoot,
                GenerationName(sequence, createdAt));
            if (File.Exists(destinationPath) || Directory.Exists(destinationPath) ||
                !MoveDirectory(stagingPath, destinationPath))
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

            bool pruneFailed = !PruneValidatedGenerations(
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
                TryDeleteStaging(stagingPath, roots.BackupRoot);
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
            if (!IsRegularFile(manifestPath) ||
                !IsRegularFile(catalogPath) ||
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
            if (!TryDeserializeManifest(manifestData, out CatalogBackupManifest manifest) ||
                manifest.Version != CatalogBackupManifest.CurrentVersion ||
                !manifestData.AsSpan().SequenceEqual(SerializeManifest(manifest)))
            {
                return default;
            }

            byte[] catalogData = File.ReadAllBytes(catalogPath);
            if (!TryDeserializeCatalog(catalogData, out CatalogSnapshot snapshot) ||
                !catalogData.AsSpan().SequenceEqual(SerializeCatalog(snapshot)) ||
                snapshot.CatalogVersion != manifest.CatalogVersion ||
                snapshot.Rows(CatalogEntityTable.Frames).Count != manifest.FrameCount ||
                !TryGetDefectFrameIds(snapshot, out IReadOnlyList<string> defectFrameIds) ||
                !defectFrameIds.SequenceEqual(
                    manifest.DefectFrameIds,
                    StringComparer.Ordinal))
            {
                return default;
            }

            Dictionary<string, CatalogBackupFileRecord> actualFiles =
                new(StringComparer.Ordinal)
                {
                    [CatalogFileName] = CreateFileRecord(CatalogFileName, catalogPath),
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
                DefectSidecarReadResult sidecar = DefectSidecarStore.ReadFile(
                    path,
                    frameId);
                if (!sidecar.IsSuccess)
                {
                    return default;
                }
                string relativePath = DefectSidecarStore.BackupRelativePath(frameId);
                actualFiles[relativePath] = CreateFileRecord(relativePath, path);
            }

            string[] actualDefectEntries = Directory.EnumerateFileSystemEntries(
                defectsPath,
                "*",
                SearchOption.TopDirectoryOnly).ToArray();
            if (actualDefectEntries.Length != expectedDefectNames.Count ||
                actualDefectEntries.Any(path =>
                    !IsRegularFile(path) ||
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

    private static bool HasValidRoots(StorageRootSet roots) =>
        Path.IsPathFullyQualified(roots.LibraryRoot) &&
        Path.IsPathFullyQualified(roots.CatalogPath) &&
        Path.IsPathFullyQualified(roots.BackupRoot) &&
        Path.IsPathFullyQualified(roots.DefectRecipeRoot) &&
        StoragePathPolicy.IsLexicallyContained(roots.LibraryRoot, roots.CatalogPath) &&
        StoragePathPolicy.IsLexicallyContained(roots.LibraryRoot, roots.BackupRoot) &&
        StoragePathPolicy.IsLexicallyContained(
            roots.LibraryRoot,
            roots.DefectRecipeRoot) &&
        !StoragePathPolicy.IsExistingReparsePoint(roots.LibraryRoot) &&
        !StoragePathPolicy.IsExistingReparsePoint(roots.CatalogPath) &&
        !StoragePathPolicy.IsExistingReparsePoint(roots.BackupRoot) &&
        !StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot);

    private static bool TryNextSequence(string backupRoot, out ulong sequence)
    {
        ulong maximum = 0;
        foreach (string directory in Directory.EnumerateDirectories(
            backupRoot,
            "backup-*",
            SearchOption.TopDirectoryOnly))
        {
            if (StoragePathPolicy.IsExistingReparsePoint(directory))
            {
                continue;
            }
            string manifestPath = Path.Combine(directory, ManifestFileName);
            if (!IsRegularFile(manifestPath) ||
                !TryReadManifestSequence(manifestPath, out ulong candidate))
            {
                continue;
            }
            maximum = Math.Max(maximum, candidate);
        }
        if (maximum == ulong.MaxValue)
        {
            sequence = 0;
            return false;
        }
        sequence = maximum + 1;
        return true;
    }

    private static bool TryReadManifestSequence(string manifestPath, out ulong sequence)
    {
        sequence = 0;
        try
        {
            JsonNode? node = JsonNode.Parse(File.ReadAllBytes(manifestPath));
            return node is JsonObject root &&
                root["sequence"] is JsonValue value &&
                value.TryGetValue(out sequence);
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or JsonException)
        {
            return false;
        }
    }

    private static bool PruneValidatedGenerations(string backupRoot, int retentionCount)
    {
        try
        {
            bool succeeded = true;
            List<(string Path, CatalogBackupManifest Manifest)> valid = [];
            foreach (string directory in Directory.EnumerateDirectories(
                backupRoot,
                "backup-*",
                SearchOption.TopDirectoryOnly))
            {
                CatalogBackupValidationResult validation = ValidateGeneration(directory);
                if (validation.Manifest is { } manifest)
                {
                    valid.Add((directory, manifest));
                }
            }

            foreach ((string path, _) in valid
                .OrderByDescending(item => item.Manifest.Sequence)
                .ThenByDescending(item => item.Path, StringComparer.Ordinal)
                .Skip(retentionCount))
            {
                if (!TryDeleteGeneration(path, backupRoot))
                {
                    succeeded = false;
                }
            }
            return succeeded;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static bool TryDeleteGeneration(string path, string backupRoot)
    {
        try
        {
            CatalogBackupValidationResult validation = ValidateGeneration(path);
            if (!IsDirectChild(backupRoot, path) ||
                !Path.GetFileName(path).StartsWith("backup-", StringComparison.Ordinal) ||
                validation.Manifest is not { } manifest ||
                StoragePathPolicy.IsExistingReparsePoint(path))
            {
                return false;
            }

            string manifestPath = Path.Combine(path, ManifestFileName);
            string catalogPath = Path.Combine(path, CatalogFileName);
            string defectsPath = Path.Combine(path, DefectsDirectoryName);
            foreach (CatalogBackupFileRecord file in manifest.Files.Where(value =>
                value.RelativePath.StartsWith("defects/", StringComparison.Ordinal)))
            {
                string fileName = file.RelativePath["defects/".Length..];
                if (!string.Equals(fileName, Path.GetFileName(fileName), StringComparison.Ordinal) ||
                    !TryDeleteRegularFile(Path.Combine(defectsPath, fileName)))
                {
                    return false;
                }
            }
            File.Delete(manifestPath);
            File.Delete(catalogPath);
            Directory.Delete(defectsPath, recursive: false);
            Directory.Delete(path, recursive: false);
            return !Directory.Exists(path) && !File.Exists(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static void TryDeleteStaging(string path, string backupRoot)
    {
        try
        {
            string name = Path.GetFileName(path);
            if (IsDirectChild(backupRoot, path) &&
                name.StartsWith("staging-", StringComparison.Ordinal) &&
                name.EndsWith(".tmp", StringComparison.Ordinal) &&
                !StoragePathPolicy.IsExistingReparsePoint(path) &&
                Directory.Exists(path))
            {
                TryDeleteRegularFile(Path.Combine(path, ManifestFileName));
                TryDeleteRegularFile(Path.Combine(path, CatalogFileName));
                string defectsPath = Path.Combine(path, DefectsDirectoryName);
                if (Directory.Exists(defectsPath) &&
                    !StoragePathPolicy.IsExistingReparsePoint(defectsPath))
                {
                    foreach (string candidate in Directory.EnumerateFiles(
                        defectsPath,
                        "*.json",
                        SearchOption.TopDirectoryOnly))
                    {
                        string fileStem = Path.GetFileNameWithoutExtension(candidate);
                        if (Guid.TryParseExact(fileStem, "D", out _))
                        {
                            TryDeleteRegularFile(candidate);
                        }
                    }
                    if (!Directory.EnumerateFileSystemEntries(defectsPath).Any())
                    {
                        Directory.Delete(defectsPath, recursive: false);
                    }
                }
                if (!Directory.EnumerateFileSystemEntries(path).Any())
                {
                    Directory.Delete(path, recursive: false);
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 실패한 staging은 valid generation 이름이 아니며 다음 정리에서 식별할 수 있습니다.
        }
    }

    private static bool TryDeleteRegularFile(string path)
    {
        if (IsRegularFile(path))
        {
            File.Delete(path);
        }
        return !File.Exists(path) && !Directory.Exists(path);
    }

    private static bool IsDirectChild(string parent, string child)
    {
        try
        {
            string normalizedParent = Path.TrimEndingDirectorySeparator(
                Path.GetFullPath(parent));
            string? childParent = Path.GetDirectoryName(Path.GetFullPath(child));
            return string.Equals(
                normalizedParent,
                childParent is null
                    ? string.Empty
                    : Path.TrimEndingDirectorySeparator(childParent),
                StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    private static byte[] SerializeCatalog(CatalogSnapshot snapshot)
    {
        JsonObject entities = [];
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            JsonArray rows = [];
            foreach (CatalogEntityRow row in snapshot.Rows(table))
            {
                rows.Add(new JsonObject
                {
                    ["id"] = row.Id,
                    ["payload"] = row.Payload.DeepClone(),
                });
            }
            entities[CatalogEntityTables.SqlName(table)] = rows;
        }

        JsonObject root = new()
        {
            ["version"] = snapshot.CatalogVersion,
            ["minimumReaderVersion"] = snapshot.MinimumReaderVersion,
            ["activeRollId"] = snapshot.ActiveRollId,
            ["entities"] = entities,
        };
        return CatalogJson.SerializeCanonical(root);
    }

    private static bool TryDeserializeCatalog(byte[] data, out CatalogSnapshot snapshot)
    {
        snapshot = null!;
        try
        {
            if (JsonNode.Parse(data) is not JsonObject root ||
                !HasExactProperties(
                    root,
                    "version",
                    "minimumReaderVersion",
                    "activeRollId",
                    "entities") ||
                !TryInt32(root["version"], out int version) ||
                !TryInt32(root["minimumReaderVersion"], out int minimumReaderVersion) ||
                version != CatalogSnapshot.CurrentCatalogVersion ||
                minimumReaderVersion != CatalogSnapshot.OldestReaderVersion ||
                root["entities"] is not JsonObject entities ||
                entities.Count != CatalogEntityTables.All.Count)
            {
                return false;
            }

            string? activeRollId = null;
            if (root["activeRollId"] is JsonNode activeNode &&
                (activeNode is not JsonValue activeValue ||
                 !activeValue.TryGetValue(out activeRollId)))
            {
                return false;
            }

            Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = [];
            foreach (CatalogEntityTable table in CatalogEntityTables.All)
            {
                string tableName = CatalogEntityTables.SqlName(table);
                if (entities[tableName] is not JsonArray rows)
                {
                    return false;
                }

                HashSet<string> ids = new(StringComparer.Ordinal);
                List<CatalogEntityRow> decodedRows = [];
                foreach (JsonNode? node in rows)
                {
                    if (node is not JsonObject row ||
                        !HasExactProperties(row, "id", "payload") ||
                        row["id"] is not JsonValue idValue ||
                        !idValue.TryGetValue(out string? id) ||
                        string.IsNullOrWhiteSpace(id) ||
                        !ids.Add(id) ||
                        row["payload"] is not JsonObject payload)
                    {
                        return false;
                    }
                    _ = CatalogJson.SerializeCanonical(payload);
                    decodedRows.Add(new CatalogEntityRow(
                        id,
                        (JsonObject)payload.DeepClone()));
                }
                tables[table] = decodedRows;
            }
            if (entities.Any(property =>
                !CatalogEntityTables.All.Any(table => string.Equals(
                    CatalogEntityTables.SqlName(table),
                    property.Key,
                    StringComparison.Ordinal))))
            {
                return false;
            }

            snapshot = new CatalogSnapshot(
                version,
                minimumReaderVersion,
                activeRollId,
                tables);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static byte[] SerializeManifest(CatalogBackupManifest manifest)
    {
        JsonArray defectIds = [];
        foreach (string id in manifest.DefectFrameIds)
        {
            defectIds.Add(id);
        }
        JsonArray files = [];
        foreach (CatalogBackupFileRecord file in manifest.Files
            .OrderBy(value => value.RelativePath, StringComparer.Ordinal))
        {
            files.Add(new JsonObject
            {
                ["relativePath"] = file.RelativePath,
                ["byteCount"] = file.ByteCount,
                ["sha256"] = file.Sha256,
            });
        }
        return CatalogJson.SerializeCanonical(new JsonObject
        {
            ["version"] = manifest.Version,
            ["sequence"] = manifest.Sequence,
            ["createdAt"] = manifest.CreatedAt.ToUniversalTime()
                .ToString("O", CultureInfo.InvariantCulture),
            ["frameCount"] = manifest.FrameCount,
            ["defectFrameIDs"] = defectIds,
            ["catalogVersion"] = manifest.CatalogVersion,
            ["files"] = files,
        });
    }

    private static bool TryDeserializeManifest(
        byte[] data,
        out CatalogBackupManifest manifest)
    {
        manifest = null!;
        try
        {
            if (JsonNode.Parse(data) is not JsonObject root ||
                !HasExactProperties(
                    root,
                    "version",
                    "sequence",
                    "createdAt",
                    "frameCount",
                    "defectFrameIDs",
                    "catalogVersion",
                    "files") ||
                !TryInt32(root["version"], out int version) ||
                root["sequence"] is not JsonValue sequenceValue ||
                !sequenceValue.TryGetValue(out ulong sequence) ||
                root["createdAt"] is not JsonValue createdValue ||
                !createdValue.TryGetValue(out string? createdText) ||
                !DateTimeOffset.TryParse(
                    createdText,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind,
                    out DateTimeOffset createdAt) ||
                !TryInt32(root["frameCount"], out int frameCount) ||
                frameCount < 0 ||
                !TryInt32(root["catalogVersion"], out int catalogVersion) ||
                root["defectFrameIDs"] is not JsonArray defectNodes ||
                root["files"] is not JsonArray fileNodes)
            {
                return false;
            }

            List<string> defectIds = [];
            foreach (JsonNode? node in defectNodes)
            {
                if (node is not JsonValue value ||
                    !value.TryGetValue(out string? id) ||
                    string.IsNullOrWhiteSpace(id))
                {
                    return false;
                }
                defectIds.Add(id);
            }
            if (!defectIds.SequenceEqual(
                    defectIds.OrderBy(value => value, StringComparer.Ordinal)) ||
                defectIds.Distinct(StringComparer.Ordinal).Count() != defectIds.Count)
            {
                return false;
            }

            List<CatalogBackupFileRecord> files = [];
            foreach (JsonNode? node in fileNodes)
            {
                if (node is not JsonObject file ||
                    !HasExactProperties(file, "relativePath", "byteCount", "sha256") ||
                    file["relativePath"] is not JsonValue pathValue ||
                    !pathValue.TryGetValue(out string? relativePath) ||
                    string.IsNullOrWhiteSpace(relativePath) ||
                    Path.IsPathRooted(relativePath) ||
                    relativePath.Contains("..", StringComparison.Ordinal) ||
                    file["byteCount"] is not JsonValue byteValue ||
                    !byteValue.TryGetValue(out long byteCount) ||
                    byteCount < 0 ||
                    file["sha256"] is not JsonValue hashValue ||
                    !hashValue.TryGetValue(out string? sha256) ||
                    sha256.Length != 64 ||
                    sha256.Any(character => !Uri.IsHexDigit(character)))
                {
                    return false;
                }
                files.Add(new CatalogBackupFileRecord(
                    relativePath,
                    byteCount,
                    sha256.ToLowerInvariant()));
            }
            if (!files.SequenceEqual(files.OrderBy(
                    value => value.RelativePath,
                    StringComparer.Ordinal)))
            {
                return false;
            }

            manifest = new CatalogBackupManifest(
                version,
                sequence,
                createdAt,
                frameCount,
                defectIds,
                catalogVersion,
                files);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool HasExactProperties(JsonObject value, params string[] names)
    {
        if (value.Count != names.Length)
        {
            return false;
        }
        HashSet<string> expected = new(names, StringComparer.Ordinal);
        return value.All(property => expected.Contains(property.Key));
    }

    private static bool TryInt32(JsonNode? node, out int value)
    {
        value = 0;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    private static bool TryGetDefectFrameIds(
        CatalogSnapshot snapshot,
        out IReadOnlyList<string> ids)
    {
        List<string> values = [];
        foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
        {
            if (!frame.Payload.TryGetPropertyValue("hasDefectEdits", out JsonNode? node) ||
                node is null)
            {
                continue;
            }
            if (node is not JsonValue value || !value.TryGetValue(out bool hasEdits))
            {
                ids = [];
                return false;
            }
            if (hasEdits)
            {
                values.Add(frame.Id);
            }
        }
        ids = values.OrderBy(value => value, StringComparer.Ordinal).ToArray();
        return true;
    }

    private static CatalogBackupFileRecord CreateFileRecord(
        string relativePath,
        string path)
    {
        if (!IsRegularFile(path))
        {
            throw new IOException("Backup authoritative path is not a regular file.");
        }
        using FileStream stream = new(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 1024 * 1024,
            FileOptions.SequentialScan);
        byte[] digest = SHA256.HashData(stream);
        return new CatalogBackupFileRecord(
            relativePath,
            stream.Length,
            Convert.ToHexStringLower(digest));
    }

    private static bool IsRegularFile(string path)
    {
        if (!File.Exists(path) || StoragePathPolicy.IsExistingReparsePoint(path))
        {
            return false;
        }
        return (File.GetAttributes(path) & FileAttributes.Directory) == 0;
    }

    private static void CopyDurable(string sourcePath, string destinationPath)
    {
        if (!IsRegularFile(sourcePath))
        {
            throw new IOException("Backup source is not a regular file.");
        }
        using FileStream source = new(
            sourcePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 1024 * 1024,
            FileOptions.SequentialScan);
        using FileStream destination = new(
            destinationPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 1024 * 1024,
            FileOptions.WriteThrough);
        source.CopyTo(destination);
        destination.Flush(flushToDisk: true);
    }

    private static void WriteDurable(string path, byte[] data)
    {
        using FileStream stream = new(
            path,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 1024 * 1024,
            FileOptions.WriteThrough);
        stream.Write(data);
        stream.Flush(flushToDisk: true);
    }

    private static string GenerationName(ulong sequence, DateTimeOffset createdAt) =>
        $"backup-{sequence.ToString("D20", CultureInfo.InvariantCulture)}-" +
        $"{createdAt.ToUniversalTime():yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}";

    private static bool MoveDirectory(string sourcePath, string destinationPath) =>
        MoveFileEx(
            ToExtendedPath(sourcePath),
            ToExtendedPath(destinationPath),
            MoveFileWriteThrough);

    private static string ToExtendedPath(string path)
    {
        string fullPath = Path.GetFullPath(path);
        if (fullPath.StartsWith(@"\\?\", StringComparison.Ordinal))
        {
            return fullPath;
        }
        return fullPath.StartsWith(@"\\", StringComparison.Ordinal)
            ? @"\\?\UNC\" + fullPath[2..]
            : @"\\?\" + fullPath;
    }

    [DllImport(
        "kernel32.dll",
        EntryPoint = "MoveFileExW",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MoveFileEx(
        string existingFileName,
        string newFileName,
        uint flags);
}
