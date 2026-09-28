namespace Negaflow.Shell;

public enum DevelopRequestRefusal
{
    None,

    /// <summary>고른 사진이 없습니다.</summary>
    /// <remarks>
    /// 예전에는 이 자리에 <c>MissingManualBase</c>(수동인데 Dmin 이 없음)와
    /// <c>MissingFilmStock</c>(preset 인데 필름이 없음)이 있었습니다. 두 상태 모두 macOS 는
    /// 거절하지 않고 자동 추정으로 현상하므로 (<c>resolveFilmBase</c>,
    /// <c>applyNegativeFilmPipeline</c>) 사유 자체가 없어졌습니다. 남아 있던 유일한 쓰임은
    /// "고른 사진이 없다" 를 이 값으로 알리던 것이라, 그 뜻을 이름에 담습니다.
    /// </remarks>
    NoFrameSelected,

    UnsupportedBaseEstimationMode,

    /// <summary>Scene-linear 또는 알 수 없는 digital source는 아직 지원하지 않습니다.</summary>
    UnsupportedDigitalSource,

    UnsupportedPositiveFilm,

    /// <summary>출력 형식이 알려진 값이 아닙니다.</summary>
    UnknownOutputFormat,

    UnsupportedAlpha,

    /// <summary>출력 경로가 비었거나 절대 경로가 아닙니다.</summary>
    InvalidDestination,

    InvalidDefectRecipe,

    UnsupportedDefectEditKind,

    /// <summary>
    /// 결함 편집을 기록할 때의 원본과 지금 파일이 다르고, <b>화소 격자까지 달라졌습니다.</b>
    /// 마스크를 다른 화소에 얹게 되므로 현상하지 않습니다.
    /// </summary>
    StaleDefectSource,

    /// <summary>
    /// 결함 편집을 선언했는데 기록을 읽지 못했습니다(복원 대기). macOS 도 현상하지 않습니다 —
    /// 결함 제거를 빼고 현상하면 제거한 줄 아는 결과가 나옵니다.
    /// </summary>
    DefectRestorePending,
}
