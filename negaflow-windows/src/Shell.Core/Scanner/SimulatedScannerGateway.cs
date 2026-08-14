using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 하드웨어가 없거나 스캐너가 점유 중일 때도 스캔 흐름 전체를 돌려 보는 가상 백엔드입니다.
/// macOS <c>MockScannerBackend</c> 와 같은 자리이며 장치 이름·capability 도 같습니다.
/// </summary>
/// <remarks>
/// 실제 플러그인 경계와 **같은 게시 경로**를 씁니다 — staging 에 TIFF 를 쓰고
/// <see cref="ScannerArtifactTransaction"/> 으로 커밋한 뒤 라이브러리가 카탈로그에 올립니다.
/// 시뮬레이터만 다른 길로 게시하면 그 길이 검증되지 않은 채 남습니다.
///
/// 승인 절차는 없습니다. 플러그인 승인은 우리가 고르지 않은 제3자 바이트를 실행하기 전에 묻는
/// 것이고, 시뮬레이터는 이 앱의 코드입니다.
/// </remarks>
public sealed class SimulatedScannerGateway : IScannerPluginGateway
{
    private readonly Func<string, LibrarySourceMetadata?>? metadataReader;

    /// <param name="metadataReader">
    /// null 이면 실제 스캔과 같은 네이티브 TIFF probe 를 씁니다. 네이티브를 띄우지 않는
    /// 관리 코드 시험만 이것을 갈아 끼웁니다.
    /// </param>
    public SimulatedScannerGateway(Func<string, LibrarySourceMetadata?>? metadataReader = null) =>
        this.metadataReader = metadataReader;

    public const string FilmScannerId = "simulated-plustek-8200i";
    public const string FlatbedScannerId = "simulated-negaflow-flatbed";
    public const string PluginId = "negaflow.simulator";

    private static readonly ScannerPluginTrustIdentity Identity = new(
        PluginId,
        "1.0.0",
        new string('0', 64),
        new string('0', 64));

    /// <summary>발견된 것처럼 보이는 하나의 항목입니다. 디스크에는 아무 것도 없습니다.</summary>
    public static InstalledScannerPlugin Plugin { get; } = new(
        new ScannerPluginManifest(
            ScannerPluginManifest.SupportedSchemaVersion,
            ScannerPluginManifest.StreamProtocolVersion,
            PluginId,
            "negaflow Scanner Simulator",
            "simulator",
            "scanner",
            null,
            null,
            "1.0.0"),
        string.Empty,
        string.Empty,
        Identity);

    public static IReadOnlyList<ScannerPluginDevice> Devices { get; } =
    [
        new ScannerPluginDevice(
            FilmScannerId,
            "negaflow Scanner",
            "negaflow",
            "OpticFilm 8200i",
            "internal",
            null,
            null,
            null,
            "verified",
            "simulator"),
        new ScannerPluginDevice(
            FlatbedScannerId,
            "negaflow Flatbed Scanner",
            "negaflow",
            "Flatbed Scanner Simulator",
            "internal",
            null,
            null,
            null,
            "verified",
            "simulator"),
    ];

    public IReadOnlyList<InstalledScannerPlugin> Discover() => [Plugin];

