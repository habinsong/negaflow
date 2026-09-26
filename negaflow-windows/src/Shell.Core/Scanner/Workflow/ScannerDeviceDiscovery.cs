namespace Negaflow.Shell;

/// <summary>
/// 승인된 플러그인에 장치와 capability 를 묻는 차례입니다. 세션 상태를 들지 않습니다 —
/// 무엇을 찾았는지와 첫 실패 이름만 돌려주고, 선택 유지와 옵션 보정은 세션이 합니다.
/// </summary>
internal static class ScannerDeviceDiscovery
{
    /// <summary>
    /// 승인된 플러그인 전부에 장치를 묻습니다. 한 플러그인이 실패해도 다음 플러그인은 묻습니다.
    /// </summary>
    /// <returns>찾은 장치와, 실패가 있었으면 첫 실패의 이름입니다.</returns>
    internal static async Task<(IReadOnlyList<ScannerPluginDevice> Devices, string? FailureName)>
        DetectAsync(
            IScannerPluginGateway gateway,
            IReadOnlyList<InstalledScannerPlugin> plugins,
            Func<InstalledScannerPlugin, ScannerPluginTrustIdentity?> approvedIdentityFor,
            CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(gateway);
        ArgumentNullException.ThrowIfNull(plugins);
        ArgumentNullException.ThrowIfNull(approvedIdentityFor);
        var found = new List<ScannerPluginDevice>();
        string? failureName = null;
        foreach (InstalledScannerPlugin plugin in plugins)
        {
            if (approvedIdentityFor(plugin) is not { } identity)
            {
                ScannerDiagnosticsLog.Write(
                    $"detect skip {plugin.Manifest.Id} - not approved");
                continue;
            }
            ScannerPluginDetectResult result =
                await gateway.DetectAsync(plugin, identity, cancellationToken)
                    .ConfigureAwait(false);
            if (result.IsSuccess)
            {
                found.AddRange(result.Devices);
                ScannerDiagnosticsLog.Write(
                    $"detect ok {plugin.Manifest.Id} devices={result.Devices.Count}");
                continue;
            }
            failureName ??= result.IsMalformedResponse
                ? "malformed_detect_response"
                : result.Process.Status.ToString();
            ScannerDiagnosticsLog.Write(
                $"detect failed {plugin.Manifest.Id} - {failureName} " +
                $"(malformed={result.IsMalformedResponse} " +
                $"process={result.Process.Status} exit={result.Process.ExitCode?.ToString() ?? "none"})");
            // **무엇을 하면 되는지 여기에 적습니다.** 화면에는 오류를 내지 않으므로
            // (사용자가 그 글자로 할 수 있는 일이 없습니다) 진단에서 읽습니다.
            if (result.Process.Status == ScannerPluginProcessStatus.TimedOut)
            {
                ScannerDiagnosticsLog.Write(
                    "detect hint: the plugin did not answer in time. Another scan or " +
                    "detect usually still holds the device - close other scanning apps, " +
                    "then power-cycle the scanner if it stays quiet.");
            }
        }
        return (found, failureName);
    }

    /// <summary>
    /// 장치의 capability 를 승인된 플러그인 차례로 묻고 처음 답한 것을 씁니다. 아무도 답하지
    /// 않으면 <see langword="null"/> 입니다.
    /// </summary>
    internal static async Task<ScannerPluginCapabilities?> CapabilitiesAsync(
        IScannerPluginGateway gateway,
        IReadOnlyList<InstalledScannerPlugin> plugins,
        Func<InstalledScannerPlugin, ScannerPluginTrustIdentity?> approvedIdentityFor,
        ScannerPluginDevice device,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(gateway);
        ArgumentNullException.ThrowIfNull(plugins);
        ArgumentNullException.ThrowIfNull(approvedIdentityFor);
        foreach (InstalledScannerPlugin plugin in plugins)
        {
            if (approvedIdentityFor(plugin) is not { } identity)
            {
                continue;
            }
            ScannerPluginCapabilitiesResult result = await gateway
                .GetCapabilitiesAsync(plugin, identity, device, cancellationToken)
                .ConfigureAwait(false);
            if (result.IsSuccess)
            {
                return result.Capabilities;
            }
        }
        return null;
    }
}
