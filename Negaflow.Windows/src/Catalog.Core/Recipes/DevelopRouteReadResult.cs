namespace Negaflow.Catalog;

public readonly record struct DevelopRouteReadResult(
    DevelopRouteSnapshot? Route,
    DevelopRouteError Error)
{
    public bool IsSuccess => Error == DevelopRouteError.None && Route is not null;

    internal static DevelopRouteReadResult Success(DevelopRouteSnapshot route) =>
        new(route, DevelopRouteError.None);

    internal static DevelopRouteReadResult Failure(DevelopRouteError error) =>
        new(null, error);
}
