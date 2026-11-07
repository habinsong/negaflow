using System.IO;
using Negaflow.Catalog;
using Negaflow.Shell.Develop.Perspective;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 변환(원근) 보정입니다. macOS <c>PerspectiveCorrectionTests</c> · <c>PerspectiveControlsTests</c> 와
/// 같은 합성 격자를 씁니다 — 실제 사진은 쓰지 않습니다.
/// </summary>
internal static class PerspectiveTests
{
    private const int SourceWidth = 1200;
    private const int SourceHeight = 800;

    /// <summary>합성 사진에 걸어 둔 왜곡입니다. 풀이는 이것의 반대(−8, 5, −2)를 내야 합니다.</summary>
    private static readonly PerspectiveRecipe Distortion = PerspectiveRecipe.Identity with
    {
        Mode = PerspectiveMode.Full,
        SolvedVertical = 8,
        SolvedHorizontal = -5,
        SolvedRotate = 2,
    };

    public static void Run()
    {
        VerifyCorrectionKeepsThePhotoCentered();
        VerifyForwardAndInverseRoundTrip();
        VerifySolverRecoversASyntheticKeystone();
        VerifyAutoSolveIgnoresTheEmptyAreaOfAnAlreadyCorrectedPreview();
        VerifyPreviewCoverageIsOpaqueOnScreenAndSkippedByAnalysis();
        VerifyPickersRefuseTheUncoveredArea();
    }

    /// <summary>
    /// 프리뷰의 빈 곳은 흰색에 알파 0 으로 옵니다. 화면에는 불투명 흰색으로 쓰고(예전과 같은 모습),
    /// 히스토그램은 그 화소를 세지 않습니다. 불투명한 그림은 복사 없이 그대로입니다.
    /// </summary>
    private static void VerifyPreviewCoverageIsOpaqueOnScreenAndSkippedByAnalysis()
    {
        const int width = 37, height = 5;
        byte[] pixels = new byte[width * height * 4];
        for (int i = 0; i < pixels.Length; i += 4)
        {
            bool uncovered = (i / 4) % width >= 20;
            pixels[i] = uncovered ? (byte)255 : (byte)40;
            pixels[i + 1] = uncovered ? (byte)255 : (byte)60;
            pixels[i + 2] = uncovered ? (byte)255 : (byte)80;
            pixels[i + 3] = uncovered ? (byte)0 : (byte)255;
        }
        Check(PreviewCoverage.HasPartialCoverage(pixels), "coverage alpha is detected");
        Check(PreviewCoverage.IsCovered(pixels, width, 3, 2) && !PreviewCoverage.IsCovered(pixels, width, 30, 2),
            "covered and uncovered preview pixels are told apart");
        using var screen = new MemoryStream();
        PreviewCoverage.WriteOpaque(screen, pixels, pixels.Length);
        byte[] written = screen.ToArray();
        bool opaque = true, unchanged = true;
        for (int i = 0; i < written.Length; i += 4)
        {
            opaque &= written[i + 3] == 255;
            unchanged &= written[i] == pixels[i] && written[i + 1] == pixels[i + 1] && written[i + 2] == pixels[i + 2];
        }
        Check(opaque && unchanged, "the screen copy is opaque with the same colour (uncovered stays white)");
        Check(pixels[(30 + width) * 4 + 3] == 0, "the analysis buffer keeps its coverage");
        DevelopHistogramBins? bins = DevelopHistogramSampler.SampleBgra8(pixels, width, height);
        Check(bins is not null && bins.TotalPixels == 20 * height,
            "the histogram counts only covered pixels",
            () => $"total={bins?.TotalPixels}");

        byte[] solid = new byte[16 * 4];
        Array.Fill(solid, (byte)255);
        Check(!PreviewCoverage.HasPartialCoverage(solid), "an opaque preview has no coverage to handle");
    }

    /// <summary>스포이드는 빈 곳에서 가장자리 화소를 찍지 않습니다. 사진 위는 그대로 원본 좌표로 풉니다.</summary>
    private static void VerifyPickersRefuseTheUncoveredArea()
    {
        ImageTransformRecipe transform = ImageTransformRecipe.Identity with
        {
            Perspective = PerspectiveRecipe.Identity with { Mode = PerspectiveMode.Off, Vertical = 40 },
        };
        Check(!DevelopDisplayGeometry.TryMapDisplayToCoveredRaw(
                transform, 1500, 1000, 0.01, 0.99, out _, out _),
            "an uncovered corner is not a source pixel");
        Check(DevelopDisplayGeometry.TryMapDisplayToCoveredRaw(
                transform, 1500, 1000, 0.5, 0.5, out double rawX, out _) && Math.Abs(rawX - 0.5) < 1e-3,
            "the frame centre maps to the source centre");
        Check(DevelopDisplayGeometry.TryMapDisplayToRaw(transform, 1500, 1000, 0.01, 0.99, out _, out _),
            "the clamping mapping still answers for drawing tools");
        Check(DevelopDisplayGeometry.TryMapDisplayToCoveredRaw(
                ImageTransformRecipe.Identity with { StraightenAngle = 3 }, 1500, 1000, 0.0, 1.0, out _, out _),
            "without perspective the whole frame is source");
    }

