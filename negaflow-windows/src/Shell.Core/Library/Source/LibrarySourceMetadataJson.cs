using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

internal static class LibrarySourceMetadataJson
{
    internal static JsonObject Write(LibrarySourceMetadata metadata) => new()
    {
        [LibraryFrameReader.SourceFileBytesName] = metadata.FileBytes,
        [LibraryFrameReader.SourcePixelWidthName] = metadata.PixelWidth,
        [LibraryFrameReader.SourcePixelHeightName] = metadata.PixelHeight,
        [LibraryFrameReader.SourceSamplesPerPixelName] = metadata.SamplesPerPixel,
        [LibraryFrameReader.SourceBitsPerSampleName] = metadata.BitsPerSample,
        [LibraryFrameReader.SourceSampleFormatName] = metadata.SampleFormat,
        [LibraryFrameReader.SourceOrientationName] = metadata.Orientation,
    };
}
