namespace Negaflow.Shell.Shortcuts;

/// <summary>
/// macOS <c>WorkflowShortcutModifiers</c> 와 같은 조합 키입니다.
/// </summary>
/// <remarks>
/// macOS 의 <c>command</c> 자리는 Windows 에서 <c>Control</c> 입니다 — 두 플랫폼에서 "주 조합
/// 키" 라는 같은 자리를 차지하기 때문입니다. macOS 의 <c>option</c> 은 <c>Alt</c>,
/// <c>control</c> 은 Windows 에도 Control 밖에 없어 겹치므로 그 자리는 <c>Alt+Shift</c> 로
/// 옮겼습니다. 겹친 채로 두면 두 명령이 같은 키에 걸려 하나가 영영 실행되지 않습니다.
/// </remarks>
[Flags]
public enum WorkflowShortcutModifiers
{
    None = 0,
    Control = 1,
    Alt = 2,
    Shift = 4,
}

/// <summary>
/// 키 하나와 조합 키입니다. 키는 소문자 한 글자이거나 <c>delete</c> 같은 이름입니다 — macOS
/// 저장 형식과 같은 모양이라 두 앱이 같은 문자열을 읽습니다.
/// </summary>
public readonly record struct WorkflowShortcut(string Key, WorkflowShortcutModifiers Modifiers)
{
    public static WorkflowShortcut None => new(string.Empty, WorkflowShortcutModifiers.None);

    public bool IsEmpty => string.IsNullOrEmpty(Key);

    /// <summary>
    /// 저장·비교에 쓰는 표준 모양입니다. 대소문자와 조합 키 차례가 흔들리면 같은 단축키가
    /// 서로 다른 두 값으로 저장되어 충돌 검사가 통과해 버립니다.
    /// </summary>
    public WorkflowShortcut Normalized() =>
        new(Key.Trim().ToLowerInvariant(), Modifiers);

    /// <summary>화면에 보이는 모양입니다. Windows 관례대로 Ctrl+Alt+Shift 차례입니다.</summary>
    public string Display()
    {
        if (IsEmpty)
        {
            return string.Empty;
        }
        List<string> parts = [];
        if (Modifiers.HasFlag(WorkflowShortcutModifiers.Control))
        {
            parts.Add("Ctrl");
        }
        if (Modifiers.HasFlag(WorkflowShortcutModifiers.Alt))
        {
            parts.Add("Alt");
        }
        if (Modifiers.HasFlag(WorkflowShortcutModifiers.Shift))
        {
            parts.Add("Shift");
        }
        parts.Add(KeyLabel(Key));
        return string.Join('+', parts);
    }

    private static string KeyLabel(string key) => key switch
    {
        "delete" => "Delete",
        "space" => "Space",
        "left" => "Left",
        "right" => "Right",
        _ => key.ToUpperInvariant(),
    };
}
