using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class WorkflowShortcutTests
{
    public static void Run()
    {
        VerifyWorkflowShortcuts();
    }

    private static void VerifyWorkflowShortcuts()
    {
        WorkflowShortcutMap defaults = WorkflowShortcutMap.Defaults;

        // 기본값끼리 부딪히면 그 자체가 결함입니다.
        var seen = new Dictionary<WorkflowShortcut, WorkflowShortcutAction>();
        List<string> collisions = [];
        foreach (WorkflowShortcutAction action in WorkflowShortcutActions.All)
        {
            WorkflowShortcut shortcut = defaults.For(action).Normalized();
            if (shortcut.IsEmpty)
            {
                collisions.Add($"{action} has no key");
                continue;
            }
            if (seen.TryGetValue(shortcut, out WorkflowShortcutAction owner))
            {
                collisions.Add($"{action} collides with {owner} on {shortcut.Display()}");
                continue;
            }
            seen[shortcut] = action;
        }
        Check(collisions.Count == 0, "workflow_shortcut_defaults_are_unique");

        // macOS 와 같은 훑기 키입니다. 이 넷이 틀리면 손에 밴 흐름이 통째로 어긋납니다.
        Check(
            WorkflowShortcutActions.Default(WorkflowShortcutAction.LoadScanner) ==
                new WorkflowShortcut(
                    "l",
                    WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Alt) &&
            WorkflowShortcutActions.Group(WorkflowShortcutAction.LoadScanner) ==
                WorkflowShortcutGroup.Library,
            "workflow_shortcut_load_scanner_matches_mac");

        Check(
            WorkflowShortcutActions.Default(WorkflowShortcutAction.Undo) ==
                new WorkflowShortcut("z", WorkflowShortcutModifiers.Control) &&
            WorkflowShortcutActions.Default(WorkflowShortcutAction.Redo) ==
                new WorkflowShortcut(
                    "z",
                    WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift) &&
            WorkflowShortcutActions.Default(WorkflowShortcutAction.CopyDevelopSettings) ==
                new WorkflowShortcut(
                    "c",
                    WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift) &&
            WorkflowShortcutActions.Default(WorkflowShortcutAction.PasteDevelopSettings) ==
                new WorkflowShortcut(
                    "v",
                    WorkflowShortcutModifiers.Control | WorkflowShortcutModifiers.Shift) &&
            WorkflowShortcutActions.Default(WorkflowShortcutAction.PickPhoto) ==
                new WorkflowShortcut("p", WorkflowShortcutModifiers.None) &&
            WorkflowShortcutActions.Default(WorkflowShortcutAction.RejectPhoto) ==
                new WorkflowShortcut("x", WorkflowShortcutModifiers.None) &&
            WorkflowShortcutActions.Default(WorkflowShortcutAction.DeletePhoto) ==
                new WorkflowShortcut("delete", WorkflowShortcutModifiers.None),
            "workflow_shortcut_edit_menu_keys_match_mac");

        Check(
            defaults.Resolve("p", WorkflowShortcutModifiers.None) ==
                WorkflowShortcutAction.PickPhoto &&
            defaults.Resolve("x", WorkflowShortcutModifiers.None) ==
                WorkflowShortcutAction.RejectPhoto &&
            defaults.Resolve("u", WorkflowShortcutModifiers.None) ==
                WorkflowShortcutAction.ClearPick &&
            defaults.Resolve("3", WorkflowShortcutModifiers.None) ==
                WorkflowShortcutAction.RateThree,
            "workflow_shortcut_culling_keys_match_mac");

        // 이미 쓰이는 키는 거절합니다. 참조가 그대로면 거절입니다.
        WorkflowShortcutMap refused = defaults.With(
            WorkflowShortcutAction.RateOne,
            new WorkflowShortcut("p", WorkflowShortcutModifiers.None));
        Check(ReferenceEquals(refused, defaults), "workflow_shortcut_refuses_a_taken_key");

        // 빈 키로 명령을 잠그지 못하게 합니다.
        Check(
            ReferenceEquals(
                defaults.With(WorkflowShortcutAction.RateOne, WorkflowShortcut.None),
                defaults),
            "workflow_shortcut_refuses_an_empty_key");

        // 바꾼 뒤에는 바꾼 쪽이 이기고, 빼앗긴 명령은 단축키 없는 상태가 됩니다 — 조용히 두
        // 명령이 한 키를 갖는 것보다 낫습니다.
        WorkflowShortcutMap moved = defaults
            .With(WorkflowShortcutAction.RateOne, new WorkflowShortcut("k", WorkflowShortcutModifiers.None))
            .With(WorkflowShortcutAction.RateTwo, new WorkflowShortcut("1", WorkflowShortcutModifiers.None));
        Check(
            moved.Resolve("k", WorkflowShortcutModifiers.None) == WorkflowShortcutAction.RateOne &&
            moved.Resolve("1", WorkflowShortcutModifiers.None) == WorkflowShortcutAction.RateTwo,
            "workflow_shortcut_override_wins_over_a_default");
        Check(moved.Overrides.Count == 2, "workflow_shortcut_stores_only_the_changes");

        // 기본값으로 되돌린 항목은 덮어쓰기 목록에서 사라집니다.
        WorkflowShortcutMap back = moved
            .Reset(WorkflowShortcutAction.RateTwo)
            .With(WorkflowShortcutAction.RateOne, WorkflowShortcutActions.Default(WorkflowShortcutAction.RateOne));
        Check(back.Overrides.Count == 0, "workflow_shortcut_default_value_clears_the_override");
        Check(back == WorkflowShortcutMap.Defaults, "workflow_shortcut_map_compares_by_value");

        // 손으로 고친 설정 파일이 두 명령을 같은 키에 걸어 두었을 수 있습니다.
        WorkflowShortcutMap loaded = new WorkflowShortcutMap
        {
            Overrides = new Dictionary<WorkflowShortcutAction, WorkflowShortcut>
            {
                [WorkflowShortcutAction.RateOne] = new("k", WorkflowShortcutModifiers.None),
                [WorkflowShortcutAction.RateTwo] = new("K", WorkflowShortcutModifiers.None),
            },
        }.Normalize();
        Check(loaded.Overrides.Count == 1, "workflow_shortcut_normalize_drops_a_duplicate");
    }


    /// <summary>
    /// 원본을 폴더 사이로 옮기는 것은 이 앱이 사용자의 파일을 실제로 건드리는 몇 안 되는
    /// 자리입니다. 절반만 옮겨 두고 실패하면 롤이 두 폴더에 흩어진 채 남습니다.
    /// </summary>
}
