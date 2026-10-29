using System.Diagnostics.CodeAnalysis;

namespace Negaflow.Shell.Library;

/// <summary>JPEG 바이트 예산과 최근 사용 순서를 관리합니다. UI 배달 중인 항목만 잠깐 보호합니다.</summary>
internal sealed class ThumbnailMemoryCache
{
    private sealed record Entry(string Id, ThumbnailCacheEntry Value);
    private readonly Lock gate = new();
    private readonly Dictionary<string, LinkedListNode<Entry>> entries = new(StringComparer.Ordinal);
    private readonly LinkedList<Entry> order = new();
    private readonly Dictionary<string, int> delivering = new(StringComparer.Ordinal);
    private long bytes;
    private long limit;

    internal int Count { get { lock (gate) { return entries.Count; } } }
    internal long ResidentBytes { get { lock (gate) { return bytes; } } }

    internal void SetLimit(long value)
    {
        lock (gate) { limit = Math.Max(0L, value); Trim(); }
    }

    internal bool TryGetValue(string id, [NotNullWhen(true)] out ThumbnailCacheEntry? value)
    {
        lock (gate)
        {
            if (!entries.TryGetValue(id, out var node)) { value = null; return false; }
            order.Remove(node); order.AddLast(node);
            value = node.Value.Value;
            return true;
        }
    }

    internal void Store(string id, ThumbnailCacheEntry value)
    {
        lock (gate) { StoreLocked(id, value); Trim(); }
    }

    internal bool TryRemove(string id, out ThumbnailCacheEntry? value)
    {
        lock (gate)
        {
            if (!entries.Remove(id, out var node)) { value = null; return false; }
            order.Remove(node); value = node.Value.Value; bytes -= value.Jpeg.LongLength;
            return true;
        }
    }

    // 시작은 요청 세대 검증 안에서, 외부 콜백과 종료는 그 잠금 밖에서 실행합니다.
    internal void BeginDelivery(string id, ThumbnailCacheEntry value)
    {
        lock (gate)
        {
            StoreLocked(id, value);
            try { delivering[id] = delivering.GetValueOrDefault(id) + 1; }
            finally { Trim(); }
        }
    }

    internal void EndDelivery(string id)
    {
        lock (gate)
        {
            if (--delivering[id] == 0) { delivering.Remove(id); }
            Trim();
        }
    }

    internal void Clear()
    {
        lock (gate) { entries.Clear(); order.Clear(); bytes = 0; }
    }

    private void StoreLocked(string id, ThumbnailCacheEntry value)
    {
        var entry = new Entry(id, value);
        if (entries.TryGetValue(id, out var existing))
        {
            bytes -= existing.Value.Value.Jpeg.LongLength;
            existing.Value = entry;
            order.Remove(existing); order.AddLast(existing);
        }
        else
        {
            var node = new LinkedListNode<Entry>(entry);
            entries.Add(id, node);
            order.AddLast(node);
        }
        bytes += value.Jpeg.LongLength;
    }

    private void Trim()
    {
        var node = order.First;
        while (bytes > limit && node is not null)
        {
            var next = node.Next;
            if (!delivering.ContainsKey(node.Value.Id)) { TryRemove(node.Value.Id, out _); }
            node = next;
        }
    }
}
