namespace Negaflow.Shell.Print;

/// <summary>눈금 하나입니다. 자리와 길이, 그리고 숫자를 답니다.</summary>
public readonly record struct PrintRulerTick(double Position, double Length, string? Label);

/// <summary>
/// 판 옆에 붙는 눈금자입니다.
/// </summary>
/// <remarks>
/// 눈금은 **용지의 실제 치수**를 따릅니다 — 화면 배율이 아니라 mm 입니다. 그래야 화면에서
/// 잰 길이가 인화물에서도 같습니다.
/// </remarks>
public static class PrintRuler
{
    /// <summary>
    /// 이 길이(mm)를 덮는 눈금들입니다. 자리는 0…1 로 돌려주므로 화면이든 판이든 곱하기만
    /// 하면 됩니다.
    /// </summary>
    /// <remarks>
    /// 센티미터는 1cm 마다 긴 눈금에 숫자, 5mm 마다 중간 눈금입니다. 인치는 1인치마다 숫자,
    /// 1/2 과 1/4 인치에 짧은 눈금입니다 — 1/8 까지 넣으면 화면에서 눈금이 서로 붙습니다.
    /// </remarks>
    public static IReadOnlyList<PrintRulerTick> Ticks(double lengthMm, PrintRulerUnit unit)
    {
        if (!double.IsFinite(lengthMm) || lengthMm <= 0)
        {
            return [];
        }
        List<PrintRulerTick> ticks = [];
        if (unit == PrintRulerUnit.Centimeters)
        {
            // 5mm 간격으로 훑되, 10mm 마다 긴 눈금과 숫자입니다.
            int steps = (int)(lengthMm / 5);
            for (int step = 0; step <= steps; ++step)
            {
                double mm = step * 5.0;
                bool major = step % 2 == 0;
                ticks.Add(new PrintRulerTick(
                    mm / lengthMm,
                    major ? 1.0 : 0.55,
                    major ? (step / 2).ToString(
                        System.Globalization.CultureInfo.CurrentCulture) : null));
            }
            return ticks;
        }

        const double inchMm = 25.4;
        int quarters = (int)(lengthMm / (inchMm / 4));
        for (int quarter = 0; quarter <= quarters; ++quarter)
        {
            double mm = quarter * inchMm / 4;
            bool inch = quarter % 4 == 0;
            bool half = quarter % 2 == 0;
            ticks.Add(new PrintRulerTick(
                mm / lengthMm,
                inch ? 1.0 : half ? 0.7 : 0.45,
                inch ? (quarter / 4).ToString(
                    System.Globalization.CultureInfo.CurrentCulture) : null));
        }
        return ticks;
    }
}
