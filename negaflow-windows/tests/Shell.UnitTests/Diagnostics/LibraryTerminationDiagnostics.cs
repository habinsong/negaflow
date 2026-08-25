using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 앱을 닫을 때 도는 경로를 <b>실제 카탈로그 사본</b>으로 그대로 돌립니다. 사용자가 종료할 때
/// "카탈로그를 저장하지 못했습니다"(<c>developExportSaveFailed</c>)를 봤는데, 그 대화상자는
/// <see cref="LibraryDefectTerminationError"/> 만 말해 주고 어느 사진에서 왜 멈췄는지는
/// 말해 주지 않습니다. 여기서 같은 입력으로 재현해 프레임과 오류를 밝힙니다.
/// </summary>
/// <remarks>
/// <b>원본은 절대 건드리지 않습니다.</b> 카탈로그만 복사하는 것으로는 부족합니다 - 스캐너
/// TIFF 의 종료 굽기는 `inPlace` 로 <b>원본 파일 자리에 덮어씁니다</b>. 카탈로그 안의
/// `rawScanPath` 는 절대 경로라 사본 밖을 가리키고, 그러면 이 진단이 사용자의 실제 스캔을
/// 고쳐 씁니다. 실제로 그렇게 만들었습니다 - `OpticFilm8100-0002.tif` 가
/// 109,181,328 에서 109,216,380 바이트로 바뀌었습니다.
///
/// 그래서 원본 파일도 사본으로 옮기고 카탈로그의 경로를 사본으로 고쳐 씁니다. 옮길 수 없는
/// 프레임은 recipe 를 지워 굽기 대상에서 빼고, 그 사실을 결과에 적습니다.
/// </remarks>
internal static class LibraryTerminationDiagnostics
{
    internal static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length is not (2 or 3) || args[0] != "--library-termination-check")
        {
            return false;
        }
        exitCode = Run(args[1], args.Length == 3 ? args[2] : null);
        return true;
    }

    /// <param name="previewScanPath">
    /// 주면 종료 전에 그 파일을 <b>임시 프리뷰 프레임</b>으로 올립니다. 사용자는 평판 프리뷰를
    /// 한 뒤 앱을 닫았고, 그때만 카탈로그 저장이 실패했습니다.
    /// </param>
    private static int Run(string sourceApplicationDataRoot, string? previewScanPath)
    {
        string source = Path.GetFullPath(sourceApplicationDataRoot);
        if (!Directory.Exists(source))
        {
            Console.Error.WriteLine("application data root not found: " + source);
            return 2;
        }

        string copyBase = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-termination-{Guid.NewGuid():N}");
        try
        {
            CopyTree(source, Path.Combine(copyBase, Path.GetFileName(source)));
            if (StorageRootResolver.ResolveForTests(copyBase).Roots is not { } roots)
            {
                Console.Error.WriteLine("storage root refused");
                return 2;
            }

            // 굽기가 손댈 수 있는 자리를 먼저 확인합니다. 사본 밖을 가리키는 프레임이 하나라도
            // 있으면 굽지 않습니다 - 사용자의 실제 파일을 고쳐 쓰는 것보다 재현을 포기하는
            // 것이 낫습니다.
            string copyRoot = Path.GetFullPath(copyBase);
            using PumpDispatcher dispatcher = new();
            using LibraryHostService host = new(
                dispatcher,
                new NativeDevelopExporterAdapter(),
                sourceMetadataReader: null,
                token => Task.Delay(Timeout.Infinite, token));
            LibraryHostState state = host.Open(roots);
            if (state != LibraryHostState.Open)
            {
                Console.WriteLine(JsonSerializer.Serialize(
                    new { status = "failed", operation = "library_termination_check", open = state.ToString() },
                    Options));
                return 1;
            }

            var recipes = host.Frames
                .Where(frame => frame.DefectRecipe is not null)
                .Select(frame => new
                {
                    frame.Id,
                    frame.SourcePath,
                    sourceExists = File.Exists(frame.SourcePath),
                    actualBytes = File.Exists(frame.SourcePath)
                        ? new FileInfo(frame.SourcePath).Length
                        : -1L,
                    expectedBytes = (long)(frame.DefectRecipe!.SourceIdentity?.ByteCount ?? 0UL),
                    frame.SourceKind,
                    sharesSource = host.Frames.Any(other =>
                        !string.Equals(other.Id, frame.Id, StringComparison.Ordinal) &&
                        string.Equals(
                            Path.GetFullPath(other.SourcePath),
                            Path.GetFullPath(frame.SourcePath),
                            StringComparison.OrdinalIgnoreCase)),
                    frame.IsPreviewScan,
                    items = frame.DefectRecipe!.Items.Count,
                    bakeable = frame.DefectRecipe!.Items.Count(item =>
                        item.Kind != DefectEditKind.Infrared &&
                        item.Enabled &&
                        item.Strength > 1.0e-3),
                    infrared = frame.DefectRecipe!.Items.Count(item =>
                        item.Kind == DefectEditKind.Infrared),
                })
                .ToArray();

            string previewPublish = "skipped";
            if (previewScanPath is { Length: > 0 })
            {
                string preview = Path.GetFullPath(previewScanPath);
                ScannerFramePublishResult published = host.PublishScannerPreviewFrame(
                    new ScannerFrameImport(preview, null, DevelopmentProcess.C41)
                    {
                        IsPreviewScan = true,
                    });
                previewPublish = published.Status.ToString();
            }

            string[] outside = [.. host.Frames
                .Where(frame => frame.DefectRecipe is not null && !frame.IsPreviewScan)
                .Where(frame => !IsInside(copyRoot, frame.SourcePath))
                .Select(frame => frame.SourcePath)];
            if (outside.Length != 0)
            {
                Console.WriteLine(JsonSerializer.Serialize(
                    new
                    {
                        status = "refused",
                        operation = "library_termination_check",
                        reason = "recipe sources live outside the copy; baking would rewrite them",
                        outside,
                        recipes,
                    },
                    Options));
                return 2;
            }

            LibraryDefectTerminationResult closing = host
                .PrepareForTerminationAsync(Path.Combine(copyBase, "Scans"))
                .GetAwaiter()
                .GetResult();

            bool passed = closing.Error == LibraryDefectTerminationError.None;
            Console.WriteLine(JsonSerializer.Serialize(
                new
                {
                    status = passed ? "ok" : "failed",
                    operation = "library_termination_check",
                    frames = host.Frames.Count,
                    framesWithRecipe = recipes.Length,
                    previewPublish,
                    terminationError = closing.Error.ToString(),
                    terminationFrame = closing.FrameId ?? string.Empty,
                    nativeFailure = closing.NativeFailureName ?? string.Empty,
                    recipes,
                },
                Options));
            return passed ? 0 : 1;
        }
        finally
        {
            TryDeleteTree(copyBase);
        }
    }

    /// <summary>사본 안에 있는 자리인지입니다. 밖이면 굽기가 사용자의 실제 파일을 고칩니다.</summary>
    private static bool IsInside(string root, string path)
    {
        try
        {
            string full = Path.GetFullPath(path);
            string prefix = root.EndsWith(Path.DirectorySeparatorChar)
                ? root
                : root + Path.DirectorySeparatorChar;
            return full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception error) when (error is ArgumentException or PathTooLongException or
            NotSupportedException)
        {
            return false;
        }
    }

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    private static void CopyTree(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (string directory in Directory.EnumerateDirectories(source, "*", SearchOption.AllDirectories))
        {
            // 캐시는 종료 경로가 보지 않습니다. 수 GB 를 복사하지 않습니다.
            if (IsSkipped(directory, source))
            {
                continue;
            }
            Directory.CreateDirectory(
                Path.Combine(destination, Path.GetRelativePath(source, directory)));
        }
        foreach (string file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
        {
            if (IsSkipped(file, source))
            {
                continue;
            }
            string target = Path.Combine(destination, Path.GetRelativePath(source, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            try
            {
                File.Copy(file, target, overwrite: true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
            }
        }
    }

    private static bool IsSkipped(string path, string source)
    {
        string relative = Path.GetRelativePath(source, path);
        return relative.StartsWith("Cache", StringComparison.OrdinalIgnoreCase) ||
            relative.StartsWith("Logs", StringComparison.OrdinalIgnoreCase) ||
            relative.StartsWith("Journals", StringComparison.OrdinalIgnoreCase);
    }

    private static void TryDeleteTree(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }
}
