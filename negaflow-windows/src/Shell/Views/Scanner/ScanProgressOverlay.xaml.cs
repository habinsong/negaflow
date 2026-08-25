using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Scanner;

/// <summary>
/// 스캔이 도는 동안 단계와 진행률을 보여 주는 카드입니다.
/// </summary>
/// <remarks>
/// macOS <c>App/Content/ScanProgressOverlay.swift</c> 를 그대로 옮겼습니다. 놓이는 자리도 같습니다 —
/// <c>ContentView+CenterStatus.swift</c> 가 캔버스 위에
/// <c>.overlay(alignment: .bottom) { … .allowsHitTesting(false).padding(.bottom, 18) }</c> 로
/// 얹고, <c>model.isScanning</c> 일 때만 보입니다.
///
/// macOS 는 <c>TimelineView(.periodic(by: 0.25))</c> 로 0.25 초마다 다시 그립니다. 여기서는 같은
/// 주기의 타이머가 그 자리를 대신합니다 — 진행 이벤트가 뜸해도 초 단위로 화면이 살아 있어야
/// 하고, 이벤트마다 그리면 초당 수십 번이 됩니다.
/// </remarks>
public sealed partial class ScanProgressOverlay : UserControl
{
    private readonly DispatcherTimer timer = new()
    {
        Interval = TimeSpan.FromMilliseconds(250),
    };

    private ScanProgressState? state;

    public ScanProgressOverlay()
    {
        InitializeComponent();
        timer.Tick += (_, _) => Render();
        Unloaded += (_, _) => timer.Stop();
    }

    /// <summary>어느 스캔을 보여 줄지 겁니다. 다시 걸면 앞의 것은 놓습니다.</summary>
    public void Bind(ScanProgressState? progress)
    {
        if (ReferenceEquals(state, progress))
        {
            return;
        }
        if (state is not null)
        {
            state.Changed -= OnProgressChanged;
        }
        state = progress;
        if (state is not null)
        {
            state.Changed += OnProgressChanged;
        }
        Render();
    }

    /// <summary>문구만 다시 겁니다. 언어를 바꾸면 셸이 부릅니다.</summary>
    public void Localize() => Render();

    private void OnProgressChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (DispatcherQueue is { } queue && !queue.HasThreadAccess)
        {
            // 진행 줄은 플러그인 출력을 읽는 워커에서 옵니다. 거기서 XAML 을 건드리면
            // WinUI 가 `COMException`(RPC_E_WRONG_THREAD) 을 던집니다.
            _ = queue.TryEnqueue(Render);
            return;
        }
        Render();
    }

    private void Render()
    {
        if (state is not { IsScanning: true })
        {
            Visibility = Visibility.Collapsed;
            timer.Stop();
            return;
        }
        if (!timer.IsEnabled)
        {
            timer.Start();
        }
        Visibility = Visibility.Visible;
        double fraction = state.DisplayedFraction();
        PhaseText.Text = AppResources.Get(ScanProgressState.PhaseKeyFor(state.Phase), "Text");
        // macOS: Text("\(Int((fraction * 100).rounded()))%")
        PercentText.Text = string.Create(
            CultureInfo.InvariantCulture,
            $"{(int)Math.Round(fraction * 100.0, MidpointRounding.AwayFromZero)}%");
        Bar.Value = Math.Clamp(fraction, 0.0, 1.0);
        MessageText.Text = state.Phase == ScanPhase.Error && state.ErrorMessage.Length != 0
            ? state.ErrorMessage
            : AppResources.Get(state.MessageKey, "Text");
    }
}
