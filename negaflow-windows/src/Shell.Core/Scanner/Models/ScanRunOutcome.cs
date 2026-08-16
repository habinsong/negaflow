namespace Negaflow.Shell;

public sealed record ScanRunOutcome(
    int Requested,
    int Published,
    ScannerPluginLibraryScanStatus? LastStatus,
    ScannerPluginScanStatus? LastScanStatus)
{
    public bool IsSuccess => Published == Requested && Requested > 0;
}
