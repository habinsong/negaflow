namespace Negaflow.Catalog;

/// <summary>
/// 앱이 들고 있는 룩 프로파일 목록입니다. macOS <c>AppModel.presets</c> 와 같은 자리입니다.
/// </summary>
/// <remarks>
/// 프로세스 전역인 이유는 하나입니다 — preview, thumbnail, export 가 같은 프리셋을 봐야 하고,
/// 호출부마다 목록을 넘기게 하면 한 군데만 빠져도 미리보기와 내보내기가 다른 그림이 됩니다.
/// 그 계약을 호출부의 성실함이 아니라 타입으로 보장합니다. 목록은 시작할 때 한 번 정해지고
/// 그 뒤로는 읽기만 하므로 참조 교체만으로 충분합니다.
/// </remarks>
public static class LookPresetLibrary
{
    private static volatile IReadOnlyList<LookPreset> loaded = [];

    /// <summary>읽힌 순서 그대로입니다. 아직 읽지 않았으면 빈 목록이고, 그때는 프리셋 없이 현상합니다.</summary>
    public static IReadOnlyList<LookPreset> All => loaded;

    public static void Load(string directory) => loaded = PresetRegistry.LoadAll(directory);

    /// <summary>테스트가 디스크 없이 목록을 정합니다.</summary>
    public static void SetForTests(IReadOnlyList<LookPreset> presets) =>
        loaded = presets ?? throw new ArgumentNullException(nameof(presets));

    /// <summary>
    /// 모르는 id 는 null 입니다. 프로파일 하나가 없어졌다고 현상을 거부하면 사진을 아예 못 보게
    /// 되므로, 프리셋 없이 사용자 값만으로 현상합니다.
    /// </summary>
    public static LookPreset? Resolve(string? id)
    {
        if (string.IsNullOrWhiteSpace(id))
        {
            return null;
        }
        IReadOnlyList<LookPreset> presets = loaded;
        for (int index = 0; index < presets.Count; index++)
        {
            if (presets[index].Id == id)
            {
                return presets[index];
            }
        }
        return null;
    }
}
