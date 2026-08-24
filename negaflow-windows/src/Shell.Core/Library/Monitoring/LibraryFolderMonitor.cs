namespace Negaflow.Shell;

internal sealed record LibraryFolderChange(
    string FolderPath,
    IReadOnlyList<string> ChangedPaths,
    IReadOnlyList<SourceRelinkMapping> Renames,
    bool RequiresFullReconciliation);

/// <summary>
/// 등록 leaf 폴더의 OS 알림을 폴더별 한 건으로 합칩니다. 알림은 변경의 증거가 아니라
/// reconciliation 힌트이므로 callback은 실제 디렉터리를 다시 열거해야 합니다.
/// </summary>
internal sealed class LibraryFolderMonitor : IDisposable
{
    private const int DebounceMilliseconds = 600;
    private const int MaximumChangedPathsPerFolder = 1_024;
    private const int MaximumAutomaticRetries = 5;

    private sealed class PendingChange
    {
        internal HashSet<string> Paths { get; } = new(StringComparer.OrdinalIgnoreCase);
        internal Dictionary<string, string> Renames { get; } =
            new(StringComparer.OrdinalIgnoreCase);
        internal bool Full { get; set; }
    }

    private readonly object gate = new();
    private readonly Action<IReadOnlyList<LibraryFolderChange>> changed;
    private readonly Dictionary<string, FileSystemWatcher> watchers =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, PendingChange> pending =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, int> retryCounts =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Timer timer;
    private bool disposed;

    internal LibraryFolderMonitor(Action<IReadOnlyList<LibraryFolderChange>> changed)
    {
        ArgumentNullException.ThrowIfNull(changed);
        this.changed = changed;
        timer = new Timer(Flush, null, Timeout.Infinite, Timeout.Infinite);
    }

    internal int WatcherCount
    {
        get
        {
            lock (gate)
            {
                return watchers.Count;
            }
        }
    }

    internal void Update(IEnumerable<string> folderPaths, bool reconcileAll = false)
    {
        ArgumentNullException.ThrowIfNull(folderPaths);
        HashSet<string> requested = new(StringComparer.OrdinalIgnoreCase);
        foreach (string path in folderPaths)
        {
            if (LibraryFolderRecord.TryNormalizePath(path, out string normalized) &&
                Directory.Exists(normalized))
            {
                requested.Add(normalized);
            }
        }

        lock (gate)
        {
            if (disposed)
            {
                return;
            }
            foreach (string removed in watchers.Keys.Where(path => !requested.Contains(path)).ToArray())
            {
                watchers.Remove(removed, out FileSystemWatcher? watcher);
                watcher?.Dispose();
                pending.Remove(removed);
                retryCounts.Remove(removed);
            }
            foreach (string folder in requested)
            {
                if (!watchers.ContainsKey(folder))
                {
                    watchers.Add(folder, CreateWatcher(folder));
                }
                if (reconcileAll)
                {
                    Pending(folder).Full = true;
                }
            }
            if (reconcileAll && requested.Count > 0)
            {
                timer.Change(DebounceMilliseconds, Timeout.Infinite);
            }
        }
    }

    internal void Retry(string folderPath)
    {
        lock (gate)
        {
            if (disposed || !watchers.ContainsKey(folderPath))
            {
                return;
            }
            int attempts = retryCounts.GetValueOrDefault(folderPath);
            if (attempts >= MaximumAutomaticRetries)
            {
                return;
            }
            retryCounts[folderPath] = attempts + 1;
            Pending(folderPath).Full = true;
            timer.Change(DebounceMilliseconds, Timeout.Infinite);
        }
    }

    private FileSystemWatcher CreateWatcher(string folder)
    {
        var watcher = new FileSystemWatcher(folder)
        {
            IncludeSubdirectories = false,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName |
                NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.CreationTime,
            EnableRaisingEvents = false,
        };
        watcher.Created += (_, args) => Record(folder, args.FullPath);
        watcher.Changed += (_, args) => Record(folder, args.FullPath);
        watcher.Deleted += (_, args) => Record(folder, args.FullPath);
        watcher.Renamed += (_, args) => RecordRename(folder, args.OldFullPath, args.FullPath);
        watcher.Error += (_, _) => Record(folder, null, full: true);
        watcher.EnableRaisingEvents = true;
        return watcher;
    }

    private void Record(string folder, string? path, bool full = false)
    {
        lock (gate)
        {
            if (disposed || !watchers.ContainsKey(folder))
            {
                return;
            }
            retryCounts.Remove(folder);
            PendingChange entry = Pending(folder);
            entry.Full |= full;
            if (path is not null && !entry.Full)
            {
                if (entry.Paths.Count < MaximumChangedPathsPerFolder)
                {
                    entry.Paths.Add(path);
                }
                else
                {
                    entry.Paths.Clear();
                    entry.Renames.Clear();
                    entry.Full = true;
                }
            }
            timer.Change(DebounceMilliseconds, Timeout.Infinite);
        }
    }

    private void RecordRename(string folder, string oldPath, string newPath)
    {
        lock (gate)
        {
            if (disposed || !watchers.ContainsKey(folder))
            {
                return;
            }
            retryCounts.Remove(folder);
            PendingChange entry = Pending(folder);
            if (entry.Paths.Count >= MaximumChangedPathsPerFolder)
            {
                entry.Paths.Clear();
                entry.Renames.Clear();
                entry.Full = true;
            }
            else if (!entry.Full)
            {
                entry.Paths.Add(oldPath);
                entry.Paths.Add(newPath);
                entry.Renames[oldPath] = newPath;
            }
            timer.Change(DebounceMilliseconds, Timeout.Infinite);
        }
    }

    private PendingChange Pending(string folder)
    {
        if (!pending.TryGetValue(folder, out PendingChange? entry))
        {
            entry = new PendingChange();
            pending.Add(folder, entry);
        }
        return entry;
    }

    private void Flush(object? state)
    {
        _ = state;
        LibraryFolderChange[] batch;
        lock (gate)
        {
            if (disposed || pending.Count == 0)
            {
                return;
            }
            batch = [.. pending.Select(pair => new LibraryFolderChange(
                pair.Key,
                [.. pair.Value.Paths],
                [.. pair.Value.Renames.Select(rename =>
                    new SourceRelinkMapping(rename.Key, rename.Value))],
                pair.Value.Full))];
            pending.Clear();
        }
        changed(batch);
    }

    public void Dispose()
    {
        FileSystemWatcher[] owned;
        lock (gate)
        {
            if (disposed)
            {
                return;
            }
            disposed = true;
            owned = [.. watchers.Values];
            watchers.Clear();
            pending.Clear();
            retryCounts.Clear();
        }
        timer.Dispose();
        foreach (FileSystemWatcher watcher in owned)
        {
            watcher.Dispose();
        }
    }
}
