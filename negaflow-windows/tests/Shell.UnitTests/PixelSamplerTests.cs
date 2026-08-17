using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 픽셀 샘플러입니다. 좌표를 잘못 옮기면 사용자가 가리킨 곳이 아닌 화소의 값을 읽고,
/// 그것이 틀렸다는 것은 눈으로 알아채기 어렵습니다.
/// </summary>
internal static class PixelSamplerTests
{
    public static void Run()
    {
        VerifyPointerMapping();
        VerifyPixelReads();
        VerifyLabConversion();
    }

    private static void VerifyPointerMapping()
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
    }

    private static void VerifyPixelReads()
    {
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
    }

    private static void VerifyLabConversion()
    {
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
    }
}
