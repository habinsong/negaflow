namespace Negaflow.Shell;

/// <summary>
/// 라이브러리를 연 뒤 알리는 결과입니다. macOS <c>restoreLibraryOnLaunch</c> 가 상태 메시지로 띄우는
/// 네 갈래와 같습니다.
/// </summary>
public enum LibraryOpenOutcome
{
    /// <summary>"라이브러리 복원: 사진 N장"</summary>
    Restored,

    /// <summary>예약한 백업을 적용했습니다. "선택한 라이브러리 백업 복원: 사진 N장"</summary>
    SelectedBackupApplied,

    /// <summary>어긋난 필드를 되돌렸습니다. "어긋난 기록 N건을 되돌리고 라이브러리를 열었습니다"</summary>
    Repaired,

    /// <summary>카탈로그를 열 수 없어 최근 백업으로 되돌렸습니다. "백업에서 라이브러리 복구: 사진 N장"</summary>
    RecoveredFromBackup,
}

/// <param name="FrameCount">프리뷰를 뺀 사진 수입니다.</param>
/// <param name="RepairCount">되돌린 필드 수입니다(<see cref="LibraryOpenOutcome.Repaired"/>).</param>
public readonly record struct LibraryOpenStatus(
    LibraryOpenOutcome Outcome,
    int FrameCount,
    int RepairCount);
