using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 내보내기 목적지가 이미 있는 파일을 덮지 않도록 빈 이름을 찾는지의 시험입니다.
/// </summary>
/// <remarks>
/// 엔진은 이미 있는 파일을 덮지 않습니다(<c>atomic_output_file.cpp</c>:
/// <c>destination_exists</c>) — 사용자가 만든 것을 조용히 지우지 않으려는 방어입니다.
/// 그런데 <b>한 장 내보내기</b>는 빈 이름을 찾지 않고 템플릿이 낸 경로를 그대로 썼습니다.
/// 배치만 <c>ExportBatchCoordinator.Plan</c> 에서 고유화했습니다.
///
/// 그래서 같은 사진을 두 번째로 내보내면 <b>언제나</b> 실패했고, 화면에는
/// "Develop stopped at writing the file: destination_exists" 만 떴습니다. 사용자는 기존
/// 사진의 내보내기·빠른 내보내기·인화뷰 내보내기가 통째로 막힌 것으로 겪습니다.
/// </remarks>
internal static class ExportUniqueDestinationTests
{
    internal static void Run()
    {
        string root = Path.Combine(
            Path.GetTempPath(), "negaflow-export-unique-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            string first = Path.Combine(root, "photo.png");

            // 없는 이름은 그대로 씁니다 — 멀쩡한 이름을 괜히 바꾸지 않습니다.
            Check(
                string.Equals(
                    ExportBatchCoordinator.UniquePath(first), first, StringComparison.Ordinal),
                "export_unique_keeps_free_name");

            File.WriteAllBytes(first, [1]);
            string second = ExportBatchCoordinator.UniquePath(first);
            Check(
                !string.Equals(second, first, StringComparison.Ordinal) && !File.Exists(second),
                "export_unique_avoids_existing_file");
            Check(
                string.Equals(
                    Path.GetExtension(second), ".png", StringComparison.OrdinalIgnoreCase),
                "export_unique_keeps_extension");

            // 여러 번 이어서 내보내도 계속 빈 이름이 나옵니다.
            File.WriteAllBytes(second, [1]);
            string third = ExportBatchCoordinator.UniquePath(first);
            Check(
                !File.Exists(third) &&
                    !string.Equals(third, first, StringComparison.Ordinal) &&
                    !string.Equals(third, second, StringComparison.Ordinal),
                "export_unique_keeps_finding_free_names");

            // 확장자가 없는 이름도 안전해야 합니다 — 인화 시트 이름이 그런 모양일 수 있습니다.
            string bare = Path.Combine(root, "sheet");
            File.WriteAllBytes(bare, [1]);
            Check(
                !File.Exists(ExportBatchCoordinator.UniquePath(bare)),
                "export_unique_handles_extensionless");
        }
        finally
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
            }
        }
    }
}
