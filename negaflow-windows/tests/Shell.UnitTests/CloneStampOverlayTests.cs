using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// macOS <c>CloneStampOverlay.draw</c> 의 이식입니다. 요점은 <b>원 안과 획 안에 소스 화소가
/// 실제로 온다</b>는 것입니다 — 테두리만 그리면 어디를 복제하는지 보지 못한 채 칠합니다.
/// </summary>
internal static class CloneStampOverlayTests
{
    /// <summary>표시 크기입니다. 홀수라 가운데 화소가 하나로 떨어집니다.</summary>
    private const int Width = 41;

    private const int Height = 31;

    /// <summary>커서 원의 지름(표시 화소). 반지름 4.5 라 테두리 띠가 3.25~5.75 입니다.</summary>
    private const double Diameter = 9.0;

    /// <summary>
    /// 투명한 자리에 테두리·십자선만 얹었을 때의 알파 하한입니다. macOS 도 source-over 라
    /// 아래가 비어 있으면 불투명해지지 않습니다 — 테두리는 0.55 위에 0.9 라 244, 십자선은
    /// 0.65 위에 0.95 라 251 입니다.
    /// </summary>
    private const byte Translucent = 200;

    public static void Run()
    {
        VerifyOptionDownDrawsOnlyCrosshairs();
        VerifyRingShowsTheSourcePixels();
        VerifyStrokeShowsTheSourceWindow();
        VerifyAlignedOffsetWins();
        VerifyDiscShapeMatchesTheDistanceTest();
    }

    /// <summary>
    /// 원 안 미리보기가 칠하는 화소 집합이 <c>dx² + dy² ≤ r²</c> 그대로인지 봅니다. 모양을
    /// 그대로 두고 속도만 올린 자리라(행 단위 채우기), 한 눈금이라도 어긋나면 여기서 드러납니다.
    /// </summary>
    private static void VerifyDiscShapeMatchesTheDistanceTest()
    {
        const int centerX = 20;
        const int centerY = 15;
        // 소스 마커를 구석으로 보내 십자선이 원에 닿지 않게 합니다. 오프셋은 정렬 값으로 주므로
        // 원 안에 오는 화소는 그대로 −10 만큼 옮긴 것입니다.
        DefectPoint corner = new(0.02, 0.9);
        DefectPoint aligned = new(-0.25, 0.0);
        byte[] reference = Reference();
        bool matches = true;
        foreach (double diameter in new[] { 3.0, 8.0, 9.0, 13.0 })
        {
            byte[]? bgra = CloneStampCursorRenderer.Render(
                FrameUnderTest(), Width, Height, reference, Cursor, [], corner, aligned,
                diameter, optionDown: false);
            double radius = diameter / 2.0;
            // 테두리 띠(안쪽 반지름 r − 1.25)는 색을 바꾸므로 그 안쪽만 셉니다.
            double inside = Math.Max(0.0, radius - (2.5 / 2.0));
            for (int y = 0; y < Height; ++y)
            {
                for (int x = 0; x < Width; ++x)
                {
                    double distance = ((x - centerX) * (x - centerX)) +
                        ((y - centerY) * (y - centerY));
                    if (bgra is null || distance >= inside * inside)
                    {
                        continue;
                    }
                    bool copied = Alpha(bgra, x, y) == 255 &&
                        Blue(bgra, x, y) == (byte)(x - 10) && Green(bgra, x, y) == (byte)y;
                    if (copied != (distance <= radius * radius))
                    {
                        matches = false;
                    }
                }
            }
        }
        Check(matches, "clone_cursor_disc_matches_the_distance_test");
    }

