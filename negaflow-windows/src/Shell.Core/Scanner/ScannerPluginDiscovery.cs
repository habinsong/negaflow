using System.Security.Cryptography;
using System.Text.Json;

namespace Negaflow.Shell;

public sealed record ScannerPluginManifest(
    int SchemaVersion,
    int? ProtocolVersion,
    string Id,
    string Name,
    string Executable,
    string? Kind,
    string? License,
    string? Homepage,
    string? PluginVersion)
{
    public const int SupportedSchemaVersion = 1;
    public const int LegacyProtocolVersion = 1;
    public const int StreamProtocolVersion = 2;

    public int ResolvedProtocolVersion => ProtocolVersion ?? LegacyProtocolVersion;

    public bool IsSupported =>
        SchemaVersion == SupportedSchemaVersion &&
        ResolvedProtocolVersion is >= LegacyProtocolVersion and <= StreamProtocolVersion &&
        IsValidPluginId(Id) &&
        string.Equals(Kind ?? "scanner", "scanner", StringComparison.Ordinal) &&
        !string.IsNullOrWhiteSpace(Name) &&
        !string.IsNullOrWhiteSpace(Executable);

    public static bool IsValidPluginId(string? value)
    {
        if (string.IsNullOrEmpty(value) || value.Length > 64 || !IsLetterOrDigit(value[0]))
        {
            return false;
        }

        return value.All(character =>
            IsLetterOrDigit(character) || character is '-' or '.' or '_');
    }

    private static bool IsLetterOrDigit(char value) =>
        value is >= '0' and <= '9' ||
        value is >= 'A' and <= 'Z' ||
        value is >= 'a' and <= 'z';
}

public sealed record ScannerPluginTrustIdentity(
    string PluginId,
    string? PluginVersion,
    string ManifestSha256,
    string ExecutableSha256);

public sealed record InstalledScannerPlugin(
    ScannerPluginManifest Manifest,
    string ManifestPath,
    string ExecutablePath,
    ScannerPluginTrustIdentity TrustIdentity);

// Scanner drivers stay out of the app process. This discovery boundary only accepts a bounded,
// non-reparse plugin directory with a manifest and executable whose bytes are identified again
// immediately before launch by the later process host.
public static class ScannerPluginDiscovery
{
    public const int MaximumManifestBytes = 256 * 1024;
    private static readonly JsonSerializerOptions ManifestJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
    };

    public static string DefaultPluginDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Negaflow",
        "Plugins");

    public static IReadOnlyList<InstalledScannerPlugin> Discover(string? pluginDirectory = null)
    {
        string root = Path.GetFullPath(pluginDirectory ?? DefaultPluginDirectory);
        if (!Directory.Exists(root) || IsReparsePoint(root))
        {
            return [];
        }

        var discovered = new List<InstalledScannerPlugin>();
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (string directory in Directory.EnumerateDirectories(root)
                     .OrderBy(path => Path.GetFileName(path), StringComparer.Ordinal))
        {
            if (IsReparsePoint(directory) ||
                !TryReadManifest(directory, out ScannerPluginManifest? manifest, out string manifestPath) ||
                !TryResolveExecutable(directory, manifest!.Executable, out string executablePath) ||
                !TryHashFile(manifestPath, out string manifestHash) ||
                !TryHashFile(executablePath, out string executableHash) ||
                !ids.Add(manifest.Id))
            {
                continue;
            }

            discovered.Add(new InstalledScannerPlugin(
                manifest,
                manifestPath,
                executablePath,
                new ScannerPluginTrustIdentity(
                    manifest.Id,
                    manifest.PluginVersion,
                    manifestHash,
                    executableHash)));
        }

        return discovered;
    }

    public static bool HasCurrentTrustIdentity(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity)
    {
        ArgumentNullException.ThrowIfNull(plugin);
        ArgumentNullException.ThrowIfNull(approvedIdentity);

        if (!string.Equals(plugin.Manifest.Id, approvedIdentity.PluginId, StringComparison.Ordinal) ||
            !TryReadManifest(
                Path.GetDirectoryName(plugin.ManifestPath)!,
                out ScannerPluginManifest? manifest,
                out string manifestPath) ||
            manifest != plugin.Manifest ||
            !TryResolveExecutable(
                Path.GetDirectoryName(plugin.ManifestPath)!,
                manifest.Executable,
                out string executablePath) ||
            !PathsEqual(executablePath, plugin.ExecutablePath) ||
            !TryHashFile(manifestPath, out string manifestHash) ||
            !TryHashFile(executablePath, out string executableHash))
        {
            return false;
        }

        ScannerPluginTrustIdentity current = new(
            manifest.Id,
            manifest.PluginVersion,
            manifestHash,
            executableHash);
        return current == approvedIdentity;
    }

    private static bool TryReadManifest(
        string pluginDirectory,
        out ScannerPluginManifest? manifest,
        out string manifestPath)
    {
        manifest = null;
        manifestPath = Path.Combine(pluginDirectory, "manifest.json");
        try
        {
            FileInfo file = new(manifestPath);
            if (IsReparsePoint(pluginDirectory) || !file.Exists ||
                file.Length is <= 0 or > MaximumManifestBytes ||
                IsReparsePoint(manifestPath))
            {
                return false;
            }

            using FileStream stream = new(manifestPath, FileMode.Open, FileAccess.Read, FileShare.Read);
            manifest = JsonSerializer.Deserialize<ScannerPluginManifest>(stream, ManifestJson);
            return manifest?.IsSupported == true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool TryResolveExecutable(
        string pluginDirectory,
        string executable,
        out string executablePath)
    {
        executablePath = string.Empty;
        if (Path.IsPathRooted(executable) || executable.IndexOf('\0') >= 0)
        {
            return false;
        }

        try
        {
            string root = Path.GetFullPath(pluginDirectory);
            string candidate = Path.GetFullPath(Path.Combine(root, executable));
            string relative = Path.GetRelativePath(root, candidate);
            if (relative.Length == 0 || Path.IsPathRooted(relative) ||
                relative.Equals("..", StringComparison.Ordinal) ||
                relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal) ||
                IsReparsePoint(candidate) || !File.Exists(candidate))
            {
                return false;
            }

            string current = root;
            foreach (string component in relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
            {
                current = Path.Combine(current, component);
                if (IsReparsePoint(current))
                {
                    return false;
                }
            }

            executablePath = candidate;
            return true;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static bool TryHashFile(string path, out string hash)
    {
        hash = string.Empty;
        try
        {
            if (IsReparsePoint(path))
            {
                return false;
            }

            using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            hash = Convert.ToHexString(SHA256.HashData(stream));
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static bool IsReparsePoint(string path)
    {
        try
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
        }
        catch (IOException)
        {
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return true;
        }
    }

    private static bool PathsEqual(string first, string second) =>
        string.Equals(
            Path.GetFullPath(first),
            Path.GetFullPath(second),
            StringComparison.OrdinalIgnoreCase);
}
