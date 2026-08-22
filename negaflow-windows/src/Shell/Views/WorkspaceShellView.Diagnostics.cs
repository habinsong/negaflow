using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 진단 보고서에 담을 값을 모읍니다. macOS <c>AppModel.runDiagnostics()</c> 가 모델에서 바로
/// 읽던 자리이며, Windows 는 그 값들이 셸 화면에 흩어져 있어 여기서 한 번에 집습니다.
/// </summary>
public sealed partial class WorkspaceShellView
{
    /// <summary>
    /// UI 스레드에서만 읽을 수 있는 것만 집습니다. 디스크를 읽는 부분은
    /// <see cref="DiagnosticsCollector"/> 가 워커에서 합니다.
    /// </summary>
    public DiagnosticsInputs CollectDiagnostics(LibraryHostService? host)
    {
        Library.Scanner.LibraryScanPanel? scan = LibraryWorkspace.ScanPanelForDiagnostics;
        bool simulator = scan?.SimulatorEnabledForDiagnostics ?? false;
        return new DiagnosticsInputs
        {
            // macOS `frames.lazy.filter { !$0.isPreviewScan }.count` - 프리뷰는
            // 프레임 찾기용 임시 그림이라 장수에 넣지 않습니다.
            FrameCount = host?.Frames.Count(frame => !frame.IsPreviewScan) ?? 0,
            HasUnsavedChanges = host?.HasUnsavedChanges ?? false,
            Lifecycle = host?.State.ToString() ?? "notOpened",
            SaveErrorGeneration = host?.StoreError is { } storeError and not
                Negaflow.Catalog.CatalogStoreError.None
                ? storeError.ToString()
                : null,
            ScannerName = scan?.SelectedDeviceNameForDiagnostics ?? string.Empty,
            // macOS backend.backendType.rawValue - 시뮬레이터인지 플러그인인지.
            BackendName = simulator ? "simulator" : "plugin",
            Capabilities = workspaceState?.ScannerCapabilities,
            Plugins = scan?.PluginsForDiagnostics ?? [],
            Words = new DiagnosticsWords(
                AppResources.Get("diagnosticsValueYes", "Value"),
                AppResources.Get("diagnosticsValueNo", "Value"),
                AppResources.Get("diagnosticsStatFrames", "Text"),
                AppResources.Get("diagnosticsStatUnsaved", "Text"),
                AppResources.Get("diagnosticsStatLifecycle", "Text"),
                AppResources.Get("diagnosticsStatSaveError", "Text"),
                AppResources.Get("scannerLabel", "Text"),
                AppResources.Get("diagnosticsScannerBackend", "Text"),
                AppResources.Get("diagnosticsScannerPlugins", "Text"),
                AppResources.Get("noInstalledPlugins", "Text"),
                AppResources.Get("resolution", "Text"),
                AppResources.Get("colorMode", "Text"),
                AppResources.Get("bitDepth", "Text"),
                AppResources.Get("infrared", "Text"),
                AppResources.Get("capabilityUnavailable", "Value")),
        };
    }
}