    /// <summary>
    /// macOS: <c>if optionDown { source 와 cursor 에 십자선만; return }</c>. 원은 그리지 않습니다.
    /// </summary>
    private static void VerifyOptionDownDrawsOnlyCrosshairs()
    {
        byte[]? bgra = Render(Reference(), Cursor, [], Source, null, optionDown: true);
        Check(bgra is not null, "clone_cursor_option_down_draws_something");
        // 커서와 소스 자리에 십자선이 옵니다.
        Check(bgra is not null && Alpha(bgra, 20, 15) > 0 && Alpha(bgra, 10, 15) > 0,
            "clone_cursor_option_down_marks_cursor_and_source");
        // 테두리 띠 위이면서 십자선 팔은 아닌 자리입니다. 원을 그렸다면 여기가 칠해집니다.
        Check(bgra is not null && Alpha(bgra, 23, 18) == 0,
            "clone_cursor_option_down_draws_no_ring");
    }

    /// <summary>
    /// macOS: 원 안에 복제될 소스 픽셀 미리보기 → 그 위에 검정 0.55 와 흰 0.9 테두리.
    /// 소스를 지정하기 전이나 기준 이미지가 없으면 미리보기는 없습니다.
    /// </summary>
    private static void VerifyRingShowsTheSourcePixels()
    {
        byte[] reference = Reference();
        byte[]? bgra = Render(reference, Cursor, [], Source, null, optionDown: false);
        // 커서 (20,15) 에는 소스 (10,15) 의 화소가 불투명하게 옵니다.
        Check(bgra is not null && Alpha(bgra, 20, 15) == 255 &&
            Blue(bgra, 20, 15) == 10 && Green(bgra, 20, 15) == 15 && Red(bgra, 20, 15) == 0,
            "clone_cursor_ring_shows_the_offset_source_pixel");
        // 테두리는 그 불투명한 미리보기 <b>위에</b> 얹힙니다. 더 진한 쪽만 남기면 사라집니다.
        Check(bgra is not null && Alpha(bgra, 23, 18) == 255 && Red(bgra, 23, 18) > 200,
            "clone_cursor_ring_border_survives_over_the_preview");
        // 소스 자리에는 십자선이 섭니다(획 중이 아니므로 지정된 소스에).
        Check(bgra is not null && Alpha(bgra, 10, 15) > Translucent && Red(bgra, 10, 15) > 200,
            "clone_cursor_marks_the_designated_source");

        // 소스를 지정하기 전에는 미리보기가 없습니다 — macOS `sourceBase == nil`.
        byte[]? noSource = Render(reference, Cursor, [], null, null, optionDown: false);
        Check(noSource is not null && Alpha(noSource, 20, 15) == 0 &&
            Alpha(noSource, 23, 18) > Translucent,
            "clone_cursor_without_a_source_draws_the_ring_only");

        // 기준 이미지가 없어도 테두리와 십자선은 그대로 나옵니다.
        byte[]? noReference = Render(null, Cursor, [], Source, null, optionDown: false);
        Check(noReference is not null && Alpha(noReference, 20, 15) == 0 &&
            Alpha(noReference, 23, 18) > Translucent && Alpha(noReference, 10, 15) > Translucent,
            "clone_cursor_without_a_reference_image_still_draws_the_ring");
    }

    /// <summary>
    /// macOS: 진행 중 스트로크는 소스 창의 실제 픽셀을 스트로크 모양으로 보여 주고, 십자 마커가
    /// 샘플 위치를 따라갑니다. 오프셋은 <b>첫 점</b> 기준으로 고정됩니다.
    /// </summary>
    private static void VerifyStrokeShowsTheSourceWindow()
    {
        byte[] reference = Reference();
        DefectPoint[] stroke = [Cursor, new DefectPoint(0.6, 0.5)];
        byte[]? bgra = Render(reference, stroke[^1], stroke, Source, null, optionDown: false);

        // (18,12) 는 획 모양 안이지만 커서 원 밖이고 십자선 팔도 아닙니다 — 획 경로가 칠하지
        // 않으면 비어 있는 자리입니다.
        Check(bgra is not null && Alpha(bgra, 18, 12) == 255 &&
            Blue(bgra, 18, 12) == 8 && Green(bgra, 18, 12) == 12,
            "clone_stroke_fills_the_stroke_shape_with_source_pixels");

        // 십자선이 샘플 위치(마지막 점 + 오프셋 = 24−10 = 14)로 따라갑니다.
        Check(bgra is not null && Alpha(bgra, 14, 15) > Translucent && Red(bgra, 14, 15) > 200,
            "clone_stroke_crosshair_follows_the_sample_position");

        // 획이 없으면 그 자리는 아무것도 아닙니다 — 위 값이 획 때문임을 못박습니다.
        byte[]? idle = Render(reference, stroke[^1], [], Source, null, optionDown: false);
        Check(idle is not null && Alpha(idle, 18, 12) == 0,
            "clone_stroke_shape_is_drawn_only_while_dragging");
    }

