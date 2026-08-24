using System.Text.Json;
using Negaflow.Catalog;

namespace Negaflow.Shell;

public sealed record ScannerPublicationReceipt(
    Guid Id,
    string VisiblePath,
    string? InfraredPath,
    DevelopmentProcess Process,
    ImageRotation Rotation = ImageRotation.Degrees0,
    ImageTransformRecipe? InitialTransform = null);

// The scan files are already committed outside the catalog. This tiny journal makes the final
// catalog append restartable without making the adapter responsible for catalog durability.
public static class ScannerPublicationReceiptStore
{
    private const string DirectoryName = "scanner-publications";
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
    };

    public static bool TrySchedule(
        StorageRootSet roots,
        ScannerFrameImport scan,
        out string receiptPath)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(scan);
        receiptPath = string.Empty;
        if (!IsValidScan(scan) || !TryPrepareRoot(roots, out string root))
        {
            return false;
        }

        ScannerPublicationReceipt receipt = new(
            Guid.NewGuid(),
            scan.VisiblePath,
            scan.InfraredPath,
            scan.Process,
            scan.Rotation,
            scan.InitialTransform);
        receiptPath = Path.Combine(root, $"{receipt.Id:N}.json");
        string temporary = Path.Combine(root, $".{receipt.Id:N}.tmp");
        try
        {
            using (System.IO.FileStream stream = new(
                temporary,
                System.IO.FileMode.CreateNew,
                System.IO.FileAccess.Write,
                System.IO.FileShare.None,
                4096,
                System.IO.FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(stream, receipt, Json);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, receiptPath);
            return true;
        }
        catch (IOException)
        {
            TryDeleteTemporary(temporary);
            receiptPath = string.Empty;
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            TryDeleteTemporary(temporary);
            receiptPath = string.Empty;
            return false;
        }
    }

    public static IReadOnlyList<(string Path, ScannerPublicationReceipt Receipt)> ReadPending(
        StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        if (!TryPrepareRoot(roots, out string root))
        {
            return [];
        }

        List<(string, ScannerPublicationReceipt)> result = [];
        try
        {
            foreach (string path in Directory.EnumerateFiles(root, "*.json", SearchOption.TopDirectoryOnly))
            {
                if (IsReparsePoint(path))
                {
                    continue;
                }
                ScannerPublicationReceipt? receipt;
                using (System.IO.FileStream stream = new(
                    path,
                    System.IO.FileMode.Open,
                    System.IO.FileAccess.Read,
                    System.IO.FileShare.Read))
                {
                    receipt = JsonSerializer.Deserialize<ScannerPublicationReceipt>(stream, Json);
                }
                if (receipt is not null && IsValidScan(ToScan(receipt)))
                {
                    result.Add((path, receipt));
                }
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
        catch (JsonException)
        {
        }
        return result;
    }

    public static void Complete(string receiptPath)
    {
        if (string.IsNullOrWhiteSpace(receiptPath) || !Path.IsPathFullyQualified(receiptPath) ||
            IsReparsePoint(receiptPath))
        {
            return;
        }
        try
        {
            File.Delete(receiptPath);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static bool TryPrepareRoot(StorageRootSet roots, out string root)
    {
        root = string.Empty;
        try
        {
            if (!Path.IsPathFullyQualified(roots.JournalRoot) || IsReparsePoint(roots.JournalRoot))
            {
                return false;
            }
            Directory.CreateDirectory(roots.JournalRoot);
            root = Path.Combine(roots.JournalRoot, DirectoryName);
            if (File.Exists(root) || IsReparsePoint(root))
            {
                return false;
            }
            Directory.CreateDirectory(root);
            return !IsReparsePoint(root);
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

    private static bool IsValidScan(ScannerFrameImport scan) =>
        Path.IsPathFullyQualified(scan.VisiblePath) &&
        (scan.InfraredPath is null || Path.IsPathFullyQualified(scan.InfraredPath)) &&
        Enum.IsDefined(scan.Rotation) &&
        (scan.InitialTransform is null || scan.InitialTransform.IsValid);

    internal static ScannerFrameImport ToScan(ScannerPublicationReceipt receipt) =>
        new(receipt.VisiblePath, receipt.InfraredPath, receipt.Process)
        {
            Rotation = receipt.Rotation,
            InitialTransform = receipt.InitialTransform,
        };

    private static bool IsReparsePoint(string path)
    {
        try
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
        }
        catch (FileNotFoundException)
        {
            return false;
        }
        catch (DirectoryNotFoundException)
        {
            return false;
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

    private static void TryDeleteTemporary(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
