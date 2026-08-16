using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

internal readonly record struct DevelopEditResult(
    LibraryFrameError Error,
    bool Changed);
