using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>Persists texture and noise-reduction recipes.</summary>
internal sealed class DevelopEffectsEditor
{
    private readonly LibraryHostService host;

    public DevelopEffectsEditor(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        this.host = host;
    }

    public DevelopEditResult Reset(LibraryFrameSnapshot? frame) =>
        frame is null
            ? Missing()
            : Edit(
                frame,
                new LibraryFrameEdit(
                    frame.Tone,
                    frame.ManualBase,
                    Texture: TextureRecipe.Identity,
                    NoiseReduction: NoiseReductionRecipe.Identity));

    public DevelopEditResult SetTexture(LibraryFrameSnapshot? frame, TextureRecipe texture)
    {
        ArgumentNullException.ThrowIfNull(texture);
        return frame is null
            ? Missing()
            : Edit(
                frame,
                new LibraryFrameEdit(frame.Tone, frame.ManualBase, Texture: texture));
    }

    public DevelopEditResult SetNoiseReduction(
        LibraryFrameSnapshot? frame,
        NoiseReductionRecipe noiseReduction)
    {
        ArgumentNullException.ThrowIfNull(noiseReduction);
        return frame is null
            ? Missing()
            : Edit(
                frame,
                new LibraryFrameEdit(
                    frame.Tone,
                    frame.ManualBase,
                    NoiseReduction: noiseReduction));
    }

    private DevelopEditResult Edit(LibraryFrameSnapshot frame, LibraryFrameEdit edit)
    {
        LibraryFrameError error = host.Edit(frame.Id, edit);
        return new(error, error == LibraryFrameError.None);
    }

    private static DevelopEditResult Missing() =>
        new(LibraryFrameError.MissingId, false);
}
