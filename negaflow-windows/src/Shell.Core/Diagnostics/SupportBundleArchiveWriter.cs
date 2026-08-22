using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Negaflow.Shell.Diagnostics;

public enum SupportBundleArchiveError
{
    None,
    EncodingFailed,
    ArchiveFailed,
    PublicationFailed,
}

/// <summary>
/// macOS <c>SupportBundleArchiveWriter</c> 이식본입니다. macOS 는 <c>/usr/bin/ditto</c> 로
/// 압축하고 Windows 는 <see cref="ZipFile"/> 을 씁니다 — 두 판 모두 결과는 zip 하나입니다.
/// </summary>
public static class SupportBundleArchiveWriter
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        // macOS 는 `.sortedKeys` 를 씁니다. System.Text.Json 은 속성 차례를 그대로 내므로
        // 레코드 선언 차례가 곧 출력 차례입니다 — 선언을 macOS 와 같게 두는 이유입니다.
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static string Readme =>
        """
        negaflow Support Bundle

        Paths, file names, source identifiers, and personal image metadata are omitted.
        Location and plugin identifiers are represented only by per-bundle salted hashes.
        """;

    public static byte[] EncodeDocument(SupportBundleDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);
        return JsonSerializer.SerializeToUtf8Bytes(document, Options);
    }

    /// <summary>
    /// 번들을 <paramref name="destinationPath"/> 에 씁니다. 임시 폴더에서 만들고 마지막에
    /// 옮깁니다 — 도중에 실패해도 목적지에 반쪽짜리 zip 이 남지 않습니다.
    /// </summary>
    public static SupportBundleArchiveError Write(
        SupportBundleDocument document,
        string destinationPath)
    {
        ArgumentNullException.ThrowIfNull(document);
        ArgumentException.ThrowIfNullOrWhiteSpace(destinationPath);

        byte[] json;
        try
        {
            json = EncodeDocument(document);
        }
        catch (Exception error) when (error is JsonException or NotSupportedException)
        {
            return SupportBundleArchiveError.EncodingFailed;
        }

        string root = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-support-build-{Guid.NewGuid():N}");
        string package = Path.Combine(root, "negaflow-support");
        string staged = Path.Combine(root, "support.zip");
        try
        {
            Directory.CreateDirectory(package);
            File.WriteAllBytes(Path.Combine(package, "support.json"), json);
            File.WriteAllText(Path.Combine(package, "README.txt"), Readme, Encoding.UTF8);
            ZipFile.CreateFromDirectory(
                package, staged, CompressionLevel.Optimal, includeBaseDirectory: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            TryRemove(root);
            return SupportBundleArchiveError.ArchiveFailed;
        }

        try
        {
            if (Path.GetDirectoryName(destinationPath) is { Length: > 0 } parent)
            {
                Directory.CreateDirectory(parent);
            }
            File.Move(staged, destinationPath, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            TryRemove(root);
            return SupportBundleArchiveError.PublicationFailed;
        }

        TryRemove(root);
        return SupportBundleArchiveError.None;
    }

    private static void TryRemove(string directory)
    {
        try
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 임시 폴더입니다. 못 지워도 번들은 이미 목적지에 있습니다.
        }
    }
}
