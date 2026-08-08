using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

public readonly record struct DevelopRouteWriteResult(
    JsonObject? FrameRecord,
    DevelopRouteError Error)
{
    public bool IsSuccess => Error == DevelopRouteError.None && FrameRecord is not null;

    internal static DevelopRouteWriteResult Success(JsonObject frameRecord) =>
        new(frameRecord, DevelopRouteError.None);

    internal static DevelopRouteWriteResult Failure(DevelopRouteError error) =>
        new(null, error);
}
