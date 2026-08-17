using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 스캔 가져오기의 기본 회전입니다. 회전이 없을 때 catalog 에 아무것도 적지 않는 것과,
/// 골랐을 때 <c>imageTransform.rotation</c> 으로 왕복하는 것을 함께 확인합니다.
/// </summary>
internal static class ScanRotationDefaultTests
{
    public static void Run()
    {
        VerifyDefaultScanRotation();
    }

    private static void VerifyDefaultScanRotation()
    {
        string root = Path.Combine(AppContext.BaseDirectory, "scan-rotation-tests");
        string folder = Path.Combine(root, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(folder);
            string scan = Path.Combine(folder, "scan.tif");
            File.WriteAllBytes(scan, [1, 2, 3, 4]);

            // 회전이 없으면 params 에 imageTransform 이 아예 없어야 합니다 — 이 기능이 없던
            // 때와 바이트 단위로 같은 record 입니다.
            FrameImportPlan plain = FrameImport.PlanScanner(
                new ScannerFrameImport(scan, null, DevelopmentProcess.C41), []);
            Check(plain.Rows.Count == 1, "scan_rotation_plain_plan");
            // develop route 가 뒤이어 params 에 자기 값을 적으므로 빈 사전은 아닙니다.
            // 없어야 하는 것은 imageTransform 입니다.
            Check(
                plain.Rows[0].Payload["params"] is JsonObject none &&
                    !none.ContainsKey("imageTransform"),
                "scan_rotation_none_writes_nothing");

            // 90도를 고르면 imageTransform.rotation 에 적힙니다.
            FrameImportPlan turned = FrameImport.PlanScanner(
                new ScannerFrameImport(scan, null, DevelopmentProcess.C41)
                {
                    Rotation = ImageRotation.Degrees90,
                },
                []);
            Check(
                turned.Rows[0].Payload["params"]?["imageTransform"]?["rotation"]
                    ?.GetValue<int>() == (int)ImageRotation.Degrees90,
                "scan_rotation_is_written_under_image_transform");

            // 그리고 reader 가 그것을 되읽어야 합니다 — 적히기만 하고 안 읽히면 소용없습니다.
            using JsonDocument document = JsonDocument.Parse(
                CatalogJson.SerializeCanonical(turned.Rows[0].Payload));
            Check(
                LibraryFrameReader.Read(document.RootElement).Frame?.ImageTransform.Rotation ==
                    ImageRotation.Degrees90,
                "scan_rotation_round_trips_through_the_reader");
        }
        finally
        {
            if (Directory.Exists(folder) && StoragePathPolicy.IsLexicallyContained(root, folder))
            {
                Directory.Delete(folder, recursive: true);
            }
        }
    }
}