    /// <summary>
    /// macOS <c>displayOffset</c>: 정렬 오프셋이 있으면 그것을 쓰고, 없을 때에만 소스−기준점을
    /// 씁니다. 첫 획 뒤에는 소스가 브러시를 따라 움직입니다.
    /// </summary>
    private static void VerifyAlignedOffsetWins()
    {
        // 원본 정규 +0.25 는 표시 화소로 +10 입니다(변형 없음, 폭 41).
        byte[]? bgra = Render(
            Reference(),
            Cursor,
            [],
            Source,
            new DefectPoint(0.25, 0.0),
            optionDown: false);
        Check(bgra is not null && Blue(bgra, 20, 15) == 30 && Green(bgra, 20, 15) == 15,
            "clone_cursor_uses_the_aligned_offset_over_the_source_anchor");
    }

    /// <summary>커서는 가운데(표시 화소 20,15), 소스는 그 왼쪽 10 화소입니다.</summary>
    private static DefectPoint Cursor => new(0.5, 0.5);

    private static DefectPoint Source => new(0.25, 0.5);

    /// <summary>
    /// 화소마다 자기 자리를 적어 둔 기준 이미지입니다 — 어느 화소가 어디로 옮겨졌는지 값으로
    /// 확인할 수 있습니다. 빨강은 0 이라 흰 테두리와 섞이지 않습니다.
    /// </summary>
    private static byte[] Reference()
    {
        byte[] reference = new byte[Width * Height * 4];
        for (int y = 0; y < Height; ++y)
        {
            for (int x = 0; x < Width; ++x)
            {
                int index = ((y * Width) + x) * 4;
                reference[index] = (byte)x;
                reference[index + 1] = (byte)y;
                reference[index + 2] = 0;
                reference[index + 3] = 255;
            }
        }
        return reference;
    }

    /// <summary>변형이 없는 100×80 원본입니다 — 표시 정규가 곧 원본 정규입니다.</summary>
    private static LibraryFrameSnapshot FrameUnderTest() =>
        Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            SourceMetadata = new LibrarySourceMetadata(1024UL, 100U, 80U, 3, 16, 1, 1),
        };

    private static byte[]? Render(
        byte[]? reference,
        DefectPoint? cursor,
        IReadOnlyList<DefectPoint> stroke,
        DefectPoint? source,
        DefectPoint? alignedRawOffset,
        bool optionDown) =>
        CloneStampCursorRenderer.Render(
            FrameUnderTest(),
            Width,
            Height,
            reference,
            cursor,
            stroke,
            source,
            alignedRawOffset,
            Diameter,
            optionDown);

    private static byte Blue(byte[] bgra, int x, int y) => bgra[(((y * Width) + x) * 4) + 0];

    private static byte Green(byte[] bgra, int x, int y) => bgra[(((y * Width) + x) * 4) + 1];

    private static byte Red(byte[] bgra, int x, int y) => bgra[(((y * Width) + x) * 4) + 2];

    private static byte Alpha(byte[] bgra, int x, int y) => bgra[(((y * Width) + x) * 4) + 3];
}
