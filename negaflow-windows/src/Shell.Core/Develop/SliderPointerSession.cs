namespace Negaflow.Shell.Develop;

/// <summary>감마·베이스 배율의 포인터 조작 소유권과 취소 수명만 관리합니다.</summary>
public sealed class SliderPointerSession
{
    private string? owner;
    private string? source;
    public long Revision { get; private set; }
    public bool IsActive { get; private set; }
    public bool IsCancelled { get; private set; }
    public bool HasDraft => IsActive && !IsCancelled;

    public void Begin(string? owner, string? source)
    {
        Revision++;
        this.owner = owner; this.source = source;
        IsActive = true; IsCancelled = false;
    }

    public void Validate(string? owner, string? source, bool canEdit)
    {
        if (IsActive && (this.owner != owner || this.source != source || !canEdit))
        { Cancel(); }
    }

    public void Cancel() { IsCancelled = true; }

    public bool End(string? owner, string? source, bool canEdit)
    {
        Validate(owner, source, canEdit);
        bool commit = HasDraft;
        IsActive = false;
        IsCancelled = true;
        return commit;
    }

    // PointerReleased/CaptureLost 뒤 같은 입력 묶음의 ValueChanged까지 흘려보냅니다.
    public void AllowUntrackedChanges(long revision)
    {
        if (Revision == revision && !IsActive) { IsCancelled = false; }
    }
}
