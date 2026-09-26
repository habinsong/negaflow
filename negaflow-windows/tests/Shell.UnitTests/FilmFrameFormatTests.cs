using Negaflow.Interop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 필름 프레임 규격 12종의 치수를 macOS 값으로 못 박습니다.
/// </summary>
/// <remarks>
/// <para>
/// 이 숫자들은 평판 스캔의 **프레임 찾기 결과와 최종 본 스캔 영역**을 직접 정합니다.
/// 한 값이 틀리면 그 규격만 컷이 잘리거나 여백이 남는데, 화면을 보기 전에는 드러나지
/// 않고 빌드도 시험도 통과합니다. 그래서 표로 고정합니다.
/// </para>
/// <para>
/// 기준: macOS <c>Sources/Chromabase/Imaging/FlatbedFrameDetector.swift</c> 의
/// <c>FilmFrameFormat.stripWidthMM</c> · <c>stripHeightMM</c> · <c>is35mm</c>. 값을 바꿔야 하면
/// **맥을 먼저 고치고** 그 값을 여기로 옮깁니다.
/// </para>
/// </remarks>
internal static class FilmFrameFormatTests
{
    public static void Run()
    {
        VerifyMacosDimensions();
        VerifyFormatListMatchesMacos();
    }

    /// <summary>
    /// macOS <c>FilmFrameFormat.allCases</c> 차례 그대로의 <c>stripWidthMM</c> ·
    /// <c>stripHeightMM</c> · <c>is35mm</c> · <c>displayName</c> 표입니다. 파노라마 두 규격은
    /// 35mm 하프 다음입니다.
    /// </summary>
    private static readonly (FlatbedFrameFormat Format, double Width, double Height, bool Is35mm,
        string Name, string Display)[] MacosDimensions =
        [
            (FlatbedFrameFormat.FullFrame35mm, 36.0, 24.0, true, "full_frame_35mm", "35 mm · 36 × 24"),
            (FlatbedFrameFormat.Square35mm, 24.0, 24.0, true, "square_35mm", "35 mm · 24 × 24"),
            (FlatbedFrameFormat.HalfFrame35mm, 18.0, 24.0, true, "half_frame_35mm", "35 mm · 24 × 18"),
            (FlatbedFrameFormat.Panorama35mm56x24, 56.0, 24.0, true, "panorama_35mm_56x24", "35 mm · 56 × 24"),
            (FlatbedFrameFormat.Panorama35mm65x24, 65.0, 24.0, true, "panorama_35mm_65x24", "35 mm · 65 × 24"),
            (FlatbedFrameFormat.Medium645, 41.5, 56.0, false, "medium_645", "120 · 6 × 4.5"),
            (FlatbedFrameFormat.Medium66, 56.0, 56.0, false, "medium_66", "120 · 6 × 6"),
            (FlatbedFrameFormat.Medium67, 69.0, 55.0, false, "medium_67", "120 · 6 × 7"),
            (FlatbedFrameFormat.Medium68, 76.0, 56.0, false, "medium_68", "120 · 6 × 8"),
            (FlatbedFrameFormat.Medium69, 84.0, 56.0, false, "medium_69", "120 · 6 × 9"),
            (FlatbedFrameFormat.Medium612, 112.0, 56.0, false, "medium_612", "120 · 6 × 12"),
            (FlatbedFrameFormat.Medium617, 168.0, 56.0, false, "medium_617", "120 · 6 × 17"),
        ];

    private static void VerifyMacosDimensions()
    {
        foreach ((FlatbedFrameFormat format, double width, double height, bool is35mm,
                string name, string display) in MacosDimensions)
        {
            Check(
                FilmFrameFormats.StripWidthMm(format) == width,
                $"strip_width_{name}");
            Check(
                FilmFrameFormats.StripHeightMm(format) == height,
                $"strip_height_{name}");
            // 35mm 여부는 enum 차례가 아닙니다 — 파노라마 두 규격은 번호로는 120 뒤입니다.
            Check(FilmFrameFormats.Is35mm(format) == is35mm, $"is_35mm_{name}");
            Check(FilmFrameFormats.DisplayName(format) == display, $"display_{name}");
            // 표기가 비어 있으면 고르개에 빈 줄이 섭니다.
            Check(
                !string.IsNullOrWhiteSpace(FilmFrameFormats.DisplayName(format)),
                $"display_name_{name}");
        }
    }

    /// <summary>
    /// macOS <c>FilmFrameFormat.allCases</c> 와 같은 열두 가지가 같은 순서로 있어야 합니다.
    /// 고르개의 순서가 곧 사용자가 보는 순서이고, 저장된 선택은 값으로 남으므로 하나만
    /// 빠져도 그 규격으로 저장된 롤을 다시 열 수 없습니다.
    /// </summary>
    private static void VerifyFormatListMatchesMacos()
    {
        Check(
            FilmFrameFormats.All.Count == MacosDimensions.Length,
            "frame_format_count_matches_macos");
        for (int index = 0; index < FilmFrameFormats.All.Count; ++index)
        {
            Check(
                FilmFrameFormats.All[index] == MacosDimensions[index].Format,
                $"frame_format_order_{index}");
        }

        // `_ => 56` 같은 기본 가지가 새 규격을 조용히 삼키지 않는지 봅니다. 열거형에 값을
        // 더하고 표를 안 고치면 여기서 걸립니다.
        foreach (FlatbedFrameFormat format in Enum.GetValues<FlatbedFrameFormat>())
        {
            Check(
                FilmFrameFormats.All.Contains(format),
                $"frame_format_enum_value_is_listed_{format}");
        }
        // 표에 없는 값은 조용히 36×24 가 되지 않고 던져야 합니다.
        bool refused = false;
        try
        {
            _ = FilmFrameFormats.Dimensions((FlatbedFrameFormat)12);
        }
        catch (ArgumentOutOfRangeException)
        {
            refused = true;
        }
        Check(refused, "frame_format_unknown_value_is_refused");
    }
}
