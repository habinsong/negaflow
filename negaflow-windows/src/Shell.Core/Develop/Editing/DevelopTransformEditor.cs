using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>Builds and persists rotation, flip, straighten, and crop recipes.</summary>
internal sealed class DevelopTransformEditor
{
    private readonly LibraryHostService host;

    public DevelopTransformEditor(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        this.host = host;
    }

    public DevelopEditResult Rotate(LibraryFrameSnapshot? frame, bool clockwise)
    {
        if (frame is null)
        {
            return Missing();
        }
        ImageRotation rotation = frame.ImageTransform.Rotation;
        ImageRotation updated = clockwise
            ? rotation switch
            {
                ImageRotation.Degrees0 => ImageRotation.Degrees90,
                ImageRotation.Degrees90 => ImageRotation.Degrees180,
                ImageRotation.Degrees180 => ImageRotation.Degrees270,
                _ => ImageRotation.Degrees0,
            }
            : rotation switch
            {
                ImageRotation.Degrees0 => ImageRotation.Degrees270,
                ImageRotation.Degrees90 => ImageRotation.Degrees0,
                ImageRotation.Degrees180 => ImageRotation.Degrees90,
                _ => ImageRotation.Degrees180,
            };
        return Set(frame, frame.ImageTransform with { Rotation = updated });
    }

    public DevelopEditResult FlipHorizontally(LibraryFrameSnapshot? frame) =>
        frame is null
            ? Missing()
            : Set(
                frame,
                frame.ImageTransform with
                {
                    FlipHorizontal = !frame.ImageTransform.FlipHorizontal,
                });

    public DevelopEditResult FlipVertically(LibraryFrameSnapshot? frame) =>
        frame is null
            ? Missing()
            : Set(
                frame,
                frame.ImageTransform with
                {
                    FlipVertical = !frame.ImageTransform.FlipVertical,
                });

    public DevelopEditResult SetStraightenAngle(LibraryFrameSnapshot? frame, double angle) =>
        frame is null
            ? Missing()
            : Set(
                frame,
                frame.ImageTransform with
                {
                    StraightenAngle = Math.Clamp(angle, -45.0, 45.0),
                });

    public DevelopEditResult SetCrop(LibraryFrameSnapshot? frame, ImageCropRect? crop) =>
        frame is null
            ? Missing()
            : Set(frame, frame.ImageTransform with { Crop = crop });

    public DevelopEditResult SetCropAspect(
        LibraryFrameSnapshot? frame,
        CropAspectOption option) =>
        frame is null
            ? Missing()
            : Set(
                frame,
                CropAspect.Apply(
                    frame.ImageTransform,
                    option,
                    frame.SourceMetadata?.PixelWidth ?? 0U,
                    frame.SourceMetadata?.PixelHeight ?? 0U));

    private DevelopEditResult Set(
        LibraryFrameSnapshot frame,
        ImageTransformRecipe imageTransform)
    {
        ArgumentNullException.ThrowIfNull(imageTransform);
        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                ImageTransform: imageTransform));
        return new(error, error == LibraryFrameError.None);
    }

    private static DevelopEditResult Missing() =>
        new(LibraryFrameError.MissingId, false);
}
