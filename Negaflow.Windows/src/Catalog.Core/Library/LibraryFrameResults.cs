namespace Negaflow.Catalog;

public enum LibraryFrameError
{
    None,

    FrameNotObject,
    MissingId,
    InvalidId,
    MissingSourcePath,
    InvalidSourcePath,
    InvalidDisplayName,

    /// <summary><c>params</c> 가 없거나 object 가 아닙니다.</summary>
    MissingParameters,

    /// <summary><c>manualBaseRGB</c> 가 유한한 세 채널 배열이 아닙니다.</summary>
    InvalidManualBase,

    /// <summary>톤 값이 수가 아니거나 유한하지 않습니다.</summary>
    InvalidToneValue,

    /// <summary>develop route 자체가 거부됐습니다. 정확한 이유는 <c>RouteError</c> 입니다.</summary>
    InvalidDevelopRoute,
}

public readonly record struct LibraryFrameReadResult(
    LibraryFrameSnapshot? Frame,
    LibraryFrameError Error,
    DevelopRouteError RouteError)
{
    public bool IsSuccess => Error == LibraryFrameError.None && Frame is not null;

    internal static LibraryFrameReadResult Success(LibraryFrameSnapshot frame) =>
        new(frame, LibraryFrameError.None, DevelopRouteError.None);

    internal static LibraryFrameReadResult Failure(LibraryFrameError error) =>
        new(null, error, DevelopRouteError.None);

    internal static LibraryFrameReadResult RouteFailure(DevelopRouteError routeError) =>
        new(null, LibraryFrameError.InvalidDevelopRoute, routeError);
}

public readonly record struct LibraryFrameWriteResult(
    System.Text.Json.Nodes.JsonObject? FrameRecord,
    LibraryFrameError Error)
{
    public bool IsSuccess => Error == LibraryFrameError.None && FrameRecord is not null;

    internal static LibraryFrameWriteResult Success(
        System.Text.Json.Nodes.JsonObject frameRecord) =>
        new(frameRecord, LibraryFrameError.None);

    internal static LibraryFrameWriteResult Failure(LibraryFrameError error) =>
        new(null, error);
}
