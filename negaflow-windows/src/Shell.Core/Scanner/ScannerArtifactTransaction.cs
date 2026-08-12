using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public enum ScannerArtifactCommitStatus
{
    Committed,
    InvalidArgument,
    StagingViolation,
    ArtifactMissing,
    ArtifactInvalid,
    InfraredMismatch,
    DestinationExists,
    CommitFailed,
    RollbackFailed,
}

public sealed record ScannerStagedArtifacts(
    string StagingDirectory,
    string VisiblePath,
    string? InfraredPath);

public sealed record ScannerArtifactRequirements(
    int PixelWidth,
    int PixelHeight,
    int BitDepth,
    string ColorMode);

public sealed record ScannerCommittedArtifacts(
    string VisiblePath,
    string? InfraredPath,
    LibrarySourceMetadata VisibleMetadata,
    LibrarySourceMetadata? InfraredMetadata);

public sealed record ScannerArtifactCommitResult(
    ScannerArtifactCommitStatus Status,
    ScannerCommittedArtifacts? Artifacts)
{
    public bool IsSuccess => Status == ScannerArtifactCommitStatus.Committed && Artifacts is not null;
}

// A scanner adapter only writes host-owned staging files. Both TIFFs are validated before any
// final name appears, and the RGB file is moved last so the Library never observes an RGB frame
// claiming a missing infrared companion. The caller must create staging beside the final output;
// that gives File.Move same-volume atomic rename semantics without guessing a volume from text.
public static class ScannerArtifactTransaction
{
    public static ScannerArtifactCommitResult Commit(
        ScannerStagedArtifacts staged,
        string destinationVisiblePath,
        Func<string, LibrarySourceMetadata?>? metadataReader = null,
        ScannerArtifactRequirements? requirements = null)
    {
        ArgumentNullException.ThrowIfNull(staged);
        if (!AreValidRequirements(requirements))
        {
            return new(ScannerArtifactCommitStatus.InvalidArgument, null);
        }
        Func<string, LibrarySourceMetadata?> readMetadata = metadataReader ?? ReadTiffMetadata;
        if (!TryNormalizeDirectory(staged.StagingDirectory, out string stagingDirectory) ||
            !TryNormalizeFile(staged.VisiblePath, out string stagedVisible) ||
            !TryNormalizeFile(destinationVisiblePath, out string destinationVisible) ||
            !IsContainedFile(stagingDirectory, stagedVisible) ||
            !AreSiblingDirectories(stagingDirectory, destinationVisible))
        {
            return new(ScannerArtifactCommitStatus.InvalidArgument, null);
        }

        string? stagedInfrared = null;
        string companionDestination = destinationVisible + ".ir.tiff";
        string? destinationInfrared = null;
        if (staged.InfraredPath is { } infraredPath)
        {
            if (!TryNormalizeFile(infraredPath, out stagedInfrared) ||
                !IsContainedFile(stagingDirectory, stagedInfrared))
            {
                return new(ScannerArtifactCommitStatus.InvalidArgument, null);
            }
            destinationInfrared = companionDestination;
        }

        if (!IsSafeDirectory(stagingDirectory) ||
            !IsSafeContainedFile(stagingDirectory, stagedVisible) ||
            (stagedInfrared is not null && !IsSafeContainedFile(stagingDirectory, stagedInfrared)))
        {
            return new(ScannerArtifactCommitStatus.StagingViolation, null);
        }
        if (!File.Exists(stagedVisible) || (stagedInfrared is not null && !File.Exists(stagedInfrared)))
        {
            return new(ScannerArtifactCommitStatus.ArtifactMissing, null);
        }
        if (File.Exists(destinationVisible) || File.Exists(companionDestination))
        {
            return new(ScannerArtifactCommitStatus.DestinationExists, null);
        }

        LibrarySourceMetadata? visibleMetadata = readMetadata(stagedVisible);
        LibrarySourceMetadata? infraredMetadata = stagedInfrared is null ? null : readMetadata(stagedInfrared);
        if (visibleMetadata is not { IsValid: true } ||
            stagedInfrared is not null && infraredMetadata is not { IsValid: true })
        {
            return new(ScannerArtifactCommitStatus.ArtifactInvalid, null);
        }
        if (!MatchesVisibleRequirements(visibleMetadata.Value, requirements))
        {
            return new(ScannerArtifactCommitStatus.ArtifactInvalid, null);
        }
        if (infraredMetadata is { } infrared &&
            (infrared.PixelWidth != visibleMetadata.Value.PixelWidth ||
             infrared.PixelHeight != visibleMetadata.Value.PixelHeight ||
             infrared.Orientation != visibleMetadata.Value.Orientation ||
             infrared.SamplesPerPixel is not (1 or 3) ||
             infrared.BitsPerSample is not (8 or 16) ||
             infrared.SampleFormat != 1))
        {
            return new(ScannerArtifactCommitStatus.InfraredMismatch, null);
        }

        bool infraredMoved = false;
        try
        {
            if (stagedInfrared is not null)
            {
                File.Move(stagedInfrared, destinationInfrared!);
                infraredMoved = true;
            }
            File.Move(stagedVisible, destinationVisible);
        }
        catch (IOException)
        {
            return RollBackInfrared(infraredMoved, destinationInfrared, stagedInfrared);
        }
        catch (UnauthorizedAccessException)
        {
            return RollBackInfrared(infraredMoved, destinationInfrared, stagedInfrared);
        }

        return new(
            ScannerArtifactCommitStatus.Committed,
            new ScannerCommittedArtifacts(
                destinationVisible,
                destinationInfrared,
                visibleMetadata.Value,
                infraredMetadata));
    }

