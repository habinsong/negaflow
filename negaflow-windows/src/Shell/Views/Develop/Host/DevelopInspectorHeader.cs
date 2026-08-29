using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Host;

/// <summary>
/// 현상 인스펙터 머리줄 오른쪽 한 줄입니다. macOS <c>WorkspaceInspectorPane.inspectorHeader</c>
/// 의 <c>DevelopInspectorHeaderSummary</c> 자리입니다.
/// </summary>
/// <remarks>
/// 앞 판은 이 자리에 <c>"ISO — · — s · f/— · — mm"</c> 를 XAML 에 박아 두었습니다. 어떤
/// 사진을 열어도 같은 글자가 나왔으므로 값이 있는 파일에서도 없는 것처럼 보였습니다.
///
/// 가져온 파일의 촬영 기록은 <b>파일을 열어야</b> 알 수 있습니다. 여는 일은 UI 스레드에서
/// 하지 않고(WIC 는 STA 에서 <c>RPC_E_CHANGED_MODE</c> 를 냅니다) 뒤에서 읽은 뒤 그 사진이
/// 아직 열려 있을 때만 글자를 겁니다. 한 번 읽은 파일은 경로로 기억합니다 — 필름스트립을
/// 훑을 때마다 같은 파일을 다시 열지 않습니다.
/// </remarks>
internal sealed class DevelopInspectorHeader
{
    private readonly DevelopWorkspaceView view;

    /// <summary>원본 경로마다 한 번만 읽습니다. 읽지 못한 파일은 빈 값으로 기억합니다.</summary>
    private readonly Dictionary<string, ImageShotMetadata> byPath =
        new(StringComparer.OrdinalIgnoreCase);

    /// <summary>지금 머리줄이 말하고 있는 사진입니다. 늦게 온 결과를 버리는 기준입니다.</summary>
    private LibraryFrameSnapshot? shownFrame;

    internal DevelopInspectorHeader(DevelopWorkspaceView view) => this.view = view;

    /// <summary>사진이 하나도 없습니다. macOS 도 이 자리에 <c>noFrame</c> 을 냅니다.</summary>
    internal void Clear()
    {
        shownFrame = null;
        view.DevelopHeaderSummaryText.Text = AppResources.Get("noFrame", "Text");
    }

    internal void Update(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        shownFrame = frame;
        if (frame.SourceKind == FrameSourceKind.ScannerTiff)
        {
            view.DevelopHeaderSummaryText.Text =
                DevelopInspectorHeaderSummary.Text(frame, default);
            return;
        }
        string path = frame.SourcePath;
        if (byPath.TryGetValue(path, out ImageShotMetadata cached))
        {
            view.DevelopHeaderSummaryText.Text =
                DevelopInspectorHeaderSummary.ImportedMetadata(cached);
            return;
        }
        // 읽는 동안에는 빈 자리를 냅니다. 값을 지어내지 않으므로 macOS 가 태그 없는 파일에
        // 내는 것과 같은 글자입니다.
        view.DevelopHeaderSummaryText.Text =
            DevelopInspectorHeaderSummary.ImportedMetadata(default);
        string frameId = frame.Id;
        _ = Task.Run(() =>
        {
            ImageShotMetadata shot = default;
            try
            {
                _ = NativeImageShotProbe.TryRead(path, out shot);
            }
            catch (Exception)
            {
                // 촬영 기록을 못 읽는 것으로 사진 열기를 막지 않습니다. 빈 값으로 둡니다.
                shot = default;
            }
            _ = view.DispatcherQueue.TryEnqueue(() => Apply(path, frameId, shot));
        });
    }

    /// <summary>
    /// 언어가 바뀌었습니다. 사진이 없을 때의 <c>noFrame</c> 만 언어를 타므로 그 자리를 다시
    /// 겁니다 — ISO·f·mm 은 규격 표기라 언어와 무관합니다.
    /// </summary>
    internal void Localize()
    {
        if (shownFrame is { } frame)
        {
            Update(frame);
            return;
        }
        Clear();
    }

    private void Apply(string path, string frameId, ImageShotMetadata shot)
    {
        byPath[path] = shot;
        if (!string.Equals(shownFrame?.Id, frameId, StringComparison.Ordinal))
        {
            return;
        }
        view.DevelopHeaderSummaryText.Text =
            DevelopInspectorHeaderSummary.ImportedMetadata(shot);
    }
}
