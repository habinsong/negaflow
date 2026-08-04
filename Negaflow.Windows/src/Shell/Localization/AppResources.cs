using Microsoft.Windows.ApplicationModel.Resources;

namespace Negaflow.Shell.Localization;

internal static class AppResources
{
    private static readonly ResourceLoader Loader = new();

    public static string Get(string key, string property)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentException.ThrowIfNullOrWhiteSpace(property);
        string value = Loader.GetString($"{key}/{property}");
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
