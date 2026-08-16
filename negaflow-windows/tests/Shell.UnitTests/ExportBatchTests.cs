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

internal static class ExportBatchTests
{
    public static void Run()
    {
        VerifyExportBatchPlan();
    }

    private static void VerifyExportBatchPlan()
    {
        string root = Path.Combine(
            Path.GetTempPath(),
            "negaflow-export-batch-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            // 이름은 카드에 보이는 이름입니다 — 원본 경로가 아니라 그것이 파일 이름이 됩니다.
            LibraryFrameSnapshot[] frames =
            [
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    displayName: "IMG_0001",
                    sourcePath: @"C:\scans\IMG_0001.tif"),
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    displayName: "IMG_0002",
                    sourcePath: @"C:\scans\IMG_0002.tif"),
                // 다른 폴더의 같은 이름입니다. 한 폴더로 내보내면 부딪힙니다.
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    displayName: "IMG_0001",
                    sourcePath: @"D:\other\IMG_0001.tif"),
            ];
            ExportSettings settings = new()
            {
                Format = DevelopExportFormat.Tiff16,
                FolderPath = root,
                NamingTemplate = ExportNamingTemplate.DefaultPattern,
            };

            IReadOnlyList<ExportBatchPlan> plans = ExportBatchCoordinator.Plan(frames, settings);
            Check(plans.Count == 3, "export_batch_plans_every_frame");
            Check(
                Path.GetFileName(plans[0].DestinationPath) == "IMG_0001.tif" &&
                Path.GetFileName(plans[1].DestinationPath) == "IMG_0002.tif" &&
                Path.GetFileName(plans[2].DestinationPath) == "IMG_0001-2.tif",
                "export_batch_separates_colliding_names");

            // 순번 패턴은 고른 순서를 따라 올라갑니다.
            IReadOnlyList<ExportBatchPlan> numbered = ExportBatchCoordinator.Plan(
                frames,
                settings with
                {
                    NamingTemplate = ExportNamingTemplate.SequenceOnlyPattern,
                    SequenceStart = 5,
                });
            Check(
                Path.GetFileName(numbered[0].DestinationPath) == "0005.tif" &&
                Path.GetFileName(numbered[2].DestinationPath) == "0007.tif",
                "export_batch_sequence_follows_the_selection_order");

            // 이미 있는 파일은 덮지 않습니다.
            File.WriteAllText(Path.Combine(root, "0005.tif"), string.Empty);
            IReadOnlyList<ExportBatchPlan> again = ExportBatchCoordinator.Plan(
                frames,
                settings with
                {
                    NamingTemplate = ExportNamingTemplate.SequenceOnlyPattern,
                    SequenceStart = 5,
                });
            Check(
                Path.GetFileName(again[0].DestinationPath) == "0005-2.tif",
                "export_batch_never_overwrites_an_existing_file");
        }
        finally
        {
            try
            {
                Directory.Delete(root, true);
            }
            catch (IOException)
            {
                // 시험 뒤처리 실패는 시험 결과가 아닙니다.
            }
        }
    }

    /// <summary>
    /// 묶음의 왕복입니다. 카탈로그에 없는 frame id 는 담기지 않아야 하고, 이름이 비면 만들지
    /// 않아야 하며, 저장하고 다시 열었을 때 그대로 있어야 합니다.
    /// </summary>
}
