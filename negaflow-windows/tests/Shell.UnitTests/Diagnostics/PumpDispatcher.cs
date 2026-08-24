using System.Collections.Concurrent;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// WinUI <c>DispatcherQueue</c>와 같은 단일 전용 스레드 큐를 진단에서 재현합니다.
/// </summary>
internal sealed class PumpDispatcher : IUiDispatcher, IDisposable
{
    private readonly BlockingCollection<Action> queue = [];
    private readonly Thread thread;
    private int pumpThreadId;

    public PumpDispatcher()
    {
        using ManualResetEventSlim ready = new();
        thread = new Thread(() =>
        {
            pumpThreadId = Environment.CurrentManagedThreadId;
            ready.Set();
            foreach (Action work in queue.GetConsumingEnumerable())
            {
                try
                {
                    work();
                }
                catch (Exception error)
                {
                    Console.Error.WriteLine("pump: " + error);
                }
            }
        })
        {
            IsBackground = true,
            Name = "negaflow-ui-pump",
        };
        thread.Start();
        ready.Wait();
    }

    public bool HasThreadAccess => Environment.CurrentManagedThreadId == pumpThreadId;

    public bool TryEnqueue(Action callback)
    {
        try
        {
            queue.Add(callback);
            return true;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    public void Send(Action callback)
    {
        using ManualResetEventSlim done = new();
        if (!TryEnqueue(() =>
            {
                try
                {
                    callback();
                }
                finally
                {
                    done.Set();
                }
            }))
        {
            return;
        }
        done.Wait();
    }

    public void Dispose()
    {
        queue.CompleteAdding();
        thread.Join(TimeSpan.FromSeconds(5));
        queue.Dispose();
    }
}
