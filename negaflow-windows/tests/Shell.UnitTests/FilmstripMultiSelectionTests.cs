using Negaflow.Catalog;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 하단 필름스트립에서 Shift·Ctrl 로 여러 장을 고르면 <b>공유 선택</b>이 그만큼 담기는지,
/// 그리고 그것이 일괄 내보내기가 보는 목록인지의 시험입니다.
/// </summary>
/// <remarks>
/// <para>
/// 현상뷰는 이 풀이를 자기 안에 따로 들고 있었습니다 — 누른 순간 컨트롤이 잡고 있는 선택을
/// 읽어 판단했는데, <c>ItemClick</c> 이 <c>SelectionChanged</c> 보다 먼저 오므로 방금 Ctrl 로
/// 더한 사진이 그 목록에 아직 없었습니다. 그래서 언제나 한 장으로 접혔고, 이어지는
/// <c>Activate</c> 가 그 한 장짜리 선택을 스트립에 되써서 Shift·Ctrl 이 아예 듣지
/// 않았습니다. 이제 인화뷰·macOS 와 같이 라이브러리의 <c>SelectFrame</c> 이 풀이합니다.
/// </para>
/// <para>
/// 명령 자체의 규칙(범위·토글·기준점)은 <c>PrintCustomPackageTests</c> 가 덮습니다. 여기서는
/// <b>라이브러리를 거쳐 나온 선택</b>만 봅니다 — 현상뷰의 내보내기·빠른 내보내기가 실제로
/// 읽는 것이 <c>SelectedFrames</c> 이기 때문입니다.
/// </para>
/// </remarks>
internal static class FilmstripMultiSelectionTests
{
    public static void Run()
    {
        string root = Path.Combine(
            Path.GetTempPath(), "negaflow-filmstrip-selection-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            LibraryFrameSnapshot[] frames =
            [
                Frame(null, sourcePath: Path.Combine(root, "a.tif")) with { Id = "a" },
                Frame(null, sourcePath: Path.Combine(root, "b.tif")) with { Id = "b" },
                Frame(null, sourcePath: Path.Combine(root, "c.tif")) with { Id = "c" },
            ];
            string[] ordered = [.. frames.Select(frame => frame.Id)];

            // Shift 로 사이를 잡습니다. 스트립이 보여 주는 차례가 곧 사이의 차례입니다.
            LibraryFrameSelectionCommand ranged = LibraryFrameSelectionCommand.Apply(
                "c", ordered, ["a"], "a", "a", LibrarySelectionModifiers.Shift);
            Check(
                Resolve(frames, ranged).Length == 3,
                "filmstrip_shift_selection_reaches_the_shared_list");

            // 그 다음 Ctrl 로 가운데 한 장을 뺍니다.
            LibraryFrameSelectionCommand toggled = LibraryFrameSelectionCommand.Apply(
                "b",
                ordered,
                ranged.SelectedFrameIds,
                ranged.ActiveFrameId,
                ranged.AnchorFrameId,
                LibrarySelectionModifiers.Toggle);
            string[] remaining = Resolve(frames, toggled);
            Check(
                remaining.Length == 2 && !remaining.Contains("b", StringComparer.Ordinal),
                "filmstrip_ctrl_selection_reaches_the_shared_list");

            // 현상뷰의 내보내기·빠른 내보내기는 이 목록이 둘 이상이면 배치로 갑니다
            // (`DevelopExportRunner.SelectedExportFrames`). 그 갈림길을 값으로 확인합니다.
            Check(
                ExportsAsBatch(remaining.Length) && !ExportsAsBatch(1),
                "filmstrip_multi_selection_takes_the_batch_export_path");
        }
        finally
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (IOException)
            {
                // 임시 폴더를 못 지운 것은 시험 결과에 영향을 주지 않습니다.
            }
        }
    }

    /// <summary>
    /// 카탈로그에 있는 사진만 남기는 <c>LibrarySelectionState.Set</c> 과 같은 거르기입니다.
    /// </summary>
    private static string[] Resolve(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        LibraryFrameSelectionCommand command)
    {
        HashSet<string> known = [.. frames.Select(frame => frame.Id)];
        return [.. command.SelectedFrameIds.Where(known.Contains)];
    }

    /// <summary>macOS <c>exportSelection</c> 과 같은 갈림길입니다 — 둘 이상이면 배치입니다.</summary>
    private static bool ExportsAsBatch(int selectedFrameCount) => selectedFrameCount > 1;
}
