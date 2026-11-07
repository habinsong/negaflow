namespace Negaflow.Shell.Shortcuts;

/// <summary>
/// 키 없이 조합키만으로 거는 동작입니다. 마우스 드래그와 함께 누르거나(기준선) 누르고 있는 동안만
/// 켜집니다(격자). macOS <c>WorkflowGestureModifierAction</c> 과 같은 두 동작이며, macOS 의 ⌘·⌥
/// 자리가 Windows 에서는 Ctrl·Alt 입니다(<see cref="WorkflowShortcutModifiers"/> 머리말).
/// </summary>
public enum WorkflowGestureModifierAction
{
    /// <summary>크롭 중 이 키를 누른 채 사진 위를 끌면 기준선을 그리고, 놓으면 그 선을 수평·수직으로 맞춥니다.</summary>
    StraightenWithLine,

    /// <summary>크롭 중 이 키를 누르고 있는 동안 촘촘한 격자를 보여 줍니다.</summary>
    StraightenGrid,
}

public static class WorkflowGestureModifierActions
{
    public static IReadOnlyList<WorkflowGestureModifierAction> All { get; } =
        Enum.GetValues<WorkflowGestureModifierAction>();

    public static WorkflowShortcutModifiers Default(WorkflowGestureModifierAction action) => action switch
    {
        WorkflowGestureModifierAction.StraightenWithLine => WorkflowShortcutModifiers.Control,
        _ => WorkflowShortcutModifiers.Alt,
    };

    /// <summary>고를 수 있는 조합키입니다. 하나만 고릅니다 — 둘을 섞으면 다른 동작과 겹치기 쉽습니다.</summary>
    public static IReadOnlyList<WorkflowShortcutModifiers> Allowed { get; } =
    [
        WorkflowShortcutModifiers.Control,
        WorkflowShortcutModifiers.Alt,
        WorkflowShortcutModifiers.Shift,
    ];

    /// <summary>지금 눌린 조합키에 이 키가 들어 있는가. 다른 조합키가 같이 눌려 있어도 됩니다.</summary>
    public static bool IsHeld(WorkflowShortcutModifiers modifier, WorkflowShortcutModifiers held) =>
        modifier != WorkflowShortcutModifiers.None && (held & modifier) == modifier;
}
