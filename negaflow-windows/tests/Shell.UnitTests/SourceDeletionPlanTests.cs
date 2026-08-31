using Negaflow.Catalog;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// "원본 파일을 휴지통으로 이동" 이 무엇을 데려가는지 고정합니다.
/// </summary>
/// <remarks>
/// <b>IR 짝은 원본과 함께 가야 합니다.</b> 남겨 두면 사진은 사라졌는데 그 옆에 정체를 알
/// 수 없는 `*.ir.tiff` 만 남고, 다음 가져오기가 그것을 주인 없는 IR 로 다시 집습니다.
/// 계획에 들어 있기는 했지만 그것을 잡아 두는 시험이 없었습니다.
/// </remarks>
internal static class SourceDeletionPlanTests
{
    public static void Run()
    {
        InfraredCompanionTravelsWithItsSource();
        SharedSourceCollectsEveryFrameAndInfrared();
        NothingToDeleteWhenOnlyDerivedFramesAreChosen();
    }

    private static void InfraredCompanionTravelsWithItsSource()
    {
        LibraryFrameSnapshot frame = Frame(null, sourcePath: @"C:\scans\roll-0001.tif") with
        {
            InfraredPath = @"C:\scans\roll-0001.tif.ir.tiff",
        };

        SourceDeletionPlan? plan = SourceDeletionPlan.For([frame], [frame]);

        Check(plan is not null, "deletion_plan_exists");
        if (plan is null)
        {
            return;
        }
        Check(plan.SourceCount == 1, "deletion_plan_source_count");
        Check(plan.FrameCount == 1, "deletion_plan_frame_count");
        // 원본과 IR **둘 다** 옮겨야 합니다. `AllPaths` 가 그대로 휴지통 거래로 갑니다.
        Check(plan.AllPaths.Count == 2, "deletion_plan_moves_source_and_infrared");
        Check(
            plan.AllPaths.Any(path => path.EndsWith("roll-0001.tif", StringComparison.OrdinalIgnoreCase)),
            "deletion_plan_keeps_source");
        Check(
            plan.AllPaths.Any(path => path.EndsWith(".ir.tiff", StringComparison.OrdinalIgnoreCase)),
            "deletion_plan_keeps_infrared");
    }

    private static void SharedSourceCollectsEveryFrameAndInfrared()
    {
        // 같은 원본을 쓰는 두 프레임. 하나만 골라도 원본이 사라지면 둘 다 못 씁니다.
        LibraryFrameSnapshot first = Frame(null, sourcePath: @"C:\scans\roll-0002.tif") with
        {
            InfraredPath = @"C:\scans\roll-0002.tif.ir.tiff",
        };
        LibraryFrameSnapshot second = first with { Id = "frame-2" };

        SourceDeletionPlan? plan = SourceDeletionPlan.For([first], [first, second]);

        Check(plan is not null, "shared_source_plan_exists");
        if (plan is null)
        {
            return;
        }
        Check(plan.FrameCount == 2, "shared_source_counts_both_frames");
        Check(plan.SourceCount == 1, "shared_source_counts_one_source");
        // IR 은 한 번만 옮깁니다 - 두 프레임이 같은 파일을 가리킵니다.
        Check(plan.AllPaths.Count == 2, "shared_source_deduplicates_infrared");
    }

    private static void NothingToDeleteWhenOnlyDerivedFramesAreChosen()
    {
        LibraryFrameSnapshot original = Frame(null, sourcePath: @"C:\scans\roll-0003.tif");
        // `IsVirtualCopy` 는 사본 번호에서 나옵니다 - 번호를 주면 사본이 됩니다.
        LibraryFrameSnapshot copy = original with { Id = "frame-copy", VirtualCopyNumber = 2 };
        LibraryFrameSnapshot preview = original with { Id = "frame-preview", IsPreviewScan = true };

        Check(
            SourceDeletionPlan.For([copy], [original, copy]) is null,
            "virtual_copy_deletes_no_source");
        Check(
            SourceDeletionPlan.For([preview], [original, preview]) is null,
            "preview_scan_deletes_no_source");
    }
}
