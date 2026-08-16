using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class LibraryFrameMetadataWriter
{
    internal static void Apply(JsonObject updated, LibraryFrameEdit edit)
    {
        if (edit.Rating is { } rating)
        {
            updated[LibraryFrameReader.RatingName] = rating;
        }
        if (edit.PickState is { } pick)
        {
            updated[LibraryFrameReader.PickStateName] = pick switch
            {
                FramePickState.Picked => "picked",
                FramePickState.Rejected => "rejected",
                _ => "unflagged",
            };
        }
        if (edit.DisplayName is { } name)
        {
            if (name.Name is { } displayName)
            {
                updated[LibraryFrameReader.DisplayNameName] = displayName;
            }
            else
            {
                updated.Remove(LibraryFrameReader.DisplayNameName);
            }
        }
        if (edit.LookPreset is { } preset)
        {
            if (preset.Id is { } presetId)
            {
                updated[LibraryFrameReader.LookPresetIdName] = presetId;
            }
            else
            {
                updated.Remove(LibraryFrameReader.LookPresetIdName);
            }
        }
    }
}