    public Task<ScannerPluginDetectResult> DetectAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        CancellationToken cancellationToken) =>
        Task.FromResult(new ScannerPluginDetectResult(Succeeded(), Devices, false));

    public Task<ScannerPluginCapabilitiesResult> GetCapabilitiesAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginDevice device,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(device);
        // macOS 의 mock 과 같은 값입니다. 평판은 7200 을 내지 않습니다.
        bool flatbed = string.Equals(device.Id, FlatbedScannerId, StringComparison.Ordinal);
        return Task.FromResult(new ScannerPluginCapabilitiesResult(
            Succeeded(),
            new ScannerPluginCapabilities(
                flatbed ? [900, 1800, 3600] : [900, 1800, 3600, 7200],
                ["color", "gray"],
                [8, 16],
                SupportsPreview: true,
                SupportsTransparency: true,
                SupportsInfrared: false,
                SupportsMultiExposure: false,
                SupportsScanArea: true,
                SupportsPositionedScanArea: flatbed,
                ["tiff"],
                "simulator",
                // macOS mock 과 같은 크기입니다. 필름 스캐너는 35mm 한 컷, 평판은 A4 입니다.
                flatbed ? 210.0 : 36.0,
                flatbed ? 297.0 : 24.0),
            false));
    }

    /// <summary>
    /// 합성 네거티브를 만들어 실제 스캔과 같은 경로로 게시합니다.
    /// </summary>
    public Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(library);
        cancellationToken.ThrowIfCancellationRequested();

        if (Stage(request) is not { } commit)
        {
            return Task.FromResult(Failed(ScannerPluginScanStatus.StagingCreateFailed));
        }
        if (!commit.IsSuccess)
        {
            return Task.FromResult(new ScannerPluginLibraryScanResult(
                ScannerPluginLibraryScanStatus.ScanFailed,
                new ScannerPluginScanResult(
                    ScannerPluginScanStatus.ArtifactCommitFailed,
                    Succeeded(),
                    ScannerPluginStreamStatus.Accepted,
                    commit),
                null));
        }

        ScannerFramePublishResult published = library.PublishScannerFrame(
            new ScannerFrameImport(
                commit.Artifacts!.VisiblePath,
                commit.Artifacts.InfraredPath,
                request.Process),
            null,
            null);
        return Task.FromResult(new ScannerPluginLibraryScanResult(
            published.Status == ScannerFramePublishStatus.CatalogWriteFailed
                ? ScannerPluginLibraryScanStatus.CatalogPublicationFailed
                : ScannerPluginLibraryScanStatus.Published,
            new ScannerPluginScanResult(
                ScannerPluginScanStatus.Completed,
                Succeeded(),
                ScannerPluginStreamStatus.Accepted,
                commit),
            published));
    }

    /// <summary>
    /// 합성 네거티브를 staging 에 쓰고 실제 스캔과 같은 트랜잭션으로 커밋합니다. 프리뷰는
    /// 짧은 변 기준으로 작게 냅니다 — 실제 프리뷰도 본 스캔보다 훨씬 거칩니다.
    /// </summary>
    private ScannerArtifactCommitResult? Stage(ScannerPluginScanRequest request)
    {
        int longEdge = request.Preview ? 600 : Math.Clamp(request.ResolutionDpi / 2, 600, 5400);
        int width = longEdge;
        int height = Math.Max(1, (int)Math.Round(longEdge * 24.0 / 36.0));

        string destination = request.DestinationVisiblePath;
        if (Path.GetDirectoryName(destination) is not { } directory)
        {
            return null;
        }
        string staging = Path.Combine(directory, $".negaflow-simulated-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(staging);
            string stagedPath = Path.Combine(staging, Path.GetFileName(destination));
            SyntheticNegativeTiff.Write(
                stagedPath,
                width,
                height,
                request.BitDepth,
                string.Equals(request.ColorMode, "gray", StringComparison.Ordinal));
            return ScannerArtifactTransaction.Commit(
                new ScannerStagedArtifacts(staging, stagedPath, null),
                destination,
                metadataReader);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            PathTooLongException or NotSupportedException)
        {
            return null;
        }
        finally
        {
            try
            {
                if (Directory.Exists(staging))
                {
                    Directory.Delete(staging, true);
                }
            }
            catch (IOException)
            {
                // 뒤처리 실패는 게시 결과가 아닙니다.
            }
        }
    }

    public Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();
        if (Stage(request) is not { } staged)
        {
            return Task.FromResult(new ScannerPluginScanResult(
                ScannerPluginScanStatus.StagingCreateFailed,
                Succeeded(),
                null,
                null));
        }
        return Task.FromResult(new ScannerPluginScanResult(
            staged.IsSuccess
                ? ScannerPluginScanStatus.Completed
                : ScannerPluginScanStatus.ArtifactCommitFailed,
            Succeeded(),
            ScannerPluginStreamStatus.Accepted,
            staged));
    }

    private static ScannerPluginProcessResult Succeeded() =>
        new(ScannerPluginProcessStatus.Succeeded, 0, [], string.Empty);

    private static ScannerPluginLibraryScanResult Failed(ScannerPluginScanStatus status) =>
        new(
            ScannerPluginLibraryScanStatus.ScanFailed,
            new ScannerPluginScanResult(status, Succeeded(), null, null),
            null);
}
