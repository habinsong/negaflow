using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>읽지 못한 frame 하나입니다. 목록에서 조용히 사라지지 않도록 남깁니다.</summary>
public sealed record LibraryFrameIssue(
    int Position,
    string? Id,
    LibraryFrameError Error,
    DevelopRouteError RouteError);

public enum LibraryDocumentError
{
    None,
    SessionBusy,
    SessionUnavailable,
    CatalogUnreadable,
}

public readonly record struct LibraryDocumentOpenResult(
    LibraryDocument? Document,
    LibraryDocumentError Error,
    CatalogSessionError SessionError,
    CatalogStoreError StoreError)
{
    public bool IsSuccess => Error == LibraryDocumentError.None && Document is not null;

    internal static LibraryDocumentOpenResult Success(LibraryDocument document) =>
        new(document, LibraryDocumentError.None, CatalogSessionError.None,
            CatalogStoreError.None);

    internal static LibraryDocumentOpenResult SessionFailure(CatalogSessionError error) =>
        new(
            null,
            error == CatalogSessionError.Busy
                ? LibraryDocumentError.SessionBusy
                : LibraryDocumentError.SessionUnavailable,
            error,
            CatalogStoreError.None);

    internal static LibraryDocumentOpenResult StoreFailure(CatalogStoreError error) =>
        new(null, LibraryDocumentError.CatalogUnreadable, CatalogSessionError.None, error);
}

/// <summary>
/// 열려 있는 라이브러리 하나입니다. catalog 세션을 소유하므로 <see cref="Dispose"/> 할 때까지
/// 다른 프로세스는 이 카탈로그의 작성자가 될 수 없습니다.
/// </summary>
/// <remarks>
/// 원본 payload 를 그대로 들고 있다가 저장할 때 그 위에 편집을 얹습니다. 투영된 값만 들고 있으면
/// 이 빌드가 모르는 field 가 저장할 때마다 사라집니다.
/// </remarks>
public sealed class LibraryDocument : IDisposable
{
    private readonly CatalogSession session;
    private readonly List<JsonObject> payloads;
    private readonly List<string> rowIds;
    private readonly List<LibraryFrameSnapshot> frames = [];
    private readonly List<LibraryFrameIssue> issues = [];
    private readonly Dictionary<string, int> indexById = new(StringComparer.Ordinal);
    private string? activeRollId;

    private LibraryDocument(
        CatalogSession session,
        List<string> rowIds,
        List<JsonObject> payloads,
        string? activeRollId)
    {
        this.session = session;
        this.rowIds = rowIds;
        this.payloads = payloads;
        this.activeRollId = activeRollId;
        Project();
    }

    public IReadOnlyList<LibraryFrameSnapshot> Frames => frames;

    /// <summary>
    /// 투영에 실패한 frame 들입니다. **비어 있지 않은데 무시하면 사용자에게는 사진이 사라진
    /// 것으로 보입니다.** 목록에서 빼는 것과 없어진 것은 다릅니다.
    /// </summary>
    public IReadOnlyList<LibraryFrameIssue> Issues => issues;

    public int RecordCount => payloads.Count;

    public static LibraryDocumentOpenResult Open(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);

        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        if (opened.Session is not { } session)
        {
            return LibraryDocumentOpenResult.SessionFailure(opened.Error);
        }

        CatalogReadResult read = session.ReadOrCreate();
        if (read.Snapshot is not { } snapshot)
        {
            session.Dispose();
            return LibraryDocumentOpenResult.StoreFailure(read.Error);
        }

        IReadOnlyList<CatalogEntityRow> rows = snapshot.Rows(CatalogEntityTable.Frames);
        List<string> rowIds = new(rows.Count);
        List<JsonObject> payloads = new(rows.Count);
        foreach (CatalogEntityRow row in rows)
        {
            rowIds.Add(row.Id);
            payloads.Add(row.Payload);
        }

        return LibraryDocumentOpenResult.Success(
            new LibraryDocument(session, rowIds, payloads, snapshot.ActiveRollId));
    }

    /// <summary>
    /// 톤과 수동 base 를 갱신합니다. 메모리 안에서만 바뀌며, 디스크로 가려면
    /// <see cref="Save"/> 를 불러야 합니다.
    /// </summary>
    public LibraryFrameError Edit(string frameId, LibraryFrameEdit edit)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(edit);

        if (!indexById.TryGetValue(frameId, out int index))
        {
            return LibraryFrameError.MissingId;
        }

        LibraryFrameWriteResult written = LibraryFrameWriter.Apply(payloads[index], edit);
        if (written.FrameRecord is not { } updated)
        {
            return written.Error;
        }

        payloads[index] = updated;
        Project();
        return LibraryFrameError.None;
    }

    /// <summary>
    /// 계획된 frame 을 뒤에 덧붙입니다. 메모리 안에서만 바뀌며 <see cref="Save"/> 로 디스크에
    /// 갑니다.
    /// </summary>
    public int Append(IReadOnlyList<CatalogEntityRow> rows)
    {
        ArgumentNullException.ThrowIfNull(rows);
        int added = 0;
        foreach (CatalogEntityRow row in rows)
        {
            if (rowIds.Contains(row.Id))
            {
                continue;
            }
            rowIds.Add(row.Id);
            payloads.Add(row.Payload);
            ++added;
        }
        if (added > 0)
        {
            Project();
        }
        return added;
    }

    public CatalogStoreError Save()
    {
        List<CatalogEntityRow> rows = new(payloads.Count);
        for (int index = 0; index < payloads.Count; index++)
        {
            rows.Add(new CatalogEntityRow(rowIds[index], payloads[index]));
        }

        CatalogSnapshot snapshot = new(
            activeRollId,
            new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
            {
                [CatalogEntityTable.Frames] = rows,
            });
        return session.Write(snapshot).Error;
    }

    public void Dispose() => session.Dispose();

    private void Project()
    {
        frames.Clear();
        issues.Clear();
        indexById.Clear();

        for (int index = 0; index < payloads.Count; index++)
        {
            using JsonDocument document = JsonDocument.Parse(
                CatalogJson.SerializeCanonical(payloads[index]));
            LibraryFrameReadResult read = LibraryFrameReader.Read(document.RootElement);
            if (read.Frame is { } frame)
            {
                frames.Add(frame);
                indexById[frame.Id] = index;
                continue;
            }
            issues.Add(new LibraryFrameIssue(
                index,
                rowIds[index],
                read.Error,
                read.RouteError));
        }
    }
}
