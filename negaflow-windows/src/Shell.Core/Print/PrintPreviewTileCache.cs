namespace Negaflow.Shell.Print;

/// <summary>UI 스레드의 인화 타일 캐시입니다. 비동기 디코드는 시작할 때의 세대에만 저장합니다.</summary>
public sealed class PrintPreviewTileCache<TImage> where TImage : class
{
    private readonly Dictionary<(string FrameId, PrintPresentationStyle Style, bool Developed, string Proof), TImage> images = [];
    public long Revision { get; private set; }
    public int Count => images.Count;
    public bool TryGetValue((string FrameId, PrintPresentationStyle Style, bool Developed, string Proof) key, out TImage? image) =>
        images.TryGetValue(key, out image);
    public void Store((string FrameId, PrintPresentationStyle Style, bool Developed, string Proof) key, TImage image) => images[key] = image;
    public bool TryStore(long revision, (string FrameId, PrintPresentationStyle Style, bool Developed, string Proof) key, TImage image)
    {
        if (revision != Revision) { return false; }
        Store(key, image);
        return true;
    }
    public void Clear() { Revision++; images.Clear(); }
}
