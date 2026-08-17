using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Info;

/// <summary>
/// 현상 정보 탭의 네 카드입니다. 원본 정보, 앱 메타데이터, 촬영 기록, 롤 기록을 담습니다.
/// </summary>
public sealed partial class DevelopInfoCards : UserControl
{
    private DevelopPanelState? panel;
    private LibraryHostService? libraryHost;
    private bool onInfoTab;
    private bool isSynchronizingMetadata;

    public DevelopInfoCards()
    {
        InitializeComponent();
        AppMetadata.Committed += OnAppMetadataCommitted;
        FilmShot.Committed += OnAppMetadataCommitted;
        RollCard.Committed += OnRollRecordCommitted;
        RollCard.CreateRequested += OnCreateRollClicked;
    }

    public void Bind(DevelopPanelState hostPanel, LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        ArgumentNullException.ThrowIfNull(host);
        panel = hostPanel;
        libraryHost = host;
    }

    public void Localize()
    {
        InfoCard.Update(panel?.SelectedFrame);
        AppMetadata.Localize();
        FilmShot.Localize();
        RollCard.Localize();
    }

    public void Apply(bool selected)
    {
        onInfoTab = selected;
        Visibility = selected ? Visibility.Visible : Visibility.Collapsed;
        InfoCard.Visibility = selected ? Visibility.Visible : Visibility.Collapsed;
        Update();
    }

    public void Update()
    {
        InfoCard.Update(panel?.SelectedFrame);
        UpdateAppMetadataCards();
        UpdateRollRecordCard();
    }

    /// <summary>
    /// 적어 둔 메타데이터를 컨트롤에 되비춥니다. 값이 없으면 빈 칸이고, placeholder 가 무엇을
    /// 적는 자리인지 말합니다 — macOS 도 라벨 대신 placeholder 를 씁니다.
    /// </summary>
    private void UpdateAppMetadataCards()
    {
        if (AppMetadata.TitleBox is null)
        {
            return;
        }
        bool hasFrame = panel?.SelectedFrame is not null;
        AppMetadata.Visibility = onInfoTab && hasFrame
            ? Visibility.Visible
            : Visibility.Collapsed;
        FilmShot.Visibility = AppMetadata.Visibility;
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }

        AppMetadataOverlay overlay = frame.AppMetadata ?? new AppMetadataOverlay();
        FilmShotMetadata shot = overlay.FilmShot ?? new FilmShotMetadata();
        isSynchronizingMetadata = true;
        try
        {
            AppMetadata.Show(overlay);
            FilmShot.Show(shot);
        }
        finally
        {
            isSynchronizingMetadata = false;
        }
    }

    /// <summary>
    /// 칸을 떠날 때 한 번만 씁니다. 글자마다 카탈로그를 건드리면 5만 행짜리 저장이 타이핑마다
    /// 돕니다.
    /// </summary>
    private void OnAppMetadataCommitted(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingMetadata || panel is null)
        {
            return;
        }
        FilmShotMetadata shot = FilmShot.Read();
        AppMetadataOverlay next = AppMetadata.Read(
            shot.Normalized().IsEmpty ? null : shot.Normalized());
        AppMetadataOverlay stored = panel.SelectedFrame?.AppMetadata ?? new AppMetadataOverlay();
        // 같은 값을 다시 쓰면 revision 만 오르고 카탈로그가 매번 더러워집니다.
        if (DevelopMetadataFields.Equivalent(stored, next))
        {
            return;
        }
        _ = panel.SetAppMetadata(_ => next);
        UpdateAppMetadataCards();
        InfoCard.Update(panel.SelectedFrame);
    }

    /// <summary>
    /// 롤 기록 카드입니다. 이 frame 이 롤에 속해 있을 때만 칸이 나오고, 아니면 macOS 와 같이
    /// 아직 롤에 속해 있지 않다고 알립니다.
    /// </summary>
    private void UpdateRollRecordCard()
    {
        if (RollCard.CodeBox is null)
        {
            return;
        }
        RollCard.Visibility = onInfoTab && panel?.SelectedFrame is not null
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (panel?.SelectedFrame is not { } frame || libraryHost is null)
        {
            return;
        }

        LibraryRollSnapshot? roll = libraryHost.RollFor(frame.Id);
        isSynchronizingMetadata = true;
        try
        {
            RollCard.Show(roll);
        }
        finally
        {
            isSynchronizingMetadata = false;
        }
    }

    /// <summary>
    /// 고른 사진으로 롤을 만듭니다. macOS 의 "선택 항목으로 롤 만들기" 와 같으며, 라이브러리에서
    /// 고른 것이 없으면 지금 보고 있는 한 장으로 만듭니다.
    /// </summary>
    private void OnCreateRollClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        IReadOnlyList<LibraryFrameSnapshot> selected = libraryHost.SelectedFrames;
        IReadOnlyList<LibraryFrameSnapshot> selection =
            selected.Count > 1 ? selected : [frame];
        // 이름은 원본이 들어 있는 폴더에서 옵니다. 사용자가 필름 봉투에 적은 이름이 대개
        // 그 폴더 이름이며, 없으면 macOS 의 "무제 필름" 자리를 씁니다.
        string name = Path.GetFileName(Path.GetDirectoryName(frame.SourcePath) ?? string.Empty);
        if (string.IsNullOrWhiteSpace(name))
        {
            name = AppResources.Get("scanUntitledFilm", "Text");
        }
        string? rollId = libraryHost.CreateRoll(
            name,
            frame.Route.FilmType,
            selection.Select(item => item.Id));
        if (rollId is not null)
        {
            // 새로 만든 롤이 곧 지금 스캔 중인 롤입니다 — macOS 도 만든 롤을 활성으로 둡니다.
            _ = libraryHost.SetActiveRoll(rollId);
        }
        UpdateRollRecordCard();
    }

    private void OnRollRecordCommitted(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingMetadata ||
            libraryHost is null ||
            panel?.SelectedFrame is not { } frame ||
            libraryHost.RollFor(frame.Id) is not { } roll)
        {
            return;
        }
        RollRecord next = RollCard.Read();
        if (next.Normalized() == (roll.Record ?? new RollRecord()).Normalized())
        {
            return;
        }
        _ = libraryHost.SetRollRecord(roll.Id, next);
        UpdateRollRecordCard();
    }
}
