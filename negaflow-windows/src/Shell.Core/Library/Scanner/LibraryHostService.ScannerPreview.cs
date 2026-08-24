namespace Negaflow.Shell;

public sealed partial class LibraryHostService
{
    public ScannerFramePublishResult PublishScannerPreviewFrame(ScannerFrameImport scan) =>
        scannerPublisher.PublishPreview(document, scan);

    public int RemoveScannerPreviewFrames(string? keepingFrameId = null) =>
        document?.RemoveTransientPreviewFrames(keepingFrameId) ?? 0;
}
