using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Negaflow.Interop;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>
/// 프레임 규격 고르개의 선택지 표식입니다. macOS <c>ScanFrameFormatChoice</c> 의
/// <c>.custom</c> 자리이고, 규격 항목의 Tag 는 <see cref="FlatbedFrameFormat"/> 그대로입니다.
/// </summary>
internal static class ScanFrameFormatChoice
{
    /// <summary>목록 맨 아래 "수동 비율" 항목입니다.</summary>
    internal static readonly object Custom = new();

    /// <summary>규격과 수동 비율 사이 구분선입니다(macOS <c>Divider()</c>). 고를 수 없습니다.</summary>
    internal static readonly object Separator = new();
}

/// <summary>
/// 수동 비율 입력(가로 : 세로, 단위 없음)과, 규격·비율이 바뀐 뒤 프레임을 다시 찾는 일입니다.
/// macOS <c>ScanCustomFrameSizeRow</c> 와 <c>applyScanFrameSizeChange()</c> 를 옮겼습니다.
/// </summary>
/// <remarks>
/// 입력하는 동안에는 적용하지 않습니다. Enter 나 두 칸 밖으로 포커스가 빠질 때 한 번 적용하고,
/// 두 칸 사이를 오가는 동안은 적용하지 않습니다. Esc 는 입력을 버리고 적용된 값으로 되돌립니다.
/// 받지 않은 값은 경고음을 내고 되돌립니다 — 안내 문구는 두지 않습니다(macOS 와 같습니다).
/// </remarks>
internal sealed class LibraryScanCustomRatio
{
    private readonly LibraryScanPanel view;
    private FilmFrameRatio? shownRatio;
    private bool rowWasVisible;

    internal LibraryScanCustomRatio(LibraryScanPanel view)
    {
        this.view = view;
        foreach (TextBox box in Boxes)
        {
            box.PreviewKeyDown += OnPreviewKeyDown;
            box.LostFocus += OnLostFocus;
        }
    }

    private TextBox[] Boxes => [view.ScanCustomFrameWidthBox, view.ScanCustomFrameHeightBox];

    /// <summary>
    /// 줄이 보이기 시작하거나 적용된 비율이 바뀌면 칸을 그 값으로 채웁니다(macOS <c>onAppear</c>,
    /// <c>onChange(of: scanCustomFrameRatio)</c>). 그 밖에는 입력 중인 글자를 건드리지 않습니다.
    /// </summary>
    internal void Sync(bool visible)
    {
        if (!visible)
        {
            rowWasVisible = false;
            return;
        }
        FilmFrameRatio? applied = view.scanSession?.Options.CustomFrameRatio;
        if (!rowWasVisible || applied != shownRatio)
        {
            ShowAppliedRatio();
        }
        rowWasVisible = true;
    }

    /// <summary>
    /// 규격이나 수동 비율이 바뀐 뒤 공통으로 할 일입니다. 평판이면 찾아 둔 프레임을 비우고,
    /// 시뮬레이터면 새 치수로 프리뷰를 다시 찍고, 아니면 지금 프리뷰에서 다시 찾습니다.
    /// macOS <c>applyScanFrameSizeChange()</c>.
    /// </summary>
    internal async Task ApplyFrameSizeChangeAsync()
    {
        if (view.scanSession is not { } session)
        {
            return;
        }
        if (session.UsesFlatbedRegionWorkflow)
        {
            bool hasPreview = !view.FlatbedPreview.IsEmpty;
            session.ClearRegions();
            if (session.SimulatorEnabled && hasPreview)
            {
                await view.runner.RunAsync(preview: true);
                return;
            }
            if (hasPreview &&
                session.Options.FrameDetectionMode == FlatbedFrameDetectionMode.Automatic)
            {
                _ = session.RefreshRegions(
                    view.FlatbedPreview.Values,
                    view.FlatbedPreview.Width,
                    view.FlatbedPreview.Height,
                    view.FlatbedPreview.PhysicalWidthMm,
                    view.FlatbedPreview.PhysicalHeightMm);
            }
        }
        view.renderer.Render();
    }

    private void ShowAppliedRatio()
    {
        FilmFrameRatio? applied = view.scanSession?.Options.CustomFrameRatio;
        shownRatio = applied;
        if (applied is null)
        {
            return;
        }
        view.ScanCustomFrameWidthBox.Text = FilmFrameRatio.Number(applied.Width);
        view.ScanCustomFrameHeightBox.Text = FilmFrameRatio.Number(applied.Height);
    }

    /// <summary>
    /// Enter 는 칸을 벗어나며 적용하고(적용은 포커스 이탈에서 한 번만), Esc 는 입력을 버리고
    /// 칸을 벗어납니다. **둘 다 여기서 소비합니다** — 올려보내면 Esc 는 스캐너 패널을 닫고
    /// Enter 는 스캔을 시작합니다(장수 상자와 같은 규칙).
    /// </summary>
    private void OnPreviewKeyDown(object sender, KeyRoutedEventArgs args)
    {
        switch (args.Key)
        {
            case Windows.System.VirtualKey.Escape:
                ShowAppliedRatio();
                MoveFocusOff();
                args.Handled = true;
                return;
            case Windows.System.VirtualKey.Enter:
                MoveFocusOff();
                args.Handled = true;
                return;
            default:
                return;
        }
    }

    /// <summary>
    /// 두 칸 사이를 오가는 동안에는 적용하지 않습니다. 칸을 완전히 벗어날 때 적용합니다.
    /// </summary>
    private async void OnLostFocus(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (view.XamlRoot is { } root &&
            FocusManager.GetFocusedElement(root) is TextBox focused &&
            Array.IndexOf(Boxes, focused) >= 0)
        {
            return;
        }
        await CommitAsync();
    }

    /// <summary>받지 않은 값은 경고음을 내고 입력칸을 지금 적용된 비율로 되돌립니다.</summary>
    private async Task CommitAsync()
    {
        if (view.scanSession is not { } session)
        {
            return;
        }
        if (FilmFrameRatio.Parse(view.ScanCustomFrameWidthBox.Text) is not { } width ||
            FilmFrameRatio.Parse(view.ScanCustomFrameHeightBox.Text) is not { } height)
        {
            _ = MessageBeep(0);
            ShowAppliedRatio();
            return;
        }
        if (session.Options.CustomFrameRatio is { } applied &&
            applied.Width == width && applied.Height == height)
        {
            ShowAppliedRatio();
            return;
        }
        CustomFrameRatioUpdate result = session.UpdateCustomFrameRatio(width, height);
        if (result == CustomFrameRatioUpdate.Rejected)
        {
            _ = MessageBeep(0);
        }
        ShowAppliedRatio();
        if (result == CustomFrameRatioUpdate.Changed && session.Options.UsesCustomFrameRatio)
        {
            await ApplyFrameSizeChangeAsync();
        }
    }

    /// <summary>
    /// 칸에서 포커스를 뺍니다. 라벨을 잠깐 탭 대상으로 만들어 받게 합니다 — 장수 상자와 같은
    /// 방법이고, 다른 컨트롤로 포커스를 넘기면 그 컨트롤이 Enter 를 받아 버립니다.
    /// </summary>
    private void MoveFocusOff()
    {
        view.ScanCustomFrameRatioLabel.IsTabStop = true;
        _ = view.ScanCustomFrameRatioLabel.Focus(FocusState.Programmatic);
        view.ScanCustomFrameRatioLabel.IsTabStop = false;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool MessageBeep(uint type);
}
