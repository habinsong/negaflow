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
        // **같은 파일을 다시 확인하는 동안에는 직전 판정을 들고 있습니다.** 여기서 비우면
        // 검사가 끝날 때까지 `supported` 가 거짓이 되어 수동 캡슐이 죽고, 끌고 있던 슬라이더의
        // 포인터 세션까지 `Validate(..., canEdit: false)` 로 취소돼 손잡이가 되돌아갑니다 —
        // 70MB TIFF 실측으로 그 창이 약 10초였습니다. 파일 자체가 바뀌었을 때만 비웁니다.
        if (path != source) { Info = default; }
        path = source;
        metadata = sourceMetadata;
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
