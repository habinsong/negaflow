namespace Negaflow.Shell.Develop;

/// <summary>
/// 내보내기가 몇 장 중 몇 장까지 갔는지입니다.
/// </summary>
/// <remarks>
/// macOS 는 이 값을 <c>ExportBatchProgressView</c> 라는 <b>별도 구역</b>으로 냅니다. Windows
/// 에서는 사용자가 요청한 대로 <b>단추 자체</b>(내보내기 · 빠른 내보내기 알약)와 위 막대에
/// 얹습니다 — 누른 자리에서 바로 보이는 편이 낫다는 판단입니다.
/// </remarks>
public readonly record struct ExportProgress(int Completed, int Total)
{
    /// <summary>아무 것도 돌고 있지 않은 상태입니다.</summary>
    public static ExportProgress Idle => default;

    /// <summary>도는 중인지입니다. 끝나면 <see cref="Idle"/> 로 돌아갑니다.</summary>
    public bool IsRunning => Total > 0;

    /// <summary>0~1 입니다. 장 수를 모르면 0 입니다.</summary>
    public double Fraction => Total > 0
        ? Math.Clamp((double)Completed / Total, 0.0, 1.0)
        : 0.0;

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
