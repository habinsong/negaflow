using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Shortcuts;

namespace Negaflow.Shell.Views.Library.Defaults;

/// <summary>
/// 가져오기 패널의 "현상" 구획입니다. macOS <c>DevelopDefaultsSection</c> 과 같은 세 줄 —
/// 프로세스, 타깃, 그리고 필름 프로파일과 룩.
/// </summary>
/// <remarks>
/// 여기서 고른 것은 **지금 고른 사진**에 걸립니다. 고른 사진이 없으면 컨트롤이 꺼집니다 —
/// 아무 데도 닿지 않는 고르개를 켜 두면 사용자는 눌러 놓고 왜 안 바뀌는지 알 수 없습니다.
/// </remarks>
public sealed partial class LibraryDevelopDefaultsPanel : UserControl
{
    private LibraryHostService? libraryHost;
    private Func<LibraryFrameSnapshot?>? actionableFrame;
    private bool isSynchronizingDevelopDefaults;

    public LibraryDevelopDefaultsPanel() => InitializeComponent();

    public event EventHandler? LibraryChanged;

    public void Bind(LibraryHostService host, Func<LibraryFrameSnapshot?> actionable)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(actionable);
        libraryHost = host;
        actionableFrame = actionable;
    }

    /// <summary>
    /// 이 구획이 손대는 사진입니다. macOS <c>actionableFrame</c> 과 같이 격자에서 마지막으로
    /// 고른 한 장입니다.
    /// </summary>
    private LibraryFrameSnapshot? ActionableFrame => actionableFrame?.Invoke();

    public void Localize()
    {
        DevelopDefaultsText.Text = AppResources.Get("libraryDevelopDefaults", "Text");
        DevelopProcessLabel.Text = AppResources.Get("libraryProcess", "Text");
        AutomationProperties.SetName(DevelopProcessSelector, DevelopProcessLabel.Text);
        DevelopTargetLabel.Text = AppResources.Get("libraryTarget", "Text");
        AutomationProperties.SetName(DevelopTargetBar, DevelopTargetLabel.Text);
        DevelopFilmProfileLabel.Text = AppResources.Get("libraryFilmProfile", "Text");
        AutomationProperties.SetName(DevelopFilmProfileSelector, DevelopFilmProfileLabel.Text);
        DevelopLookLabel.Text = AppResources.Get("libraryLook", "Text");
        AutomationProperties.SetName(DevelopLookSelector, DevelopLookLabel.Text);

        DevelopProcessSelector.ItemsSource = ProcessChoices;
        BuildDevelopTargetBar();
    }

    /// <summary>
    /// macOS <c>SegmentedPicker(options: visibleTargets, …)</c> 입니다. 칸은 라디오라
    /// 한 번에 하나만 켜지고, 켜진 칸은 판형이 칠합니다 — 여기서 색을 손대지 않습니다.
    /// </summary>
    private void BuildDevelopTargetBar()
    {
        DevelopTargetBar.Children.Clear();
        int column = 0;
        foreach (DevelopTarget target in DevelopTargets.Visible)
        {
            DevelopTarget value = target;
            RadioButton segment = new()
            {
                Content = DevelopTargets.DisplayName(target),
                Style = (Style)Application.Current.Resources["NegaflowSegmentStyle"],
                GroupName = "DevelopTarget",
                Tag = target,
            };
            AutomationProperties.SetAutomationId(
                segment,
                "negaflow.library.develop.target." + target.ToString().ToLowerInvariant());
            // macOS 도 이미 고른 칸을 다시 눌렀을 때는 아무것도 하지 않습니다
            // (`if option != selection { selection = option }`).
            segment.Checked += (_, _) =>
            {
                if (isSynchronizingDevelopDefaults)
                {
                    return;
                }
                ApplyDevelopTarget(value);
            };
            Grid.SetColumn(segment, column++);
            DevelopTargetBar.Children.Add(segment);
        }
    }

    /// <summary>고른 사진의 값으로 구획을 맞춥니다.</summary>
    public void Synchronize()
    {
        if (DevelopTargetBar is null)
        {
            return;
        }
        LibraryFrameSnapshot? frame = ActionableFrame;
        bool enabled = frame is not null && libraryHost is not null;
        DevelopProcessSelector.IsEnabled = enabled;
        DevelopFilmProfileSelector.IsEnabled = enabled;
        DevelopLookSelector.IsEnabled = enabled;

        DevelopTarget target = frame?.DevelopTarget ?? DevelopTarget.Main;
        DevelopTarget family = DevelopTargets.Family(target);

        isSynchronizingDevelopDefaults = true;
        try
        {
            foreach (RadioButton segment in DevelopTargetBar.Children.OfType<RadioButton>())
            {
                segment.IsEnabled = enabled;
                segment.IsChecked = segment.Tag is DevelopTarget candidate && candidate == family;
            }

            DevelopProcessSelector.SelectedItem = ProcessChoices
                .FirstOrDefault(choice => choice.Process == (frame is null
                    ? DevelopmentProcess.C41
                    : DevelopProcesses.From(
                        frame.Route.FilmType,
                        frame.Route.SourceSignalKind == SourceSignalKind.RenderedDigital)));
            BuildFilmProfileChoices(frame, family);
            IReadOnlyList<ScannerProfileChoice> looks = LookChoices();
            DevelopLookSelector.ItemsSource = looks;
            // macOS `lookPresetBinding` 은 프레임에 룩이 없으면 **neutral 을 보여 줍니다**
            // (`model.actionableFrame?.preset ?? neutralPreset`). 비워 두면 사용자는
            // 룩이 없는 것인지 못 읽은 것인지 알 수 없습니다.
            DevelopLookSelector.SelectedItem =
                looks.FirstOrDefault(choice => choice.Id == frame?.LookPresetId)
                ?? looks.FirstOrDefault(choice =>
                    string.Equals(choice.Id, "neutral", StringComparison.Ordinal));
        }
        finally
        {
            isSynchronizingDevelopDefaults = false;
        }
    }

    /// <summary>
    /// 필름 프로파일 칸입니다. macOS 처럼 갈래에 따라 **다른 것을 고릅니다** — MAIN 갈래에서는
    /// MAIN/PRINT/EXPIRED 중 하나를, HS·SP 에서는 그 기종의 필름 프로파일을 고릅니다. F135·HR
    /// 은 고를 것이 없어 이름만 보입니다.
    /// </summary>
    private void BuildFilmProfileChoices(LibraryFrameSnapshot? frame, DevelopTarget family)
    {
        List<ScannerProfileChoice> choices = [];
        // 고를 것이 있는 갈래로 돌아오면 고르개를 다시 보입니다.
        DevelopFilmProfileText.Visibility = Visibility.Collapsed;
        DevelopFilmProfileSelector.Visibility = Visibility.Visible;
        if (family == DevelopTarget.Main)
        {
            foreach (DevelopTarget candidate in DevelopTargets.MainFamily)
            {
                choices.Add(new ScannerProfileChoice(
                    candidate.ToString(),
                    DevelopTargets.DisplayName(candidate)));
            }
            DevelopFilmProfileSelector.ItemsSource = choices;
            DevelopFilmProfileSelector.SelectedItem = choices.FirstOrDefault(choice =>
                choice.Id == (frame?.DevelopTarget ?? DevelopTarget.Main).ToString());
            return;
        }
        if (family is DevelopTarget.Noritsu or DevelopTarget.Sp3000)
        {
            choices.Add(new ScannerProfileChoice(null, DevelopTargets.DisplayName(family)));
            foreach (ScannerProfileOption option in DevelopTargets.MatchingProfiles(
                         family,
                         frame?.Route.FilmType ?? FilmType.ColorNegative))
            {
                choices.Add(new ScannerProfileChoice(option.Id, CompactFilmName(option)));
            }
            DevelopFilmProfileSelector.ItemsSource = choices;
            DevelopFilmProfileSelector.SelectedItem = choices.FirstOrDefault(choice =>
                choice.Id == frame?.Base.ScannerProfileId);
            return;
        }
        // macOS 는 이 갈래에서 고르개 대신 타깃 이름만 흐린 글씨로 둡니다 — 고를 것이 없으므로
        // 고르개 테두리를 남기면 누를 수 있는 것처럼 보입니다.
        DevelopFilmProfileText.Text = DevelopTargets.DisplayName(family);
        DevelopFilmProfileText.Visibility = Visibility.Visible;
        DevelopFilmProfileSelector.Visibility = Visibility.Collapsed;
        choices.Add(new ScannerProfileChoice(null, DevelopTargets.DisplayName(family)));
        DevelopFilmProfileSelector.ItemsSource = choices;
        DevelopFilmProfileSelector.SelectedIndex = 0;
    }

    /// <summary>
    /// 좁은 사이드바에서도 필름을 구분할 수 있게 기종과 갈래를 뗀 이름입니다 — macOS
    /// <c>compactFilmName</c> 과 같은 뜻입니다.
    /// </summary>
    private static string CompactFilmName(ScannerProfileOption option)
    {
        if (option.Id is not { } id)
        {
            return option.DisplayName;
        }
        int marker = id.LastIndexOf("__", StringComparison.Ordinal);
        string film = marker < 0 ? id : id[(marker + 2)..];
        return film.Replace('-', ' ');
    }

    /// <summary>
    /// 프로세스 여섯 개입니다. 폴더 머리줄과 같은 목록이지만 그쪽은 구획마다 새로 만들므로,
    /// 여기서는 한 벌을 두고 씁니다.
    /// </summary>
    private static IReadOnlyList<DevelopProcessChoice> ProcessChoices { get; } =
        [.. DevelopProcesses.All.Select(process =>
            new DevelopProcessChoice(process, DevelopProcesses.DisplayName(process)))];

    private static IReadOnlyList<ScannerProfileChoice> LookChoices() =>
        [.. LookPresetLibrary.All.Select(preset =>
            new ScannerProfileChoice(preset.Id, preset.Name))];

    private void OnDevelopProcessChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingDevelopDefaults || libraryHost is null ||
            ActionableFrame is not { } frame ||
            DevelopProcessSelector.SelectedItem is not DevelopProcessChoice choice)
        {
            return;
        }
        if (libraryHost.EditRoute(frame.Id, DevelopRouteSelection.FromProcess(choice.Process)) ==
            LibraryFrameError.None)
        {
            NotifyChanged();
        }
    }

    /// <summary>
    /// 타깃을 바꿉니다. macOS 처럼 **스캐너 프로파일도 함께 정리합니다** — 남겨 두면 타깃의
    /// 성격과 프로파일의 성격이 겹칩니다.
    /// </summary>
    private void ApplyDevelopTarget(DevelopTarget target)
    {
        if (libraryHost is not { } host || ActionableFrame is not { } frame)
        {
            return;
        }
        if (DevelopDefaultsCommands.ApplyTarget(host, frame, target) == LibraryFrameError.None)
        {
            NotifyChanged();
        }
    }

    /// <summary>
    /// 값을 바꾼 뒤에는 **이 구획을 다시 그립니다.** macOS 는 피커가 상태에 묶여 있어
    /// 타깃을 바꾸면 필름 프로파일 목록이 그 자리에서 따라옵니다(`targetFamily` 가 바뀌므로).
    /// Windows 는 스스로 다시 읽지 않으면 옛 목록이 남습니다 — 실제로 HS 로 바꿔도
    /// 필름 프로파일이 `MAIN` 으로 남아 있었습니다.
    /// </summary>
    private void NotifyChanged()
    {
        // 먼저 알립니다 — 뷰가 카탈로그에서 프레임을 다시 읽어야 아래 Synchronize 가
        // **새 값**을 봅니다. 순서를 뒤집으면 옛 스냅숏을 읽어 방금 고른 칸이 도로 풀립니다.
        LibraryChanged?.Invoke(this, EventArgs.Empty);
        Synchronize();
    }

    /// <summary>단축키가 부른 타깃 전환입니다. 타깃 막대를 누른 것과 같은 길을 탑니다.</summary>
    public void ApplyTarget(DevelopTarget target) => ApplyDevelopTarget(target);

    /// <summary>단축키가 부른 프로세스 전환입니다. 고르개를 누른 것과 같은 길을 탑니다.</summary>
    public void ApplyProcess(WorkflowShortcutAction action)
    {
        if (libraryHost is not { } host || ActionableFrame is not { } frame)
        {
            return;
        }
        if (DevelopDefaultsCommands.ApplyProcess(
                host,
                frame,
                DevelopDefaultsCommands.ProcessFor(action)) == LibraryFrameError.None)
        {
            NotifyChanged();
        }
    }

    private void OnDevelopFilmProfileChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingDevelopDefaults || libraryHost is not { } host ||
            ActionableFrame is not { } frame ||
            DevelopFilmProfileSelector.SelectedItem is not ScannerProfileChoice choice)
        {
            return;
        }
        DevelopTarget family = DevelopTargets.Family(frame.DevelopTarget);
        // MAIN 갈래에서는 이 칸이 타깃 자체(MAIN/PRINT/EXPIRED)를 고릅니다.
        if (family == DevelopTarget.Main)
        {
            if (Enum.TryParse(choice.Id, out DevelopTarget picked) &&
                picked != frame.DevelopTarget)
            {
                ApplyDevelopTarget(picked);
            }
            return;
        }
        if (family is not (DevelopTarget.Noritsu or DevelopTarget.Sp3000) ||
            string.Equals(choice.Id, frame.Base.ScannerProfileId, StringComparison.Ordinal))
        {
            return;
        }
        if (host.Edit(
                frame.Id,
                new LibraryFrameEdit(
                    frame.Tone,
                    frame.ManualBase,
                    frame.Base with { ScannerProfileId = choice.Id })) == LibraryFrameError.None)
        {
            NotifyChanged();
        }
    }

    private void OnDevelopLookChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingDevelopDefaults || libraryHost is not { } host ||
            ActionableFrame is not { } frame ||
            DevelopLookSelector.SelectedItem is not ScannerProfileChoice choice ||
            string.Equals(choice.Id, frame.LookPresetId, StringComparison.Ordinal))
        {
            return;
        }
        if (host.Edit(
                frame.Id,
                new LibraryFrameEdit(
                    frame.Tone,
                    frame.ManualBase,
                    LookPreset: new LookPresetSelection(choice.Id))) == LibraryFrameError.None)
        {
            NotifyChanged();
        }
    }
}
