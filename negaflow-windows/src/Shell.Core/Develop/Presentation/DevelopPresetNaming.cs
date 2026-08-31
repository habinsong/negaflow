namespace Negaflow.Shell.Develop;

/// <summary>
/// 사용자 프리셋 이름을 정합니다. 어느 말로 낼지는 화면이 정하고, 겹치지 않게 만드는 규칙만
/// 여기 둡니다.
/// </summary>
public static class DevelopPresetNaming
{
    /// <summary>
    /// 저장할 이름입니다. 비워 두면 <paramref name="autoName"/> 이 만드는 번호 이름을 쓰고,
    /// 어느 쪽이든 이미 있는 이름과 겹치지 않을 때까지 번호를 올립니다.
    /// </summary>
    /// <param name="requested">사용자가 적은 이름입니다. 비었거나 공백뿐이면 자동으로 짓습니다.</param>
    /// <param name="existing">이미 있는 프리셋 이름들입니다.</param>
    /// <param name="autoName">번호로 자동 이름을 만드는 자입니다(예: 1 → "프리셋 1").</param>
    /// <remarks>
    /// 겹침은 <b>대소문자를 가리지 않고</b> 봅니다. 목록에서 사람이 읽고 고르는 이름이라
    /// "Portra" 와 "portra" 가 나란히 있으면 어느 쪽인지 알 수 없습니다.
    ///
    /// 적어 준 이름이 겹칠 때도 번호를 붙입니다. 저장은 됐는데 목록에 같은 이름이 둘이면
    /// 어느 것을 지우는지 알 수 없어, 조용히 실패한 것보다 나쁩니다.
    /// </remarks>
    public static string Resolve(
        string? requested,
        IReadOnlyList<string> existing,
        Func<int, string> autoName)
    {
        ArgumentNullException.ThrowIfNull(existing);
        ArgumentNullException.ThrowIfNull(autoName);

        string trimmed = (requested ?? string.Empty).Trim();
        if (trimmed.Length == 0)
        {
            // 자동 이름은 1 부터 세어 **비어 있는 첫 번호**를 씁니다. 개수+1 로 하면 중간을
            // 지웠을 때 이미 있는 번호와 부딪힙니다.
            for (int index = 1; ; ++index)
            {
                string candidate = autoName(index);
                if (!Contains(existing, candidate))
                {
                    return candidate;
                }
            }
        }

        if (!Contains(existing, trimmed))
        {
            return trimmed;
        }
        for (int suffix = 2; ; ++suffix)
        {
            string candidate = $"{trimmed} {suffix}";
            if (!Contains(existing, candidate))
            {
                return candidate;
            }
        }
    }

    private static bool Contains(IReadOnlyList<string> existing, string candidate)
    {
        foreach (string name in existing)
        {
            if (string.Equals(name, candidate, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }
}
