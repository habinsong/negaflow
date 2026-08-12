using System.Collections.Concurrent;
using System.Threading.Channels;

namespace Negaflow.Shell.Library;

/// <summary>
/// 라이브러리·필름스트립 썸네일의 디스크 백킹입니다. 메모리 캐시는 그대로 두고, 정착 시점
/// (가져오기 직후 원본 프리뷰·현상 정착)마다 JPEG 로 덮어씁니다.
/// </summary>
/// <remarks>
/// <para>
/// 프레임마다 <b>마지막 요청만 남깁니다.</b> 슬라이더를 끄는 동안 같은 프레임의 썸네일이 수십 번
/// 정착하는데, 전부 쓰면 디스크가 밀리고 결과는 어차피 마지막 것 하나입니다. 버전 번호를 붙여
/// 두고 큐에서 꺼낼 때 자기가 최신인지 확인합니다.
/// </para>
/// <para>
/// 쓰기는 단일 워커에서만 일어나므로 UI 스레드에 IO 가 없고, 같은 파일에 두 쓰기가 겹치지도
/// 않습니다. 캐시이므로 전부 지워도 원본에서 다시 만들어집니다.
/// </para>
/// </remarks>
public sealed class ThumbnailDiskCache : IAsyncDisposable
{
    private readonly Channel<Func<Task>> queue =
        Channel.CreateUnbounded<Func<Task>>(new UnboundedChannelOptions
        {
            SingleReader = true,
        });

    private readonly ConcurrentDictionary<string, ulong> versions = new(StringComparer.Ordinal);
    private readonly Task worker;
    private ulong clearGeneration;

    public ThumbnailDiskCache()
    {
        worker = Task.Run(RunAsync);
    }

    /// <summary>썸네일을 디스크에 저장합니다. 같은 프레임의 진행 전 요청은 최신 것으로 대체됩니다.</summary>
    public void Store(string frameId, string path, byte[] jpeg)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        ArgumentException.ThrowIfNullOrEmpty(path);
        ArgumentNullException.ThrowIfNull(jpeg);

        ulong version = versions.AddOrUpdate(frameId, 1UL, static (_, current) => current + 1UL);
        ulong generation = Interlocked.Read(ref clearGeneration);
        Enqueue(() =>
        {
            if (Interlocked.Read(ref clearGeneration) != generation ||
                !versions.TryGetValue(frameId, out ulong latest) || latest != version)
            {
                return Task.CompletedTask;
            }
            Write(path, jpeg);
            return Task.CompletedTask;
        });
    }

    /// <summary>같은 프레임의 대기 중 쓰기를 무효화한 뒤 파일을 지웁니다.</summary>
    public void Remove(string frameId, string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        ArgumentException.ThrowIfNullOrEmpty(path);

        versions.AddOrUpdate(frameId, 1UL, static (_, current) => current + 1UL);
        Enqueue(() =>
        {
            TryDeleteFile(path);
            return Task.CompletedTask;
        });
    }

    /// <summary>대기 중인 모든 쓰기를 버리고 캐시 루트를 지웁니다.</summary>
    public Task ClearAsync(string root)
    {
        ArgumentException.ThrowIfNullOrEmpty(root);

        Interlocked.Increment(ref clearGeneration);
        versions.Clear();
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Enqueue(() =>
        {
            try
            {
                if (Directory.Exists(root))
                {
                    Directory.Delete(root, recursive: true);
                }
            }
            catch (Exception error) when (IsExpectedIoFailure(error))
            {
                // 캐시입니다. 지우지 못해도 다음 정착이 덮어씁니다.
            }
            completion.TrySetResult();
            return Task.CompletedTask;
        });
        return completion.Task;
    }

    /// <summary>큐에 남은 IO 가 끝날 때까지 기다립니다. 시험과 종료 동기화용입니다.</summary>
    public Task WaitUntilIdleAsync()
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Enqueue(() =>
        {
            completion.TrySetResult();
            return Task.CompletedTask;
        });
        return completion.Task;
    }

    public static byte[]? Load(string path)
    {
        try
        {
            return File.Exists(path) ? File.ReadAllBytes(path) : null;
        }
        catch (Exception error) when (IsExpectedIoFailure(error))
        {
            return null;
        }
    }

    /// <summary>캐시 폴더가 지금 차지하는 바이트입니다. 설정의 디스크 탭이 읽습니다.</summary>
    public static long DirectorySize(string root)
    {
        if (!Directory.Exists(root))
        {
            return 0L;
        }
        long total = 0L;
        try
        {
            foreach (string file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
            {
                try
                {
                    total += new FileInfo(file).Length;
                }
                catch (Exception error) when (IsExpectedIoFailure(error))
                {
                    // 세는 도중 사라진 파일은 0 으로 둡니다.
                }
            }
        }
        catch (Exception error) when (IsExpectedIoFailure(error))
        {
            return total;
        }
        return total;
    }

    public async ValueTask DisposeAsync()
    {
        queue.Writer.TryComplete();
        try
        {
            await worker.ConfigureAwait(false);
        }
        catch (Exception error) when (IsExpectedIoFailure(error))
        {
            // 종료 중 IO 실패는 캐시 손실일 뿐입니다.
        }
    }

    private void Enqueue(Func<Task> work) => _ = queue.Writer.TryWrite(work);

    private async Task RunAsync()
    {
        await foreach (Func<Task> work in queue.Reader.ReadAllAsync().ConfigureAwait(false))
        {
            try
            {
                await work().ConfigureAwait(false);
            }
            catch (Exception error) when (IsExpectedIoFailure(error))
            {
                // 하나가 실패해도 큐는 계속 돕니다.
            }
        }
    }

    /// <summary>임시 파일에 쓰고 옮깁니다. 중간에 죽어도 반쯤 쓰인 JPEG 가 남지 않습니다.</summary>
    private static void Write(string path, byte[] jpeg)
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
            File.WriteAllBytes(temporary, jpeg);
            File.Move(temporary, path, overwrite: true);
        }
        catch (Exception error) when (IsExpectedIoFailure(error))
        {
            TryDeleteFile(temporary);
        }
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception error) when (IsExpectedIoFailure(error))
        {
            // 이미 없거나 잠겨 있습니다. 캐시이므로 그냥 둡니다.
        }
    }

    private static bool IsExpectedIoFailure(Exception error) =>
        error is IOException or UnauthorizedAccessException or NotSupportedException or
            ArgumentException or PathTooLongException;
}
