using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;
using Negaflow.Catalog;

namespace Negaflow.Shell.Library;

internal readonly record struct DevelopedFileObservation(
    uint VolumeSerialNumber,
    ulong FileIndex,
    ulong FileBytes,
    ulong LastWriteTicks);

public sealed class DevelopedPreviewCacheIdentity
{
    internal DevelopedPreviewCacheIdentity(
        byte[] recipeBytes,
        DevelopedFileObservation source,
        DevelopedFileObservation nativeEngine,
        Guid shellModuleVersion)
    {
        RecipeBytes = recipeBytes;
        Source = source;
        NativeEngine = nativeEngine;
        ShellModuleVersion = shellModuleVersion;
    }

    internal byte[] RecipeBytes { get; }

    internal DevelopedFileObservation Source { get; }

    internal DevelopedFileObservation NativeEngine { get; }

    internal Guid ShellModuleVersion { get; }

    internal bool Matches(DevelopedPreviewCacheIdentity other) =>
        Source == other.Source &&
        NativeEngine == other.NativeEngine &&
        ShellModuleVersion == other.ShellModuleVersion &&
        RecipeBytes.AsSpan().SequenceEqual(other.RecipeBytes);
}

/// <summary>
/// persistent developed cache의 값싼 local identity입니다. 전체 파일 content hash는 계산하지 않습니다.
/// </summary>
internal static class DevelopedPreviewCacheIdentityFactory
{
    private const uint FileAttributeDirectory = 0x10U;

    internal static bool TryCreate(
        LibraryFrameSnapshot frame,
        out DevelopedPreviewCacheIdentity identity)
    {
        ArgumentNullException.ThrowIfNull(frame);
        identity = null!;
        string destination = Path.ChangeExtension(frame.SourcePath, ".preview-cache.png");
        if (DevelopRequestFactory.Create(frame, destination).Request is not { } request ||
            !TryObserve(frame.SourcePath, out DevelopedFileObservation source) ||
            !TryObserve(
                Path.Combine(AppContext.BaseDirectory, "Negaflow.Native.dll"),
                out DevelopedFileObservation nativeEngine))
        {
            return false;
        }

        try
        {
            identity = new DevelopedPreviewCacheIdentity(
                DevelopedPreviewCacheRecipeCodec.Compose(request, frame.DefectRecipe),
                source,
                nativeEngine,
                typeof(DevelopedPreviewCacheIdentityFactory)
                    .Assembly.ManifestModule.ModuleVersionId);
            return true;
        }
        catch (Exception error) when (error is JsonException or NotSupportedException or
            ArgumentException or OverflowException)
        {
            return false;
        }
    }

    private static bool TryObserve(string path, out DevelopedFileObservation observation)
    {
        observation = default;
        try
        {
            using SafeFileHandle handle = File.OpenHandle(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                FileOptions.RandomAccess);
            if (!GetFileInformationByHandle(handle, out ByHandleFileInformation info) ||
                (info.FileAttributes & FileAttributeDirectory) != 0U)
            {
                return false;
            }

            observation = new DevelopedFileObservation(
                info.VolumeSerialNumber,
                Combine(info.FileIndexHigh, info.FileIndexLow),
                Combine(info.FileSizeHigh, info.FileSizeLow),
                Combine(info.LastWriteTimeHigh, info.LastWriteTimeLow));
            return observation.FileBytes > 0;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            return false;
        }
    }

    private static ulong Combine(uint high, uint low) =>
        ((ulong)high << 32) | low;

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle file,
        out ByHandleFileInformation information);

    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation
    {
        internal uint FileAttributes;
        internal uint CreationTimeLow;
        internal uint CreationTimeHigh;
        internal uint LastAccessTimeLow;
        internal uint LastAccessTimeHigh;
        internal uint LastWriteTimeLow;
        internal uint LastWriteTimeHigh;
        internal uint VolumeSerialNumber;
        internal uint FileSizeHigh;
        internal uint FileSizeLow;
        internal uint NumberOfLinks;
        internal uint FileIndexHigh;
        internal uint FileIndexLow;
    }
}
