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

internal static class ScanImageTests
{
    public static void Run()
    {
        VerifyDefaultScanRotation();
        VerifyPixelSampler();
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


    /// <summary>
    /// 픽셀 샘플러입니다. 좌표를 잘못 옮기면 사용자가 가리킨 곳이 아닌 화소의 값을 읽고,
    /// 그것이 틀렸다는 것은 눈으로 알아채기 어렵습니다.
    /// </summary>
    private static void VerifyPixelSampler()
    {
        // 캔버스 400×300 안에 200×100 사진: 배율 2, 위아래 여백 50.
        Check(
            PixelSampler.ToSourceCoordinate(100, 150, 400, 300, 200, 100) ==
                new PixelCoordinate(50, 50),
            "sampler_maps_the_pointer_through_the_fit_scale");
        // 사진 위쪽 여백은 사진이 아닙니다.
        Check(
            PixelSampler.ToSourceCoordinate(100, 10, 400, 300, 200, 100) is null,
            "sampler_refuses_the_letterbox");
        Check(
            PixelSampler.ToSourceCoordinate(-5, 150, 400, 300, 200, 100) is null,
            "sampler_refuses_outside_the_canvas");
        Check(
            PixelSampler.ToSourceCoordinate(100, 150, 0, 300, 200, 100) is null,
            "sampler_refuses_an_empty_canvas");

        // BGRA 순서를 잘못 읽으면 빨강과 파랑이 뒤바뀝니다.
        byte[] pixels = [10, 20, 30, 255, 40, 50, 60, 255];
        Check(
            PixelSampler.Read(pixels, 2, 1, 0, 0) == new PixelColorReading(30, 20, 10),
            "sampler_reads_bgra_order");
        Check(
            PixelSampler.Read(pixels, 2, 1, 1, 0) == new PixelColorReading(60, 50, 40),
            "sampler_reads_the_second_pixel");
        Check(
            PixelSampler.Read(pixels, 2, 1, 2, 0) is null,
            "sampler_refuses_a_pixel_past_the_row");

        // Lab: 흰색은 L=100, 검정은 L=0, 중성은 a·b 가 0 입니다.
        (double whiteL, double whiteA, double whiteB) =
            new PixelColorReading(255, 255, 255).Lab;
        Check(
            Math.Abs(whiteL - 100) < 0.1 && Math.Abs(whiteA) < 0.1 && Math.Abs(whiteB) < 0.1,
            "sampler_lab_white_is_one_hundred");
        Check(Math.Abs(new PixelColorReading(0, 0, 0).Lab.L) < 0.1, "sampler_lab_black_is_zero");
        (_, double greyA, double greyB) = new PixelColorReading(128, 128, 128).Lab;
        Check(
            Math.Abs(greyA) < 0.1 && Math.Abs(greyB) < 0.1,
            "sampler_lab_neutral_has_no_chroma");
        // 빨강은 a 가 크게 양수여야 합니다 — 부호가 뒤집히면 색을 반대로 읽습니다.
        Check(new PixelColorReading(255, 0, 0).Lab.A > 50, "sampler_lab_red_is_positive_a");

        // 언어 목록은 리소스가 있는 것만 냅니다.
        Check(AppLanguages.All.Count == 7, "language_list_has_system_plus_six");
        Check(AppLanguages.All[0] == AppLanguages.System, "language_system_comes_first");
        Check(
            AppLanguages.Normalize("ko-KR") == "ko-KR" &&
                AppLanguages.Normalize("KO-kr") == "KO-kr",
            "language_accepts_a_known_tag");
        // 리소스가 없는 언어를 고르면 화면이 영어로 돌아갑니다 — 시스템으로 되돌립니다.
        Check(
            AppLanguages.Normalize("es-ES") == AppLanguages.System &&
                AppLanguages.Normalize(null) == AppLanguages.System,
            "language_unknown_falls_back_to_system");
    }

}
