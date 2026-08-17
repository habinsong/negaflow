using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>붙여넣기 범위 요약이 쓰는 이름들입니다. 어느 말로 낼지는 화면이 정합니다.</summary>
public sealed record PasteScopeText(
    string All,
    string None,
    string Base,
    string Tone,
    string Color,
    string Detail,
    string Geometry);

/// <summary>
/// 붙여넣기 범위 단추의 요약 문구입니다. macOS 표기가 바뀔 때 바뀌므로 화면 배치·이벤트와
/// 같은 자리에 두지 않습니다.
/// </summary>
public static class PasteScopeSummary
{
    /// <summary>
    /// 전부면 "모든 설정", 하나도 없으면 "없음", 그 사이는 켜진 묶음 이름을 순서대로 잇습니다.
    /// </summary>
    public static string Describe(DevelopSettingsPasteScope scope, PasteScopeText text)
    {
        if (scope.IsFullDevelopScope)
        {
            return text.All;
        }
        List<string> groups = [];
        if (scope.Base)
        {
            groups.Add(text.Base);
        }
        if (scope.Tone)
        {
            groups.Add(text.Tone);
        }
        if (scope.Color)
        {
            groups.Add(text.Color);
        }
        if (scope.Detail)
        {
            groups.Add(text.Detail);
        }
        if (scope.Geometry)
        {
            groups.Add(text.Geometry);
        }
        return groups.Count == 0 ? text.None : string.Join("/", groups);
    }
}
