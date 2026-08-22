using System.Collections.Concurrent;
using System.Text;
using System.Threading.Channels;
using Negaflow.Catalog;

namespace Negaflow.Shell.Library;

internal sealed class DevelopedPreviewDiskCache : IAsyncDisposable
{
    private const ulong Magic = 0x314157524744464EUL; // "NFDGRAW1" little-endian
    private const uint SchemaVersion = 1U;
    private const int MaximumFrameIdBytes = 4096;
    private const int MaximumRecipeBytes = 16 * 1024 * 1024;
    private const int MaximumDimension = 3600;
    private const long MaximumPayloadBytes = (long)MaximumDimension * MaximumDimension * 4;
    private const long MinimumFreeReserveBytes = 2L * 1024 * 1024 * 1024;
    private const long MaximumCacheBytes = 8L * 1024 * 1024 * 1024;

    private readonly string root;
    private readonly Channel<Action> queue =
        Channel.CreateUnbounded<Action>(new UnboundedChannelOptions { SingleReader = true });
    private readonly ConcurrentDictionary<string, ulong> versions = new(StringComparer.Ordinal);
    private readonly Task worker;
    private ulong clearGeneration;

    internal DevelopedPreviewDiskCache(string root)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(root);
        this.root = root;
        worker = Task.Run(RunAsync);
    }

    internal ThumbnailService.DevelopedPreview? Load(
        LibraryFrameSnapshot frame,
        DevelopedPreviewCacheIdentity expected)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(expected);
        string path = PathFor(frame.Id);
        try
        {
            using FileStream stream = new(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read | FileShare.Delete,
                128 * 1024,
                FileOptions.SequentialScan);
            using BinaryReader reader = new(stream, Encoding.UTF8, leaveOpen: true);
            if (reader.ReadUInt64() != Magic || reader.ReadUInt32() != SchemaVersion ||
                !ReadText(reader, MaximumFrameIdBytes, out string frameId) ||
                !string.Equals(frameId, frame.Id, StringComparison.Ordinal) ||
                !ReadIdentity(reader, out DevelopedPreviewCacheIdentity? stored) ||
                stored is null ||
                !stored.Matches(expected))
            {
                RemoveInvalid(path);
                return null;
            }

            int width = reader.ReadInt32();
            int height = reader.ReadInt32();
            long payloadBytes = reader.ReadInt64();
            long expectedBytes = checked((long)width * height * 4);
            if (width <= 0 || height <= 0 || width > MaximumDimension || height > MaximumDimension ||
                payloadBytes != expectedBytes || payloadBytes > MaximumPayloadBytes ||
                stream.Length - stream.Position != payloadBytes)
            {
                RemoveInvalid(path);
                return null;
            }

            byte[] pixels = reader.ReadBytes(checked((int)payloadBytes));
            if (pixels.LongLength != payloadBytes || stream.Position != stream.Length)
            {
                RemoveInvalid(path);
                return null;
            }
            TryTouch(path);
            return new ThumbnailService.DevelopedPreview(
                pixels,
                width,
                height,
                Settled: true);
        }
        catch (Exception error) when (IsExpectedFailure(error))
        {
            RemoveInvalid(path);
            return null;
        }
    }

    /// <summary>
    /// Background 순회가 기존 disk 결과를 RAM으로 다시 읽지 않고 건너뛸 수 있게 header와
    /// 정확한 파일 길이만 확인합니다. SHA-256 Off 계약상 payload 전체를 hash/read하지 않습니다.
    /// </summary>
    internal bool Contains(
        LibraryFrameSnapshot frame,
        DevelopedPreviewCacheIdentity expected)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(expected);
        string path = PathFor(frame.Id);
        try
        {
            using FileStream stream = new(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read | FileShare.Delete,
                128 * 1024,
                FileOptions.SequentialScan);
            using BinaryReader reader = new(stream, Encoding.UTF8, leaveOpen: true);
            if (reader.ReadUInt64() != Magic || reader.ReadUInt32() != SchemaVersion ||
                !ReadText(reader, MaximumFrameIdBytes, out string frameId) ||
                !string.Equals(frameId, frame.Id, StringComparison.Ordinal) ||
                !ReadIdentity(reader, out DevelopedPreviewCacheIdentity? stored) ||
                stored is null ||
                !stored.Matches(expected))
            {
                RemoveInvalid(path);
                return false;
            }

            int width = reader.ReadInt32();
            int height = reader.ReadInt32();
            long payloadBytes = reader.ReadInt64();
            long expectedBytes = checked((long)width * height * 4);
            if (width <= 0 || height <= 0 || width > MaximumDimension ||
                height > MaximumDimension || payloadBytes != expectedBytes ||
                payloadBytes > MaximumPayloadBytes ||
                stream.Length - stream.Position != payloadBytes)
            {
                RemoveInvalid(path);
                return false;
            }
            TryTouch(path);
            return true;
        }
        catch (Exception error) when (IsExpectedFailure(error))
        {
            RemoveInvalid(path);
            return false;
        }
    }

    internal void Store(
        LibraryFrameSnapshot frame,
        DevelopedPreviewCacheIdentity identity,
        byte[] pixels,
        int width,
        int height)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(identity);
        ArgumentNullException.ThrowIfNull(pixels);
        long required = checked((long)width * height * 4);
        if (width <= 0 || height <= 0 || width > MaximumDimension || height > MaximumDimension ||
            required <= 0 || required > pixels.LongLength || required > MaximumPayloadBytes ||
            identity.RecipeBytes.Length > MaximumRecipeBytes)
        {
            return;
        }

        ulong version = versions.AddOrUpdate(
            frame.Id,
            1UL,
            static (_, current) => current + 1UL);
        ulong generation = Interlocked.Read(ref clearGeneration);
        queue.Writer.TryWrite(() =>
        {
            if (Interlocked.Read(ref clearGeneration) != generation ||
                !versions.TryGetValue(frame.Id, out ulong latest) || latest != version ||
                !DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var current) ||
                !identity.Matches(current))
            {
                return;
            }
            Write(PathFor(frame.Id), frame.Id, identity, pixels, width, height, required);
            Prune();
        });
    }

    internal void Remove(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        versions.AddOrUpdate(frameId, 1UL, static (_, current) => current + 1UL);
        queue.Writer.TryWrite(() => TryDeleteFile(PathFor(frameId)));
    }

    internal Task ClearAsync()
    {
        Interlocked.Increment(ref clearGeneration);
        versions.Clear();
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        queue.Writer.TryWrite(() =>
        {
            TryDeleteDirectory(root);
            completion.TrySetResult();
        });
        return completion.Task;
    }

    internal Task WaitUntilIdleAsync()
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        queue.Writer.TryWrite(() => completion.TrySetResult());
        return completion.Task;
    }

    internal long SizeBytes() => ThumbnailDiskCache.DirectorySize(root);

    public async ValueTask DisposeAsync()
    {
        queue.Writer.TryComplete();
        try
        {
            await worker.ConfigureAwait(false);
        }
        catch (Exception error) when (IsExpectedFailure(error))
        {
        }
    }

    private async Task RunAsync()
    {
        await foreach (Action action in queue.Reader.ReadAllAsync().ConfigureAwait(false))
        {
            try
            {
                action();
            }
            catch (Exception error) when (IsExpectedFailure(error))
            {
            }
        }
    }

    private static void Write(
        string path,
        string frameId,
        DevelopedPreviewCacheIdentity identity,
        byte[] pixels,
        int width,
        int height,
        long payloadBytes)
    {
        string? directory = Path.GetDirectoryName(path);
        if (string.IsNullOrEmpty(directory))
        {
            return;
        }
        string temporary = path + ".tmp";
        try
        {
            Directory.CreateDirectory(directory);
            using (FileStream stream = new(
                temporary,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None,
                128 * 1024,
                FileOptions.SequentialScan))
            using (BinaryWriter writer = new(stream, Encoding.UTF8, leaveOpen: false))
            {
                writer.Write(Magic);
                writer.Write(SchemaVersion);
                WriteText(writer, frameId);
                WriteIdentity(writer, identity);
                writer.Write(width);
                writer.Write(height);
                writer.Write(payloadBytes);
                writer.Write(pixels, 0, checked((int)payloadBytes));
                writer.Flush();
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, path, overwrite: true);
        }
        catch (Exception error) when (IsExpectedFailure(error))
        {
            TryDeleteFile(temporary);
        }
    }

    private static void WriteIdentity(BinaryWriter writer, DevelopedPreviewCacheIdentity identity)
    {
        writer.Write(identity.ShellModuleVersion.ToByteArray());
        WriteObservation(writer, identity.Source);
        WriteObservation(writer, identity.NativeEngine);
        writer.Write(identity.RecipeBytes.Length);
        writer.Write(identity.RecipeBytes);
    }

    private static bool ReadIdentity(
        BinaryReader reader,
        out DevelopedPreviewCacheIdentity? identity)
    {
        identity = null;
        byte[] module = reader.ReadBytes(16);
        if (module.Length != 16)
        {
            return false;
        }
        DevelopedFileObservation source = ReadObservation(reader);
        DevelopedFileObservation native = ReadObservation(reader);
        int recipeBytes = reader.ReadInt32();
        if (recipeBytes < 0 || recipeBytes > MaximumRecipeBytes)
        {
            return false;
        }
        byte[] recipe = reader.ReadBytes(recipeBytes);
        if (recipe.Length != recipeBytes)
        {
            return false;
        }
        identity = new DevelopedPreviewCacheIdentity(recipe, source, native, new Guid(module));
        return true;
    }

    private static void WriteObservation(BinaryWriter writer, DevelopedFileObservation value)
    {
        writer.Write(value.VolumeSerialNumber);
        writer.Write(value.FileIndex);
        writer.Write(value.FileBytes);
        writer.Write(value.LastWriteTicks);
    }

    private static DevelopedFileObservation ReadObservation(BinaryReader reader) => new(
        reader.ReadUInt32(),
        reader.ReadUInt64(),
        reader.ReadUInt64(),
        reader.ReadUInt64());

    private static void WriteText(BinaryWriter writer, string value)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(value);
        writer.Write(bytes.Length);
        writer.Write(bytes);
    }

    private static bool ReadText(BinaryReader reader, int maximumBytes, out string value)
    {
        value = string.Empty;
        int length = reader.ReadInt32();
        if (length < 0 || length > maximumBytes)
        {
            return false;
        }
        byte[] bytes = reader.ReadBytes(length);
        if (bytes.Length != length)
        {
            return false;
        }
        value = Encoding.UTF8.GetString(bytes);
        return true;
    }

    private string PathFor(string frameId)
    {
        ulong hash = 14695981039346656037UL;
        foreach (byte value in Encoding.UTF8.GetBytes(frameId))
        {
            hash ^= value;
            hash *= 1099511628211UL;
        }
        return Path.Combine(root, hash.ToString("x16") + ".nfdp");
    }

    private void Prune()
    {
        long limit = BudgetBytes();
        if (!Directory.Exists(root))
        {
            return;
        }
        FileInfo[] files;
        try
        {
            files = new DirectoryInfo(root)
                .EnumerateFiles("*.nfdp", SearchOption.TopDirectoryOnly)
                .OrderBy(file => file.LastWriteTimeUtc)
                .ToArray();
        }
        catch (Exception error) when (IsExpectedFailure(error))
        {
            return;
        }
        long total = files.Sum(file => file.Length);
        foreach (FileInfo file in files)
        {
            if (total <= limit)
            {
                break;
            }
            long bytes = file.Length;
            TryDeleteFile(file.FullName);
            total -= bytes;
        }
    }

    private long BudgetBytes()
    {
        try
        {
            string full = Path.GetFullPath(root);
            string? volume = Path.GetPathRoot(full);
            if (string.IsNullOrEmpty(volume))
            {
                return 0L;
            }
            DriveInfo drive = new(volume);
            long reserve = Math.Max(MinimumFreeReserveBytes, drive.TotalSize / 50L);
            long usable = Math.Max(0L, drive.AvailableFreeSpace - reserve);
            return Math.Min(MaximumCacheBytes, usable / 10L);
        }
        catch (Exception error) when (IsExpectedFailure(error))
        {
            return 0L;
        }
    }

    private static void RemoveInvalid(string path) => TryDeleteFile(path);

    private static void TryTouch(string path)
    {
        try
        {
            File.SetLastWriteTimeUtc(path, DateTime.UtcNow);
        }
        catch (Exception error) when (IsExpectedFailure(error))
        {
        }
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception error) when (IsExpectedFailure(error))
        {
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch (Exception error) when (IsExpectedFailure(error))
        {
        }
    }

    private static bool IsExpectedFailure(Exception error) =>
        error is IOException or UnauthorizedAccessException or NotSupportedException or
            ArgumentException or PathTooLongException or EndOfStreamException or
            OverflowException;
}
