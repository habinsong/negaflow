using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 가져오기 패널의 "현상" 구획입니다. macOS <c>DevelopDefaultsSection</c> 과 같은 세 줄 —
/// 프로세스, 타깃, 그리고 필름 프로파일과 룩.
/// </summary>
/// <remarks>
/// 여기서 고른 것은 **지금 고른 사진**에 걸립니다. 고른 사진이 없으면 컨트롤이 꺼집니다 —
/// 아무 데도 닿지 않는 고르개를 켜 두면 사용자는 눌러 놓고 왜 안 바뀌는지 알 수 없습니다.
/// </remarks>
public sealed partial class LibraryWorkspaceView
{
    private bool isSynchronizingDevelopDefaults;

    /// <summary>
    /// 이 구획이 손대는 사진입니다. macOS <c>actionableFrame</c> 과 같이 격자에서 마지막으로
    /// 고른 한 장입니다.
    /// </summary>
    private LibraryFrameSnapshot? ActionableFrame =>
        FrameListView?.SelectedItem is LibraryFrameListItem item ? item.Frame : null;

    private void LocalizeDevelopDefaults()
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

    private void BuildDevelopTargetBar()
    {
        DevelopTargetBar.Children.Clear();
        int column = 0;
        foreach (DevelopTarget target in DevelopTargets.Visible)
        {
            DevelopTarget value = target;
            Button button = new()
            {
                Content = DevelopTargets.DisplayName(target),
                HorizontalAlignment = HorizontalAlignment.Stretch,
                FontSize = 11,
                Padding = new Thickness(2, 4, 2, 4),
                Tag = target,
            };
            AutomationProperties.SetAutomationId(
                button,
                "negaflow.library.develop.target." + target.ToString().ToLowerInvariant());
            button.Click += (_, _) => ApplyDevelopTarget(value);
            Grid.SetColumn(button, column++);
            DevelopTargetBar.Children.Add(button);
        }
    }

    /// <summary>고른 사진의 값으로 구획을 맞춥니다.</summary>
    private void SynchronizeDevelopDefaults()
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
        foreach (Button button in DevelopTargetBar.Children.OfType<Button>())
        {
            bool selected = button.Tag is DevelopTarget candidate && candidate == family;
            button.IsEnabled = enabled;
            button.Background = selected
                ? new SolidColorBrush(Windows.UI.Color.FromArgb(0x2D, 0x6B, 0x8B, 0xFF))
                : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            button.FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal;
            button.Opacity = selected ? 1 : 0.72;
        }

        isSynchronizingDevelopDefaults = true;
        try
        {
            DevelopProcessSelector.SelectedItem = ProcessChoices
                .FirstOrDefault(choice => choice.Process == (frame is null
                    ? DevelopmentProcess.C41
                    : DevelopProcesses.From(
                        frame.Route.FilmType,
                        frame.Route.SourceSignalKind == SourceSignalKind.RenderedDigital)));
            BuildFilmProfileChoices(frame, family);
            DevelopLookSelector.ItemsSource = LookChoices();
            DevelopLookSelector.SelectedItem = LookChoices()
                .FirstOrDefault(choice => choice.Id == frame?.LookPresetId);
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
            ShowLibrary(libraryHost, importWindowId ?? default);
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
        string? profileId = DevelopTargets.ProfileAfterTargetChange(
            target,
            frame.Route.FilmType,
            frame.Base.ScannerProfileId);
        if (host.Edit(
                frame.Id,
                new LibraryFrameEdit(
                    frame.Tone,
                    frame.ManualBase,
                    frame.Base with { ScannerProfileId = profileId },
                    DevelopTarget: target)) == LibraryFrameError.None)
        {
            ShowLibrary(host, importWindowId ?? default);
        }
    }

    /// <summary>단축키가 부른 프로세스 전환입니다. 고르개를 누른 것과 같은 길을 탑니다.</summary>
    private void ApplyDevelopProcess(Shortcuts.WorkflowShortcutAction action)
    {
        if (libraryHost is not { } host || ActionableFrame is not { } frame)
        {
            return;
        }
        DevelopmentProcess process = action switch
        {
            Shortcuts.WorkflowShortcutAction.ProcessColorPositive => DevelopmentProcess.E6,
            Shortcuts.WorkflowShortcutAction.ProcessBwNegative => DevelopmentProcess.D76,
            Shortcuts.WorkflowShortcutAction.ProcessBwPositive =>
                DevelopmentProcess.BlackAndWhiteReversal,
            _ => DevelopmentProcess.C41,
        };
        if (host.EditRoute(frame.Id, DevelopRouteSelection.FromProcess(process)) ==
            LibraryFrameError.None)
        {
            ShowLibrary(host, importWindowId ?? default);
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
            ShowLibrary(host, importWindowId ?? default);
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
            ShowLibrary(host, importWindowId ?? default);
        }
    }
}