    private static bool TryNormalizeDirectory(string path, out string normalized)
    {
        normalized = string.Empty;
        try
        {
            if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
            {
                return false;
            }
            normalized = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
            return Directory.Exists(normalized);
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
        catch (PathTooLongException)
        {
            return false;
        }
    }

    private static bool TryNormalizeFile(string path, out string normalized)
    {
        normalized = string.Empty;
        try
        {
            if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
            {
                return false;
            }
            normalized = Path.GetFullPath(path);
            return Path.GetFileName(normalized).Length != 0;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
        catch (PathTooLongException)
        {
            return false;
        }
    }

    private static bool IsContainedFile(string directory, string file) =>
        Path.GetRelativePath(directory, file) is { } relative && relative.Length != 0 &&
        !Path.IsPathFullyQualified(relative) && !relative.Equals("..", StringComparison.Ordinal) &&
        !relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal);

    private static bool AreSiblingDirectories(string stagingDirectory, string destinationFile) =>
        string.Equals(
            Path.GetDirectoryName(stagingDirectory),
            Path.GetDirectoryName(destinationFile),
            StringComparison.OrdinalIgnoreCase);

    private static bool IsSafeDirectory(string directory) =>
        !IsReparsePoint(directory) && Directory.Exists(directory);

    private static bool IsSafeFile(string path) =>
        File.Exists(path) && !IsReparsePoint(path) &&
        (File.GetAttributes(path) & FileAttributes.Directory) == 0;

    private static bool IsSafeContainedFile(string directory, string file)
    {
        if (!IsSafeFile(file))
        {
            return false;
        }

        string? current = Path.GetDirectoryName(file);
        while (current is not null && !string.Equals(current, directory, StringComparison.OrdinalIgnoreCase))
        {
            if (!IsSafeDirectory(current))
            {
                return false;
            }
            current = Path.GetDirectoryName(current);
        }
        return current is not null;
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

    private static LibrarySourceMetadata? ReadTiffMetadata(string path) =>
        NativeTiffSourceProbe.TryRead(path, out TiffSourceMetadata metadata)
            ? new LibrarySourceMetadata(
                metadata.FileBytes,
                metadata.PixelWidth,
                metadata.PixelHeight,
                metadata.SamplesPerPixel,
                metadata.BitsPerSample,
                metadata.SampleFormat,
                metadata.Orientation)
            : null;

    private static bool AreValidRequirements(ScannerArtifactRequirements? requirements) =>
        requirements is null ||
        requirements.PixelWidth > 0 && requirements.PixelHeight > 0 &&
        requirements.BitDepth is 8 or 16 &&
        requirements.ColorMode is "color" or "gray" or "lineart" or "infrared";

    private static bool MatchesVisibleRequirements(
        LibrarySourceMetadata metadata,
        ScannerArtifactRequirements? requirements)
    {
        if (metadata.SampleFormat != 1)
        {
            return false;
        }
        if (requirements is null)
        {
            return metadata.SamplesPerPixel == 3 && metadata.BitsPerSample is 8 or 16;
        }
        int expectedSamples = requirements.ColorMode == "color" ? 3 : 1;
        return metadata.PixelWidth == requirements.PixelWidth &&
            metadata.PixelHeight == requirements.PixelHeight &&
            metadata.SamplesPerPixel == expectedSamples &&
            metadata.BitsPerSample == requirements.BitDepth;
    }

    private static ScannerArtifactCommitResult RollBackInfrared(
        bool infraredMoved,
        string? destinationInfrared,
        string? stagedInfrared)
    {
        if (!infraredMoved)
        {
            return new(ScannerArtifactCommitStatus.CommitFailed, null);
        }

        try
        {
            File.Move(destinationInfrared!, stagedInfrared!);
            return new(ScannerArtifactCommitStatus.CommitFailed, null);
        }
        catch (IOException)
        {
            return new(ScannerArtifactCommitStatus.RollbackFailed, null);
        }
        catch (UnauthorizedAccessException)
        {
            return new(ScannerArtifactCommitStatus.RollbackFailed, null);
        }
    }
}
