using System.Runtime.InteropServices;
using Microsoft.Windows.ApplicationModel.Resources;

namespace Negaflow.Shell.Localization;

/// <summary>
/// 화면 문구를 냅니다. macOS <c>model.text(...)</c> 자리입니다.
/// </summary>
/// <remarks>
/// <para>
/// 언어는 <b>그 자리에서</b> 바뀝니다. macOS 는 <c>model.appLanguage</c> 가 바뀌면 모든
/// 문구가 다시 그려지므로, Windows 도 다시 시작하지 않고 따라가야 합니다.
/// </para>
/// <para>
/// 앞 판은 <c>ResourceLoader</c> 를 <c>static readonly</c> 로 한 번 만들어 두고 썼습니다.
/// 그 인스턴스는 만들어질 때의 언어 문맥을 그대로 들고 있어서,
/// <c>ApplicationLanguages.PrimaryLanguageOverride</c> 를 바꿔도 **다음 실행까지** 문구가
/// 그대로였습니다. 그래서 MRT Core 의 <see cref="ResourceManager"/> 와 갈아 끼울 수 있는
/// <see cref="ResourceContext"/> 로 바꿉니다
/// (learn.microsoft.com/windows/apps/windows-app-sdk/mrtcore/localize-strings —
/// <c>context.QualifierValues["Language"]</c>).
/// </para>
/// </remarks>
internal static class AppResources
{
    private static readonly ResourceManager Manager = new();
    private static readonly ResourceMap Map = Manager.MainResourceMap.GetSubtree("Resources");
    private static ResourceContext context = Manager.CreateResourceContext();

    /// <summary>지금 언어입니다. 빈 문자열은 시스템 언어입니다.</summary>
    public static string Language { get; private set; } = AppLanguages.System;

    /// <summary>언어가 바뀌었습니다. 열려 있는 화면은 문구를 다시 걸어야 합니다.</summary>
    public static event EventHandler? LanguageChanged;

    /// <summary>
    /// 문구가 나올 언어를 바꿉니다. 같은 언어면 아무 것도 하지 않습니다 — 화면을 다시
    /// 그리는 값이 없는데 다시 그리면 깜빡임만 남습니다.
    /// </summary>
    public static void SetLanguage(string? language)
    {
        string normalized = AppLanguages.Normalize(language);
        if (string.Equals(normalized, Language, StringComparison.Ordinal))
        {
            return;
        }

        ResourceContext next = Manager.CreateResourceContext();
        if (normalized.Length != 0)
        {
            next.QualifierValues["Language"] = normalized;
        }
        context = next;
        Language = normalized;
        LanguageChanged?.Invoke(null, EventArgs.Empty);
    }

    public static string Get(string key, string property)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentException.ThrowIfNullOrWhiteSpace(property);
        string name = $"{key}/{property}";
        ResourceCandidate? candidate;
        try
        {
            candidate = Map.TryGetValue(name, context);
        }
        catch (Exception exception) when (exception is COMException or ArgumentException)
        {
            throw new InvalidOperationException(
                $"Missing localized resource: {key}.{property}",
                exception);
        }

        string value = candidate?.ValueAsString ?? string.Empty;
        if (string.IsNullOrEmpty(value))
        {
            throw new InvalidOperationException($"Missing localized resource: {key}.{property}");
        }

        return value;
    }

    public static string FormatInteger(string key, string property, int value) =>
        Get(key, property).Replace("%d", value.ToString(), StringComparison.Ordinal);

    public static string FormatIntegers(
        string key,
        string property,
        params int[] values)
    {
        string result = Get(key, property);
        foreach (int value in values)
        {
            int marker = result.IndexOf("%d", StringComparison.Ordinal);
            if (marker < 0)
            {
                throw new InvalidOperationException(
                    $"Localized resource has fewer integer markers than expected: {key}.{property}");
            }

            result = result[..marker] + value + result[(marker + 2)..];
        }

        return result;
    }
}
