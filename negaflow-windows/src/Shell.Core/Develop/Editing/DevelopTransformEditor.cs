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

    public DevelopEditResult Rotate(LibraryFrameSnapshot? frame, bool clockwise) =>
        frame is null
            ? Missing()
            : Set(frame, ImageTransformGeometry.Rotate(frame.ImageTransform, clockwise));

    public DevelopEditResult FlipHorizontally(LibraryFrameSnapshot? frame) =>
        frame is null
            ? Missing()
            : Set(frame, ImageTransformGeometry.Flip(frame.ImageTransform, displayHorizontal: true));

    public DevelopEditResult FlipVertically(LibraryFrameSnapshot? frame) =>
        frame is null
            ? Missing()
            : Set(frame, ImageTransformGeometry.Flip(frame.ImageTransform, displayHorizontal: false));

    public DevelopEditResult SetStraightenAngle(LibraryFrameSnapshot? frame, double angle) =>
        frame is null
            ? Missing()
            : Set(
                frame,
                frame.ImageTransform with
                {
                    StraightenAngle = Math.Clamp(angle, -45.0, 45.0),
                });

    /// <summary>
    /// macOS <c>AppModel.resetPhotoAngle</c> — 회전과 수평 보정만 0 으로 돌리고 크롭·뒤집기는
    /// 그대로 둡니다(<c>AppModel+TransformControls.swift:42-47</c>).
    /// </summary>
    public DevelopEditResult ResetPhotoAngle(LibraryFrameSnapshot? frame) =>
        frame is null
            ? Missing()
            : Set(
                frame,
                frame.ImageTransform with
                {
                    Rotation = ImageRotation.Degrees0,
                    StraightenAngle = 0.0,
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
        if (Negaflow.Shell.PreviewTrace.IsEnabled)
        {
            string crop = imageTransform.Crop is { } box
                ? System.FormattableString.Invariant(
                    $"({box.X:F4},{box.Y:F4},{box.Width:F4},{box.Height:F4})")
                : "none";
            string aspect = imageTransform.CropAspect is { } ratio
                ? ratio.ToString("F4", System.Globalization.CultureInfo.InvariantCulture)
                : "none";
            string angle = imageTransform.StraightenAngle.ToString(
                "F2", System.Globalization.CultureInfo.InvariantCulture);
            Negaflow.Shell.PreviewTrace.Write(
                "transform rot=" + imageTransform.Rotation +
                " flipH=" + imageTransform.FlipHorizontal +
                " flipV=" + imageTransform.FlipVertical +
                " straighten=" + angle + " crop=" + crop + " aspect=" + aspect);
        }
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
