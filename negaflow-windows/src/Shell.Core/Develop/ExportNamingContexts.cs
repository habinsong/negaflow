using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 파일명 토큰을 채울 값을 한 곳에서 모읍니다. 한 장 내보내기와 배치가 같은 규칙을 써야
/// 같은 사진이 경로에 따라 다른 이름으로 나가지 않습니다.
/// </summary>
public static class ExportNamingContexts
{
    /// <summary>
    /// 롤 값은 frame 값이 비어 있을 때만 씁니다. macOS 의 롤 기록도 <b>비어 있는 칸만</b>
    /// 채웁니다 — 롤 중간에 렌즈나 필름을 바꾸는 일이 실제로 있기 때문입니다.
    /// </summary>
    public static ExportNamingContext For(
        LibraryFrameSnapshot frame,
        LibraryRollSnapshot? roll,
        int sequence)
    {
        ArgumentNullException.ThrowIfNull(frame);
        FilmShotMetadata? frameShot = frame.AppMetadata?.FilmShot;
        FilmShotMetadata? rollShot = roll?.Record?.Shot;
        return new ExportNamingContext(
            string.Empty,
            frame.LookPresetId ?? string.Empty,
            sequence)
        {
            Roll = roll?.Name ?? string.Empty,
            RollCode = roll?.Record?.Code ?? string.Empty,
            Film = frameShot?.FilmStock ?? rollShot?.FilmStock ?? string.Empty,
            Camera = frameShot?.CameraModel ?? rollShot?.CameraModel ?? string.Empty,
        };
    }
}
