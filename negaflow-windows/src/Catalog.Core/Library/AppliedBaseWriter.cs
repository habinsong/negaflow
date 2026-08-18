using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// macOS <c>LibraryFrameRecord.baseRGB</c> 입니다. 레시피가 아니므로 <c>params</c> 안이 아니라
/// 그 형제 자리에 둡니다. 현상 결과가 앉힌 Dmin 이며 수동 샘플과 자리가 다릅니다.
/// </summary>
public static class AppliedBaseWriter
{
    public static LibraryFrameWriteResult Apply(JsonObject frameRecord, ManualBaseRgb? applied)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        if (applied is { } rgb && !BaseRecipeJsonCodec.IsValid(rgb))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidAppliedBase);
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        if (applied is { } written)
        {
            updated[LibraryFrameReader.BaseRgbName] = new JsonArray(
                written.Red,
                written.Green,
                written.Blue);
        }
        else
        {
            updated.Remove(LibraryFrameReader.BaseRgbName);
        }
        return LibraryFrameWriteResult.Success(updated);
    }
}
