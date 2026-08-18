using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeFilmBasePickV1
{
    internal uint StructSize;
    internal uint Status;
    internal float Red;
    internal float Green;
    internal float Blue;
}

/// <summary>필름 베이스 스포이드의 결과입니다.</summary>
public enum FilmBasePickOutcome
{
    /// <summary>클릭한 자리의 Dmin 을 얻었습니다.</summary>
    Picked,

    /// <summary>원본을 읽지 못했습니다.</summary>
    SourceUnavailable,

    /// <summary>
    /// 그 자리는 필름 베이스가 아닙니다 — 필름 밖 검정 띠·빈 베드·장면 한복판입니다.
    /// </summary>
    /// <remarks>
    /// macOS <c>FilmBasePicker.isPlausibleBase</c> 가 nil 을 내는 자리입니다. 그 값을 Dmin 으로
    /// 앉히면 반전이 전 구간 클리핑되어 사진이 통째로 검게 죽으므로, 호출부는 Dmin 을
    /// <b>바꾸지 않고</b> 사용자에게 다시 집으라고 알립니다.
    /// </remarks>
    NotFilmBase,
}

/// <summary>사용자가 캔버스에서 집은 필름 베이스입니다.</summary>
public readonly record struct FilmBasePick(
    FilmBasePickOutcome Outcome,
    double Red,
    double Green,
    double Blue)
{
    /// <summary>
    /// macOS <c>AppModel.pickFilmBase</c> 와 같은 자리입니다 — 원본을 읽어 표시 정규 좌표
    /// <paramref name="unitX"/>/<paramref name="unitY"/>(0…1, y 아래로) 의 Dmin 을 냅니다.
    /// </summary>
    public static unsafe FilmBasePick Sample(
        string sourcePath,
        double unitX,
        double unitY,
        bool monochrome)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        NativeFilmBasePickV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeFilmBasePickV1);
        uint status = NativeMethods.nf_pick_film_base_v1(
            sourcePath,
            unitX,
            unitY,
            monochrome ? 1U : 0U,
            &raw);
        if (status != 0U)
        {
            return new FilmBasePick(FilmBasePickOutcome.SourceUnavailable, 0.0, 0.0, 0.0);
        }
        return raw.Status switch
        {
            0U => new FilmBasePick(
                FilmBasePickOutcome.Picked,
                raw.Red,
                raw.Green,
                raw.Blue),
            2U => new FilmBasePick(FilmBasePickOutcome.NotFilmBase, 0.0, 0.0, 0.0),
            _ => new FilmBasePick(FilmBasePickOutcome.SourceUnavailable, 0.0, 0.0, 0.0),
        };
    }
}
