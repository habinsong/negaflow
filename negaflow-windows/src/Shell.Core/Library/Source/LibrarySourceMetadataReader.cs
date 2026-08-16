using Negaflow.Interop;
using Negaflow.Catalog;

namespace Negaflow.Shell;

internal static class LibrarySourceMetadataReader
{
    internal static LibrarySourceMetadata? Read(string path)
    {
        bool read = ImageSourcePaths.UsesWicStandardDecoder(path)
            ? NativeStandardImageSourceProbe.TryRead(path, out TiffSourceMetadata metadata)
            : NativeTiffSourceProbe.TryRead(path, out metadata);
        return read
            ? new LibrarySourceMetadata(
                metadata.FileBytes,
                metadata.PixelWidth,
                metadata.PixelHeight,
                metadata.SamplesPerPixel,
                metadata.BitsPerSample,
                metadata.SampleFormat,
                metadata.Orientation)
            : null;
    }
}
