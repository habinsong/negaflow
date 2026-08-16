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

internal static class SourceMoveTests
{
    public static void Run()
    {
        VerifySourceMove();
    }

    private static void VerifySourceMove()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "source-move-tests");
        string root = Path.Combine(testParent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        string from = Path.Combine(root, "from");
        string to = Path.Combine(root, "to");
        try
        {
            Directory.CreateDirectory(from);
            Directory.CreateDirectory(to);
            string raw = Path.Combine(from, "IMG_0001.tif");
            string infrared = Path.Combine(from, "IMG_0001.ir.tif");
            File.WriteAllBytes(raw, [1, 2, 3]);
            File.WriteAllBytes(infrared, [4, 5, 6]);

            // 없는 폴더로는 계획을 세우지 않습니다.
            Check(
                SourceMovePlanner.Files(
                    [new SourceMovePair(raw, null)],
                    Path.Combine(root, "missing")).Error ==
                    SourceMovePlanError.InvalidDestination,
                "source_move_refuses_a_missing_destination");

            // 이미 그 폴더에 있으면 옮길 것이 없습니다.
            Check(
                SourceMovePlanner.Files([new SourceMovePair(raw, null)], from).Error ==
                    SourceMovePlanError.NothingToMove,
                "source_move_nothing_to_do");

            // IR 짝은 본 스캔과 함께 움직입니다 — 남겨 두면 다음 검출이 다른 폴더를 봅니다.
            SourceMovePlanResult planned = SourceMovePlanner.Files(
                [new SourceMovePair(raw, infrared)],
                to);
            Check(planned.IsSuccess, "source_move_plan");
            Check(planned.Plan!.FileMoves.Count == 2, "source_move_takes_the_infrared_too");
            Check(planned.Plan.SourceCount == 1, "source_move_counts_photos_not_files");
            Check(
                planned.Plan.RelinkPlan.Mappings.Count == 1 &&
                    planned.Plan.RelinkPlan.Mappings[0].NewSourcePath ==
                        Path.Combine(to, "IMG_0001.tif"),
                "source_move_relink_follows_the_files");

            Check(
                SourceMoveTransaction.Move(planned.Plan.FileMoves).IsSuccess,
                "source_move_transaction");
            Check(
                File.Exists(Path.Combine(to, "IMG_0001.tif")) &&
                    File.Exists(Path.Combine(to, "IMG_0001.ir.tif")) &&
                    !File.Exists(raw),
                "source_move_moved_both_files");

            // 같은 이름이 이미 있으면 덮지 않고 번호를 붙입니다.
            File.WriteAllBytes(raw, [7, 8, 9]);
            SourceMovePlanResult second = SourceMovePlanner.Files(
                [new SourceMovePair(raw, null)],
                to);
            Check(
                second.IsSuccess &&
                    second.Plan!.FileMoves[0].DestinationPath ==
                        Path.Combine(to, "IMG_0001-2.tif"),
                "source_move_never_overwrites");

            // 두 번째 파일이 부딪히면 첫 번째까지 되돌아와야 합니다.
            string good = Path.Combine(from, "A.tif");
            string blocked = Path.Combine(from, "B.tif");
            File.WriteAllBytes(good, [1]);
            File.WriteAllBytes(blocked, [2]);
            File.WriteAllBytes(Path.Combine(to, "B.tif"), [9]);
            SourceMoveResult rolled = SourceMoveTransaction.Move(
            [
                new SourceFileMove(good, Path.Combine(to, "A.tif")),
                new SourceFileMove(blocked, Path.Combine(to, "B.tif")),
            ]);
            Check(
                rolled.Outcome == SourceMoveOutcome.Collision,
                "source_move_reports_the_collision");
            Check(rolled.RollbackFailures.Count == 0, "source_move_rollback_succeeded");
            Check(
                File.Exists(good) && !File.Exists(Path.Combine(to, "A.tif")),
                "source_move_rolls_the_first_file_back");
        }
        finally
        {
            if (Directory.Exists(root) &&
                StoragePathPolicy.IsLexicallyContained(testParent, root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }


    /// <summary>
    /// 현상 타깃은 사진 성격을 통째로 바꿉니다. 타깃과 스캐너 프로파일이 함께 걸리면 두 성격이
    /// 겹쳐 어느 쪽이 나온 그림인지 알 수 없게 됩니다.
    /// </summary>
}
