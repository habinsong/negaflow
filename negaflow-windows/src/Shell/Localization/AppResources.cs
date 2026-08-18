using Microsoft.Windows.ApplicationModel.Resources;
using System.Runtime.InteropServices;

namespace Negaflow.Shell.Localization;

internal static class AppResources
{
    private static readonly ResourceLoader Loader = new();

    public static string Get(string key, string property)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentException.ThrowIfNullOrWhiteSpace(property);
        string value;
        try
        {
            value = Loader.GetString($"{key}/{property}");
        }
        catch (COMException exception) when (unchecked((uint)exception.HResult) == 0x80073B17)
        {
            // ResourceLoader 는 없는 키에 빈 문자열이 아니라 0x80073B17 을 던집니다.
            // https://learn.microsoft.com/windows/uwp/app-resources/localize-strings-ui-manifest
            throw new InvalidOperationException(
                $"Missing localized resource: {key}.{property}",
                exception);
        }

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
