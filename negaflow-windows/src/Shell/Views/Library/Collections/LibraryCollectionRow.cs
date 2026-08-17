namespace Negaflow.Shell.Views.Library.Collections;

/// <summary>목록 한 줄입니다. 이름을 한 곳에서만 만들어야 줄마다 말이 달라지지 않습니다.</summary>
internal sealed record LibraryCollectionRow(
    string? Id,
    string Name,
    string CountText,
    string Glyph,
    bool IsStoredSearch = false,
    bool IsGroupLabel = false);
