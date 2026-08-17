using System.Globalization;
using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>버전 목록 한 줄입니다. 표시 문구를 XAML 이 짓지 않도록 여기서 만듭니다.</summary>
public sealed record VersionRow(
    string Id,
    string Name,
    string CreatedText,
    string RestoreText,
    string DeleteText);

/// <summary>
/// 버전 목록의 줄을 만듭니다. 만든 시각을 어떤 표기로 적을지는 화면 배치·이벤트와 다른
/// 이유로 바뀌므로 뷰 밖에 둡니다. 단추 이름은 밖에서 받습니다.
/// </summary>
public static class VersionListProjection
{
    public static IReadOnlyList<VersionRow> Rows(
        IReadOnlyList<LibraryVersionSnapshot> versions,
        string restoreText,
        string deleteText)
    {
        List<VersionRow> rows = [];
        foreach (LibraryVersionSnapshot version in versions)
        {
            rows.Add(new VersionRow(
                version.Id,
                version.Name,
                // 기록되지 않은 시각을 지어내지 않습니다 — 비워 둡니다.
                version.CreatedAt is { } created
                    ? created.ToLocalTime().ToString("g", CultureInfo.CurrentCulture)
                    : string.Empty,
                restoreText,
                deleteText));
        }
        return rows;
    }
}