    /// <summary>
    /// 카메라를 기울여도 그림 중심은 프레임 가운데에 남습니다. 예전에는 세로 15° 에서 중심이 높이의
    /// 24% 아래로 밀려 바로 세운 건물 꼭대기가 잘렸습니다.
    /// </summary>
    private static void VerifyCorrectionKeepsThePhotoCentered()
    {
        foreach (PerspectiveRecipe recipe in new[]
                 {
                     PerspectiveRecipe.Identity with { Mode = PerspectiveMode.Full, SolvedVertical = -15, SolvedHorizontal = 5 },
                     PerspectiveRecipe.Identity with { Mode = PerspectiveMode.Vertical, SolvedVertical = 20, Rotate = 3 },
                     PerspectiveRecipe.Identity with { Vertical = -60, Horizontal = 40 },
                 })
        {
            PerspectiveMapping? mapping = PerspectiveGeometry.Mapping(recipe, 2400, 1600);
            (double X, double Y)? center = mapping is null ? null : PerspectiveGeometry.Apply(mapping.Forward, 1200, 800);
            Check(
                center is { } c && Math.Abs(c.X - 1200) < 1e-6 && Math.Abs(c.Y - 800) < 1e-6,
                "perspective_keeps_photo_center",
                () => $"center={center}");
        }
    }

    private static void VerifyForwardAndInverseRoundTrip()
    {
        PerspectiveMapping? mapping = PerspectiveGeometry.Mapping(Distortion, SourceWidth, SourceHeight);
        bool ok = mapping is not null;
        foreach ((double x, double y) in new[] { (0.0, 0.0), (1200.0, 0.0), (1200.0, 800.0), (0.0, 800.0), (333.0, 517.0) })
        {
            if (mapping is null ||
                PerspectiveGeometry.Apply(mapping.Forward, x, y) is not { } forward ||
                PerspectiveGeometry.Apply(mapping.Inverse, forward.X, forward.Y) is not { } back)
            {
                ok = false;
                continue;
            }
            ok &= Math.Abs(back.X - x) < 1e-6 && Math.Abs(back.Y - y) < 1e-6;
        }
        Check(ok, "perspective_forward_inverse_round_trip");
    }

    /// <summary>격자 선분을 왜곡해 넘기면 전체 모드가 왜곡의 반대를 찾습니다(macOS 와 같은 허용치).</summary>
    private static void VerifySolverRecoversASyntheticKeystone()
    {
        double[] camera = CameraTilt(Distortion, inverse: false);
        List<PerspectiveLineSegment> segments = [];
        for (double x = 70; x < SourceWidth; x += 110)
        {
            AddWarped(segments, camera, x, 40, x, SourceHeight - 40);
        }
        for (double y = 70; y < SourceHeight; y += 110)
        {
            AddWarped(segments, camera, 40, y, SourceWidth - 40, y);
        }
        PerspectiveSolution? solution = PerspectiveSolver.Solve(PerspectiveMode.Full, segments, SourceWidth, SourceHeight);
        Check(
            solution is { } s && Math.Abs(s.Vertical + 8) < 0.8 && Math.Abs(s.Horizontal - 5) < 0.8 &&
                Math.Abs(s.Rotate + 2) < 0.4,
            "perspective_full_mode_recovers_keystone",
            () => $"solution={solution}");
    }

    /// <summary>
    /// 이미 보정이 걸린 미리보기에는 원본 바깥의 흰 영역이 있고, 그 경계는 원본 테두리(완벽한
    /// 수직·수평선)로 되돌아갑니다. 예전에는 그 선이 풀이를 "보정 0" 쪽으로 끌어 수직·전체 모드가
    /// 거의 펴지지 않았습니다. 어떤 보정이 걸린 화면에서 풀어도 같은 답이 나와야 합니다.
    /// </summary>
    private static void VerifyAutoSolveIgnoresTheEmptyAreaOfAnAlreadyCorrectedPreview()
    {
        double[] distortion = CameraTilt(Distortion, inverse: true);
        foreach (PerspectiveRecipe shown in new[]
                 {
                     PerspectiveRecipe.Identity,
                     PerspectiveRecipe.Identity with { Mode = PerspectiveMode.Level, SolvedRotate = -2 },
                     PerspectiveRecipe.Identity with { Mode = PerspectiveMode.Auto, SolvedVertical = -5, SolvedHorizontal = 3, SolvedRotate = -2 },
                 })
        {
            ImageTransformRecipe transform = ImageTransformRecipe.Identity with { Perspective = shown };
            (byte[] bgra, int width, int height) = RenderPreview(transform, distortion);
            PerspectiveSolution? solution = PerspectiveWorkflow.SolveFromDisplay(
                bgra, width, height, transform, SourceWidth, SourceHeight, PerspectiveMode.Full);
            Check(
                solution is { } s && Math.Abs(s.Vertical + 8) < 0.8 && Math.Abs(s.Horizontal - 5) < 0.8 &&
                    Math.Abs(s.Rotate + 2) < 0.4,
                "perspective_auto_solve_from_corrected_preview",
                () => $"shown={shown.SolvedVertical},{shown.SolvedHorizontal},{shown.SolvedRotate} solution={solution}");
        }
    }

