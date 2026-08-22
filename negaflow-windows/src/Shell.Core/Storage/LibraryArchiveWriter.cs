using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Negaflow.Catalog;

namespace Negaflow.Shell.Storage;

public enum LibraryArchiveError
{
    None,
    CatalogMissing,
    ArchiveFailed,
    PublicationFailed,
}

/// <summary>
/// 보존 아카이브입니다. macOS <c>LibraryArchiveButton</c> 이 만드는 것과 같은 내용 —
/// 카탈로그 + 결함 레시피 + 무엇이 들었는지 적은 목록 하나.
/// </summary>
/// <remarks>
/// <para>
/// <b>사진 원본은 담지 않습니다.</b> 원본은 사용자가 고른 디스크 자리에 있고, 수십 GB 를
/// 다시 복사하는 것은 보존이 아니라 낭비입니다. 이 아카이브는 "무엇을 어떻게 현상했는지"를
/// 지키는 것이며, 목록에 원본의 해시를 적어 나중에 짝을 맞출 수 있게 합니다.
/// </para>
/// <para>
/// 목록에는 파일마다 SHA-256 을 적습니다. 압축을 풀었을 때 바이트가 그대로인지 확인할 수
/// 없으면 보존본이라 부를 수 없습니다.
/// </para>
/// </remarks>
public static class LibraryArchiveWriter
{
    public const string ManifestName = "archive.json";

    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public sealed record ArchiveEntry(string RelativePath, long ByteCount, string Sha256);

    public sealed record ArchiveManifest(
        int Version,
        DateTimeOffset CreatedAt,
        IReadOnlyList<ArchiveEntry> Files)
    {
        public const int CurrentVersion = 1;
    }

    public static LibraryArchiveError Write(
        StorageRootSet roots,
        string destinationPath,
        DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentException.ThrowIfNullOrWhiteSpace(destinationPath);
        if (!File.Exists(roots.CatalogPath))
        {
            return LibraryArchiveError.CatalogMissing;
        }

        string staged = Path.Combine(
            Path.GetTempPath(), $"negaflow-archive-{Guid.NewGuid():N}.zip");
        List<ArchiveEntry> entries = [];
        try
        {
            using (FileStream stream = File.Create(staged))
            using (ZipArchive archive = new(stream, ZipArchiveMode.Create))
            {
                AddFile(archive, roots.CatalogPath, "library.sqlite", entries);
                foreach (string recipe in EnumerateFiles(roots.DefectRecipeRoot))
                {
                    string relative = Path.Combine(
                        "defects", Path.GetRelativePath(roots.DefectRecipeRoot, recipe));
                    AddFile(archive, recipe, relative.Replace('\\', '/'), entries);
                }
                ZipArchiveEntry manifest = archive.CreateEntry(ManifestName);
                using Stream manifestStream = manifest.Open();
                manifestStream.Write(JsonSerializer.SerializeToUtf8Bytes(
                    new ArchiveManifest(ArchiveManifest.CurrentVersion, now, entries), Json));
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or InvalidDataException)
        {
            TryDelete(staged);
            return LibraryArchiveError.ArchiveFailed;
        }

        try
        {
            if (Path.GetDirectoryName(destinationPath) is { Length: > 0 } parent)
            {
                Directory.CreateDirectory(parent);
            }
            File.Move(staged, destinationPath, overwrite: true);
            return LibraryArchiveError.None;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            TryDelete(staged);
            return LibraryArchiveError.PublicationFailed;
        }
    }

    private static IEnumerable<string> EnumerateFiles(string root)
    {
        if (!Directory.Exists(root))
        {
            yield break;
        }
        foreach (string file in Directory.EnumerateFiles(
            root, "*", SearchOption.AllDirectories))
        {
            yield return file;
        }
    }

    private static void AddFile(
        ZipArchive archive,
        string sourcePath,
        string relativePath,
        List<ArchiveEntry> entries)
    {
        ZipArchiveEntry entry = archive.CreateEntry(relativePath, CompressionLevel.Optimal);
        using FileStream source = File.OpenRead(sourcePath);
        using Stream target = entry.Open();
        // 해시는 쓰면서 함께 구합니다 — 큰 카탈로그를 두 번 읽지 않습니다.
        using IncrementalHash hasher = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        byte[] buffer = System.Buffers.ArrayPool<byte>.Shared.Rent(128 * 1024);
        long total = 0;
        try
        {
            int read;
            while ((read = source.Read(buffer, 0, buffer.Length)) > 0)
            {
                target.Write(buffer, 0, read);
                hasher.AppendData(buffer, 0, read);
                total += read;
            }
        }
        finally
        {
            System.Buffers.ArrayPool<byte>.Shared.Return(buffer);
        }
        entries.Add(new ArchiveEntry(
            relativePath, total, Convert.ToHexStringLower(hasher.GetHashAndReset())));
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 임시 파일입니다.
        }
    }

    /// <summary>기본 파일 이름입니다. macOS "negaflow Library.negaflowarchive" 와 같은 뜻입니다.</summary>
    public static string DefaultFileName(DateTimeOffset now) => string.Create(
        System.Globalization.CultureInfo.InvariantCulture,
        $"negaflow Library {now:yyyyMMdd-HHmmss}");

    /// <summary>목록만 따로 읽고 싶을 때 씁니다(복원 검증).</summary>
    public static ArchiveManifest? ReadManifest(string archivePath)
    {
        try
        {
            using ZipArchive archive = ZipFile.OpenRead(archivePath);
            if (archive.GetEntry(ManifestName) is not { } entry)
            {
                return null;
            }
            using Stream stream = entry.Open();
            using StreamReader reader = new(stream, Encoding.UTF8);
            return JsonSerializer.Deserialize<ArchiveManifest>(reader.ReadToEnd(), Json);
        }
        catch (Exception error) when (error is IOException or InvalidDataException
            or JsonException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
