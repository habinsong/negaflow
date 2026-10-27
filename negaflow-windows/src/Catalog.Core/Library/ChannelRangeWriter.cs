using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 롤 교정이 찍는 값입니다. <c>params.channelRange</c> 는 레시피(자동 밸런스를 끈 반전이 읽습니다)라
/// 사용자 편집 기록 없이 <see cref="AppliedBaseWriter"/> 와 같은 길로 씁니다 — 자동으로 찍은 값이
/// 되돌리기 칸을 채우지 않게 하기 위해서입니다.
/// </summary>
public static class ChannelRangeWriter
{
    public static LibraryFrameWriteResult Apply(JsonObject frameRecord, ChannelRangeRgb? range)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        ChannelRangeRgb? sanitized = null;
        if (range is { } requested)
        {
            sanitized = ChannelRangeCalibration.Sanitized(requested);
            if (sanitized is null)
            {
                return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidChannelRange);
            }
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        if (updated[LibraryFrameReader.ParametersName] is not JsonObject parameters)
        {
            parameters = [];
            updated[LibraryFrameReader.ParametersName] = parameters;
        }
        if (sanitized is { } written)
        {
            parameters[LibraryFrameReader.ChannelRangeName] = ChannelRangeCalibration.ToJson(written);
        }
        else
        {
            parameters.Remove(LibraryFrameReader.ChannelRangeName);
        }
        return LibraryFrameWriteResult.Success(updated);
    }
}

/// <summary>
/// macOS <c>LibraryFrameRecord.rangeShapeRGB</c> 입니다. 렌더가 잰 채널 범위 모양(롤 교정의 재료)이며
/// 레시피가 아니므로 <c>params</c> 형제 자리에 둡니다.
/// </summary>
public static class RangeShapeWriter
{
    public static LibraryFrameWriteResult Apply(JsonObject frameRecord, ChannelRangeRgb? shape)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        ChannelRangeRgb? sanitized = null;
        if (shape is { } requested)
        {
            sanitized = ChannelRangeCalibration.Sanitized(requested);
            if (sanitized is null)
            {
                return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidChannelRange);
            }
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        if (sanitized is { } written)
        {
            updated[LibraryFrameReader.RangeShapeName] = ChannelRangeCalibration.ToJson(written);
        }
        else
        {
            updated.Remove(LibraryFrameReader.RangeShapeName);
        }
        return LibraryFrameWriteResult.Success(updated);
    }
}