    /// <summary>
    /// 실제 카메라를 기울인 것과 같은 왜곡(픽셀 → 픽셀)입니다. 보정 식과 달리 중심을 되돌리지 않습니다 —
    /// 실제 사진의 원근은 이미지 중심을 주점으로 한 순수 회전이고, 풀이도 그 모형을 씁니다.
    /// </summary>
    private static double[] CameraTilt(PerspectiveRecipe c, bool inverse)
    {
        double w = SourceWidth, h = SourceHeight, s = Math.Max(w, h) / 2, f = PerspectiveGeometry.FocalLength;
        (double wx, double wy, double wz) = PerspectiveGeometry.RotationVector(c);
        double sign = inverse ? -1 : 1;
        double[] r = PerspectiveGeometry.RotationMatrix(sign * wx, sign * wy, sign * wz);
        double[] toNormal = [1 / s, 0, -w / 2 / s, 0, 1 / s, -h / 2 / s, 0, 0, 1];
        double[] toPixel = [s, 0, w / 2, 0, s, h / 2, 0, 0, 1];
        double[] k = [f, 0, 0, 0, f, 0, 0, 0, 1];
        double[] kInverse = [1 / f, 0, 0, 0, 1 / f, 0, 0, 0, 1];
        return Multiply(Multiply(Multiply(Multiply(toPixel, k), r), kInverse), toNormal);
    }

    private static double[] Multiply(double[] a, double[] b)
    {
        double[] m = new double[9];
        for (int row = 0; row < 3; ++row)
        {
            for (int column = 0; column < 3; ++column)
            {
                m[(row * 3) + column] = (a[row * 3] * b[column]) + (a[(row * 3) + 1] * b[3 + column]) +
                    (a[(row * 3) + 2] * b[6 + column]);
            }
        }
        return m;
    }

    private static void AddWarped(
        List<PerspectiveLineSegment> segments, double[] camera, double x0, double y0, double x1, double y1)
    {
        (double X, double Y) a = PerspectiveGeometry.Apply(camera, x0, y0)!.Value;
        (double X, double Y) b = PerspectiveGeometry.Apply(camera, x1, y1)!.Value;
        double length = Math.Sqrt(((b.X - a.X) * (b.X - a.X)) + ((b.Y - a.Y) * (b.Y - a.Y)));
        segments.Add(new PerspectiveLineSegment(
            a.X / SourceWidth, a.Y / SourceHeight, b.X / SourceWidth, b.Y / SourceHeight, length));
    }

    /// <summary>
    /// <paramref name="transform"/> 을 건 미리보기(BGRA8)입니다. 원본은 격자를 <paramref name="distortion"/>
    /// 으로 일그러뜨린 사진이고, 원본 바깥은 엔진처럼 흰색입니다.
    /// </summary>
    private static (byte[] Pixels, int Width, int Height) RenderPreview(
        ImageTransformRecipe transform, double[] distortion)
    {
        DevelopDisplayGeometry.TryDevelopedPixelSize(
            transform, SourceWidth, SourceHeight, out double outWidth, out double outHeight);
        int width = (int)outWidth, height = (int)outHeight;
        byte[] pixels = new byte[width * height * 4];
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                byte value = 255;
                double dx = (double)x / (width - 1), dy = (double)y / (height - 1);
                if (DevelopDisplayGeometry.TryMapDisplayToRaw(
                        transform, SourceWidth, SourceHeight, dx, dy, out double rawX, out double rawY) &&
                    DevelopDisplayGeometry.TryMapRawToDisplay(
                        transform, SourceWidth, SourceHeight, rawX, rawY, out double backX, out double backY) &&
                    Math.Abs(backX - dx) < 0.5 / width && Math.Abs(backY - dy) < 0.5 / height)
                {
                    // 사진 안쪽입니다. 격자 바깥은 회색(macOS 시험과 같음), 원본 바깥만 흰색입니다.
                    value = 128;
                    if (PerspectiveGeometry.Apply(
                            distortion, (rawX * (SourceWidth - 1)) + 0.5, (rawY * (SourceHeight - 1)) + 0.5)
                            is { } s && s.X >= 0 && s.Y >= 0 && s.X < SourceWidth && s.Y < SourceHeight)
                    {
                        bool onLine = ((s.X + 40) % 110) < 8 || ((s.Y + 40) % 110) < 8;
                        value = onLine ? (byte)40 : (byte)220;
                    }
                }
                int i = ((y * width) + x) * 4;
                pixels[i] = value;
                pixels[i + 1] = value;
                pixels[i + 2] = value;
                pixels[i + 3] = 255;
            }
        }
        return (pixels, width, height);
    }
}
