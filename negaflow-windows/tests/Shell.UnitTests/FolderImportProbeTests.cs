using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 가져오기 관문은 새로 들어올 파일만 엽니다. 켤 때 등록 폴더를 다시 훑으며 이미 가져온 RAW/TIFF 를
/// 전부 다시 열어 첫 화면이 2 초 넘게 늦던 자리입니다.
/// </summary>
internal static class FolderImportProbeTests
{
    public static void Run()
    {
        string folder = Path.Combine(Path.GetTempPath(), $"negaflow-folder-probe-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        try
        {
            string imported = Path.Combine(folder, "a.tif");
            string attachedInfrared = Path.Combine(folder, "a_ir.tif");
            string added = Path.Combine(folder, "b.tif");
            foreach (string path in new[] { imported, attachedInfrared, added })
            {
                File.WriteAllBytes(path, [0]);
            }
            LibraryFrameSnapshot existing = Frame(null) with
            {
                Id = "folder-probe-existing",
                SourcePath = imported,
                InfraredPath = attachedInfrared,
            };
            List<string> probed = [];
            LibrarySourceMetadata? Reader(string path)
            {
                probed.Add(path);
                return new LibrarySourceMetadata(1UL, 10U, 10U, 3, 16, 1, 1);
            }

            FolderImportPlan plan = FolderImport.Plan(
                [folder],
                [existing],
                DevelopmentProcess.C41,
                sourceMetadataReader: Reader);
            Check(
                probed.SequenceEqual([added], StringComparer.OrdinalIgnoreCase) &&
                plan.Rejected.Count == 0 &&
                plan.Frames.Rows.Count == 1 &&
                plan.Frames.Rejected.Any(rejection =>
                    rejection.Refusal == FrameImportRefusal.AlreadyInLibrary &&
                    string.Equals(rejection.Path, imported, StringComparison.OrdinalIgnoreCase)),
                "folder_import_probes_only_files_not_in_library");

            probed.Clear();
            FolderImportPlan unchanged = FolderImport.Plan(
                [folder],
                [existing, existing with { Id = "folder-probe-b", SourcePath = added }],
                DevelopmentProcess.C41,
                sourceMetadataReader: Reader);
            Check(
                probed.Count == 0 && unchanged.Rejected.Count == 0 &&
                unchanged.Frames.Rows.Count == 0,
                "folder_import_rescan_of_known_folder_opens_nothing");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }
}
