using System.Security.Cryptography;
using Negaflow.Catalog;

namespace Negaflow.Shell;

internal static class DefectSourceIdentityReader
{
    internal static bool TryRead(string path, out DefectSourceIdentity identity)
    {
        identity = default;
        try
        {
            using FileStream stream = new(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 128 * 1024,
                FileOptions.SequentialScan);
            if (stream.Length <= 0)
            {
                return false;
            }

            byte[] hash = SHA256.HashData(stream);
            identity = new DefectSourceIdentity(
                checked((ulong)stream.Length),
                Convert.ToHexString(hash).ToLowerInvariant());
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException or OverflowException)
        {
            return false;
        }
    }
}
