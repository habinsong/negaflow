using System.Reflection;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

internal static class NativeLibraryLoader
{
    private static readonly object Gate = new();
    private static nint libraryHandle;
    private static string? loadedPath;

    internal static void EnsureLoaded(string nativeLibraryPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(nativeLibraryPath);

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Negaflow.Native is supported only on Windows.");
        }

        if (!Path.IsPathFullyQualified(nativeLibraryPath))
        {
            throw new ArgumentException(
                "The native library path must be absolute.",
                nameof(nativeLibraryPath));
        }

        string fullPath = Path.GetFullPath(nativeLibraryPath);
        if (!string.Equals(
                Path.GetFileName(fullPath),
                NativeMethods.FileName,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException(
                $"The native library file name must be {NativeMethods.FileName}.",
                nameof(nativeLibraryPath));
        }

        lock (Gate)
        {
            if (loadedPath is not null)
            {
                if (!string.Equals(loadedPath, fullPath, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException(
                        "Negaflow.Interop has already loaded a different native library.");
                }

                return;
            }

            if (!File.Exists(fullPath))
            {
                throw new FileNotFoundException("The native library was not found.", fullPath);
            }

            nint candidateHandle = NativeLibrary.Load(fullPath);
            libraryHandle = candidateHandle;
            try
            {
                NativeLibrary.SetDllImportResolver(
                    typeof(NativeMethods).Assembly,
                    ResolveLibrary);
                loadedPath = fullPath;
            }
            catch
            {
                libraryHandle = nint.Zero;
                NativeLibrary.Free(candidateHandle);
                throw;
            }
        }
    }

    private static nint ResolveLibrary(
        string libraryName,
        Assembly assembly,
        DllImportSearchPath? searchPath)
    {
        _ = assembly;
        _ = searchPath;

        return string.Equals(libraryName, NativeMethods.LibraryName, StringComparison.Ordinal)
            ? libraryHandle
            : nint.Zero;
    }
}
