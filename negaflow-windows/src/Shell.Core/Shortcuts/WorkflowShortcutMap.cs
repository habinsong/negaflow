namespace Negaflow.Shell.Shortcuts;

/// <summary>
/// 지금 걸려 있는 단축키 전부입니다. 기본값 위에 사용자가 바꾼 것만 얹습니다 — macOS
/// <c>WorkflowShortcutStore</c> 와 같이, 기본값과 같아진 항목은 덮어쓰기 목록에서 지웁니다.
/// </summary>
/// <remarks>
/// **한 키에 두 명령을 허용하지 않습니다.** 허용하면 둘 중 하나는 영영 실행되지 않고, 사용자는
/// 어느 쪽이 죽었는지 알 방법이 없습니다.
/// </remarks>
public sealed record WorkflowShortcutMap
{
    /// <summary>기본값과 다른 것만 담습니다. 저장되는 것도 이것뿐입니다.</summary>
    public IReadOnlyDictionary<WorkflowShortcutAction, WorkflowShortcut> Overrides { get; init; } =
        new Dictionary<WorkflowShortcutAction, WorkflowShortcut>();

    public static WorkflowShortcutMap Defaults { get; } = new();

    public WorkflowShortcut For(WorkflowShortcutAction action) =>
        Overrides.TryGetValue(action, out WorkflowShortcut shortcut)
            ? shortcut
            : WorkflowShortcutActions.Default(action);

    /// <summary>이 키 조합이 부르는 명령입니다. 걸린 것이 없으면 null 입니다.</summary>
    public WorkflowShortcutAction? Resolve(string key, WorkflowShortcutModifiers modifiers)
    {
        WorkflowShortcut pressed = new(key ?? string.Empty, modifiers);
        pressed = pressed.Normalized();
        if (pressed.IsEmpty)
        {
            return null;
        }
        // 사용자가 직접 건 것을 먼저 봅니다. 어떤 명령의 덮어쓰기가 다른 명령의 기본값을
        // 빼앗았다면 이긴 쪽은 사용자가 고른 쪽이어야 합니다 — enum 차례가 아니라.
        foreach ((WorkflowShortcutAction action, WorkflowShortcut shortcut) in Overrides)
        {
            if (shortcut.Normalized() == pressed)
            {
                return action;
            }
        }
        foreach (WorkflowShortcutAction action in WorkflowShortcutActions.All)
        {
            if (!Overrides.ContainsKey(action) &&
                WorkflowShortcutActions.Default(action).Normalized() == pressed)
            {
                return action;
            }
        }
        return null;
    }

    /// <summary>
    /// 단축키를 바꿉니다. 비어 있거나 이미 다른 명령이 쓰고 있으면 바꾸지 않고 자기 자신을
    /// 돌려줍니다 — 부르는 쪽은 참조가 그대로인 것으로 거절을 압니다.
    /// </summary>
    public WorkflowShortcutMap With(WorkflowShortcutAction action, WorkflowShortcut shortcut)
    {
        WorkflowShortcut normalized = shortcut.Normalized();
        if (normalized.IsEmpty)
        {
            return this;
        }
        foreach (WorkflowShortcutAction candidate in WorkflowShortcutActions.All)
        {
            if (candidate != action && For(candidate).Normalized() == normalized)
            {
                return this;
            }
        }
        Dictionary<WorkflowShortcutAction, WorkflowShortcut> updated = new(Overrides);
        if (normalized == WorkflowShortcutActions.Default(action).Normalized())
        {
            updated.Remove(action);
        }
        else
        {
            updated[action] = normalized;
        }
        return this with { Overrides = updated };
    }

    /// <summary>이 명령만 기본값으로 되돌립니다.</summary>
    public WorkflowShortcutMap Reset(WorkflowShortcutAction action)
    {
        if (!Overrides.ContainsKey(action))
        {
            return this;
        }
        Dictionary<WorkflowShortcutAction, WorkflowShortcut> updated = new(Overrides);
        updated.Remove(action);
        return this with { Overrides = updated };
    }

    public WorkflowShortcutMap ResetAll() => Defaults;

    /// <summary>
    /// 저장된 값을 읽을 때 씁니다. 모르는 명령 이름, 빈 키, 그리고 **먼저 온 항목과 부딪히는
    /// 것**은 버립니다 — 손으로 고친 설정 파일이 두 명령을 같은 키에 걸어 두었을 수 있습니다.
    /// </summary>
    public WorkflowShortcutMap Normalize()
    {
        Dictionary<WorkflowShortcutAction, WorkflowShortcut> kept = [];
        var taken = new HashSet<WorkflowShortcut>();
        foreach (WorkflowShortcutAction action in WorkflowShortcutActions.All)
        {
            if (!Overrides.TryGetValue(action, out WorkflowShortcut shortcut))
            {
                continue;
            }
            WorkflowShortcut normalized = shortcut.Normalized();
            if (normalized.IsEmpty || !taken.Add(normalized))
            {
                continue;
            }
            if (normalized != WorkflowShortcutActions.Default(action).Normalized())
            {
                kept[action] = normalized;
            }
        }
        // 덮어쓰기가 기본값 자리를 빼앗았을 수 있습니다. 남은 기본값이 그것과 부딪히면 그 명령은
        // 단축키 없이 둡니다 — 조용히 두 명령이 한 키를 갖는 것보다 낫습니다.
        return this with { Overrides = kept };
    }

    /// <summary>
    /// 이 명령이 지금 쓸 수 있는 단축키를 가지고 있는지. 덮어쓰기 때문에 기본값을 빼앗긴
    /// 명령은 false 입니다.
    /// </summary>
    public bool IsBound(WorkflowShortcutAction action)
    {
        WorkflowShortcut mine = For(action).Normalized();
        if (mine.IsEmpty)
        {
            return false;
        }
        return Resolve(mine.Key, mine.Modifiers) == action;
    }

    /// <summary>
    /// record 의 기본 비교는 사전을 <b>참조</b>로 봅니다. 그대로 두면 내용이 같은 두 설정이
    /// 다르다고 나오고, 설정 저장소의 "바뀐 것이 없으면 쓰지 않는다" 가 무너져 실행할 때마다
    /// 파일을 다시 씁니다.
    /// </summary>
    public bool Equals(WorkflowShortcutMap? other)
    {
        if (other is null)
        {
            return false;
        }
        if (ReferenceEquals(this, other))
        {
            return true;
        }
        if (Overrides.Count != other.Overrides.Count)
        {
            return false;
        }
        foreach ((WorkflowShortcutAction action, WorkflowShortcut shortcut) in Overrides)
        {
            if (!other.Overrides.TryGetValue(action, out WorkflowShortcut candidate) ||
                candidate != shortcut)
            {
                return false;
            }
        }
        return true;
    }

    public override int GetHashCode()
    {
        // 차례에 기대지 않는 결합입니다 — 사전은 순서를 약속하지 않습니다.
        int hash = Overrides.Count;
        foreach ((WorkflowShortcutAction action, WorkflowShortcut shortcut) in Overrides)
        {
            hash ^= HashCode.Combine(action, shortcut.Key, shortcut.Modifiers);
        }
        return hash;
    }
}
