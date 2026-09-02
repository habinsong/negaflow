namespace Negaflow.Shell.Develop;

/// <summary>
/// 내보내기가 몇 장 중 몇 장까지 갔는지입니다.
/// </summary>
/// <remarks>
/// macOS 는 이 값을 <c>ExportBatchProgressView</c> 라는 <b>별도 구역</b>으로 냅니다. Windows
/// 에서는 사용자가 요청한 대로 <b>단추 자체</b>(내보내기 · 빠른 내보내기 알약)와 위 막대에
/// 얹습니다 — 누른 자리에서 바로 보이는 편이 낫다는 판단입니다.
/// </remarks>
/// <param name="Completed">끝난 장 수입니다.</param>
/// <param name="Total">전체 장 수입니다.</param>
/// <param name="CurrentFraction">
/// <b>지금 굽고 있는 한 장</b>이 얼마나 갔는지입니다(0~1).
/// </param>
/// <remarks>
/// <para>
/// 세 번째 값이 없을 때는 한 장짜리 내보내기가 <c>0/1</c> 로 시작해 끝날 때까지 그대로라
/// <b>화면에 0% 가 붙박여 있었습니다</b> — 8 초가 걸려도 아무것도 움직이지 않으니 멈춘
/// 것처럼 보였습니다. 엔진은 이미 단계별 비용으로 진행도를 내고 있고
/// (<c>nf_develop_run_state_v1.progress_permille</c> · <c>DevelopRun.Progress</c>),
/// 화면만 그것을 읽지 않고 있었습니다.
/// </para>
/// </remarks>
public readonly record struct ExportProgress(int Completed, int Total, double CurrentFraction = 0.0)
{
    /// <summary>아무 것도 돌고 있지 않은 상태입니다.</summary>
    public static ExportProgress Idle => default;

    /// <summary>도는 중인지입니다. 끝나면 <see cref="Idle"/> 로 돌아갑니다.</summary>
    public bool IsRunning => Total > 0;

    /// <summary>
    /// 0~1 입니다. 끝난 장에 지금 장의 진행분을 얹습니다 — 장 수를 모르면 0 입니다.
    /// </summary>
    public double Fraction
    {
        get
        {
            if (Total <= 0)
            {
                return 0.0;
            }
            double inner = double.IsFinite(CurrentFraction)
                ? Math.Clamp(CurrentFraction, 0.0, 1.0)
                : 0.0;
            // 마지막 장이 다 차기 전에 100% 가 뜨지 않게, 얹는 몫은 남은 장 안에서만 셉니다.
            double reached = Math.Min(Completed + inner, Total);
            return Math.Clamp(reached / Total, 0.0, 1.0);
        }
    }

    /// <summary>0~100 정수입니다. 표시에만 씁니다.</summary>
    public int Percent => (int)Math.Round(Fraction * 100.0);

    /// <summary>"3/8" 처럼 몇 장 중 몇 장인지입니다.</summary>
    public string CountText => Total > 0
        ? string.Create(
            System.Globalization.CultureInfo.CurrentCulture,
            $"{Completed}/{Total}")
        : string.Empty;

    /// <summary>"3/8 · 38%" — 단추에 얹는 한 줄입니다.</summary>
    public string DisplayText => Total > 0
        ? string.Create(
            System.Globalization.CultureInfo.CurrentCulture,
            $"{Completed}/{Total} · {Percent}%")
        : string.Empty;

    public ExportProgress Advanced() => this with { Completed = Math.Min(Completed + 1, Total) };
}
