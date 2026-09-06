using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

// UI 스레드에서 사용합니다. 원본 검사 수명은 감마 편집이나 가상 복사본 선택과 독립적입니다.
public sealed class InputGammaSourceInspection
{
    public readonly record struct Request(long Revision, string Path);
    private long revision;
    private string? path;
    private LibrarySourceMetadata? metadata;
    public InputGammaSource.Info Info { get; private set; }

    public Request? Begin(string source, LibrarySourceMetadata? sourceMetadata)
    {
        if (path == source && metadata == sourceMetadata) { return null; }
        path = source;
        metadata = sourceMetadata;
        Info = default;
        return new(++revision, source);
    }

    public bool Complete(Request request, InputGammaSource.Info info)
    {
        if (request.Revision != revision || request.Path != path) { return false; }
        Info = info;
        return true;
    }

    public void Invalidate()
    {
        revision++;
        path = null;
        metadata = null;
        Info = default;
    }
}
