using System.Text.Json;

namespace Negaflow.Shell;

public enum ScannerPluginApprovalState
{
    /// <summary>승인된 적이 없습니다.</summary>
    Unapproved,

    /// <summary>승인은 있으나 매니페스트나 실행 파일의 바이트가 그때와 다릅니다.</summary>
    Changed,

    Approved,
}

/// <summary>
/// 사용자가 승인한 스캐너 플러그인의 신원입니다. 플러그인은 별도 프로세스에서 도는 GPL 코드이고
/// 우리는 그 바이트를 고르지 않으므로, 승인은 <b>그때 본 그 바이트</b>에만 붙습니다. 매니페스트나
/// 실행 파일이 바뀌면 승인이 자동으로 풀립니다 — 조용히 다른 실행 파일을 돌리지 않기 위해서입니다.
/// </summary>
public sealed class ScannerPluginTrustStore
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    private readonly string storePath;
    private readonly Dictionary<string, ScannerPluginTrustIdentity> approved;

    public ScannerPluginTrustStore(string? storePath = null)
    {
        this.storePath = storePath ?? DefaultStorePath();
        approved = Load(this.storePath);
    }

    public static string DefaultStorePath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Negaflow",
        "scanner-plugin-trust.json");

    public string? LastWriteError { get; private set; }

    public ScannerPluginApprovalState StateFor(InstalledScannerPlugin plugin)
    {
        ArgumentNullException.ThrowIfNull(plugin);
        if (!approved.TryGetValue(plugin.Manifest.Id, out ScannerPluginTrustIdentity? identity))
        {
            return ScannerPluginApprovalState.Unapproved;
        }
        // 저장된 해시가 지금 디스크의 바이트와 같아야 승인입니다. 파일이 사라졌거나 바뀌었으면
        // 승인은 무효이며, 사용자가 다시 봐야 합니다.
        return identity == plugin.TrustIdentity &&
            ScannerPluginDiscovery.HasCurrentTrustIdentity(plugin, identity)
            ? ScannerPluginApprovalState.Approved
            : ScannerPluginApprovalState.Changed;
    }

    public ScannerPluginTrustIdentity? ApprovedIdentityFor(InstalledScannerPlugin plugin) =>
        StateFor(plugin) == ScannerPluginApprovalState.Approved
            ? approved[plugin.Manifest.Id]
            : null;

    public IReadOnlyList<InstalledScannerPlugin> ApprovedPlugins(
        IReadOnlyList<InstalledScannerPlugin> plugins)
    {
        ArgumentNullException.ThrowIfNull(plugins);
        return [.. plugins.Where(plugin =>
            StateFor(plugin) == ScannerPluginApprovalState.Approved)];
    }

    public IReadOnlyList<InstalledScannerPlugin> PluginsRequiringApproval(
        IReadOnlyList<InstalledScannerPlugin> plugins)
    {
        ArgumentNullException.ThrowIfNull(plugins);
        return [.. plugins.Where(plugin =>
            StateFor(plugin) != ScannerPluginApprovalState.Approved)];
    }

    public void Approve(InstalledScannerPlugin plugin)
    {
        ArgumentNullException.ThrowIfNull(plugin);
        approved[plugin.Manifest.Id] = plugin.TrustIdentity;
        Save();
    }

    public void Revoke(string pluginId)
    {
        ArgumentException.ThrowIfNullOrEmpty(pluginId);
        if (approved.Remove(pluginId))
        {
            Save();
        }
    }

    private static Dictionary<string, ScannerPluginTrustIdentity> Load(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return new Dictionary<string, ScannerPluginTrustIdentity>(StringComparer.Ordinal);
            }
            Dictionary<string, ScannerPluginTrustIdentity>? read =
                JsonSerializer.Deserialize<Dictionary<string, ScannerPluginTrustIdentity>>(
                    File.ReadAllText(path),
                    Json);
            return read is null
                ? new Dictionary<string, ScannerPluginTrustIdentity>(StringComparer.Ordinal)
                : new Dictionary<string, ScannerPluginTrustIdentity>(read, StringComparer.Ordinal);
        }
        catch (Exception error) when (error is JsonException or IOException or
            UnauthorizedAccessException)
        {
            // 읽지 못한 승인 목록은 빈 목록입니다. 승인을 지어내는 것보다 다시 묻는 것이 낫습니다.
            return new Dictionary<string, ScannerPluginTrustIdentity>(StringComparer.Ordinal);
        }
    }

    private void Save()
    {
        string temporaryPath = storePath + ".tmp";
        try
        {
            string? directory = Path.GetDirectoryName(storePath);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(approved, Json));
            File.Move(temporaryPath, storePath, true);
            LastWriteError = null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            LastWriteError = error.Message;
        }
    }
}
