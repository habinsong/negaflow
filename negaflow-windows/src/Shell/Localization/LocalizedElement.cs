using Microsoft.UI.Xaml;

namespace Negaflow.Shell.Localization;

/// <summary>
/// 컨트롤이 <b>스스로</b> 언어를 따라가게 합니다.
/// </summary>
/// <remarks>
/// <para>
/// 앞 판은 문구를 다시 거는 길이 <c>Localize()</c> 사슬 하나뿐이었습니다 — 셸이 도구막대를
/// 부르고, 도구막대가 자식을 부르고… 어느 한 마디에서 부모가 자식을 안 부르면 그 아래는
/// 통째로 옛 언어로 남습니다. 실제로 <c>ColorGradingEditor</c>(어두운 영역·중간톤·밝은
/// 영역·색조·채도)와 <c>ColorMixerEditor</c> 가 그렇게 남아 있었습니다: 두 편집기는 문구를
/// <b>생성자에서만</b> 걸었고, 이들을 담은 구역의 <c>Localize()</c> 는 머리글만 다시 걸었습니다.
/// </para>
/// <para>
/// 그래서 <b>부모가 잊어도 되게</b> 바꿉니다. 잎 컨트롤이 이 자리에 자기 문구 거는 법을
/// 맡기면, 화면에 붙어 있는 동안 <see cref="AppResources.LanguageChanged"/> 를 스스로 듣습니다.
/// macOS 에서 SwiftUI 가 <c>model.appLanguage</c> 를 관찰해 그 자리에서 다시 그리는 것과
/// 같은 자리입니다.
/// </para>
/// <para>
/// <b>붙어 있는 동안만</b> 듣습니다. <see cref="AppResources.LanguageChanged"/> 는 static 이라
/// 계속 걸어 두면 떼어 낸 컨트롤이 살아남습니다(누수). <see cref="FrameworkElement.Unloaded"/>
/// 에서 떼고 <see cref="FrameworkElement.Loaded"/> 에서 다시 겁니다 — 탭을 오가느라 떼였다
/// 붙는 컨트롤도 다시 듣게 됩니다.
/// </para>
/// </remarks>
internal static class LocalizedElement
{
    /// <summary>
    /// 지금 한 번 걸고, 화면에 붙어 있는 동안 언어가 바뀔 때마다 다시 겁니다.
    /// </summary>
    /// <param name="element">문구를 담은 컨트롤입니다.</param>
    /// <param name="localize">문구를 거는 일입니다. 여러 번 불려도 같아야 합니다.</param>
    public static void Track(FrameworkElement element, Action localize)
    {
        ArgumentNullException.ThrowIfNull(element);
        ArgumentNullException.ThrowIfNull(localize);

        void OnLanguageChanged(object? sender, EventArgs args)
        {
            _ = sender;
            _ = args;
            localize();
        }

        element.Loaded += (_, _) =>
        {
            // 붙을 때마다 한 번씩만 걸리게 합니다 — 떼임 없이 다시 붙는 길이 있습니다.
            AppResources.LanguageChanged -= OnLanguageChanged;
            AppResources.LanguageChanged += OnLanguageChanged;
            localize();
        };
        element.Unloaded += (_, _) => AppResources.LanguageChanged -= OnLanguageChanged;

        localize();
    }

    /// <summary>
    /// 창 제목처럼 <see cref="FrameworkElement"/> 가 아닌 자리를 위한 것입니다. 창은
    /// 붙었다 떼였다 하지 않으므로 닫힐 때까지 듣습니다.
    /// </summary>
    public static void Track(Window window, Action localize)
    {
        ArgumentNullException.ThrowIfNull(window);
        ArgumentNullException.ThrowIfNull(localize);

        void OnLanguageChanged(object? sender, EventArgs args)
        {
            _ = sender;
            _ = args;
            localize();
        }

        AppResources.LanguageChanged += OnLanguageChanged;
        window.Closed += (_, _) => AppResources.LanguageChanged -= OnLanguageChanged;
        localize();
    }
}
