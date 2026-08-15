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
        int sequence,
        DateTimeOffset? exportedAt = null)
    {
        ArgumentNullException.ThrowIfNull(frame);
        FilmShotMetadata? frameShot = frame.AppMetadata?.FilmShot;
        FilmShotMetadata? rollShot = roll?.Record?.Shot;
        // {name} 은 **카드에 보이는 이름**입니다. 원본 파일 이름을 쓰면 macOS 와 다른 파일이
        // 나옵니다 — 같은 사진을 두 앱에서 내보내면 이름이 갈립니다.
        string frameName = LibraryFrameNaming.DisplayName(frame);
        return new ExportNamingContext(
            frameName,
            frame.LookPresetId ?? string.Empty,
            sequence)
        {
            FrameIndex = frame.PresentationIndex,
            Date = exportedAt ?? DateTimeOffset.Now,
            Roll = roll?.Name ?? string.Empty,
            RollCode = roll?.Record?.Code ?? string.Empty,
            Film = frameShot?.FilmStock ?? rollShot?.FilmStock ?? string.Empty,
            Camera = frameShot?.CameraModel ?? rollShot?.CameraModel ?? string.Empty,
        };
    }
}
