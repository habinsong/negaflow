using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

internal static class TestAssert
{
    private static readonly List<string> failures = [];
    private static int assertionCount;

    public static IReadOnlyList<string> Failures => failures;

    public static int AssertionCount => assertionCount;

    /// <summary>
    /// 네이티브 엔진이 있을 때만 돌립니다. 없으면 건너뛰었다고 남기고 넘어갑니다.
    /// </summary>
    /// <remarks>
    /// CI 는 네이티브와 관리 코드를 **다른 작업에서** 짓습니다. 관리 작업에는
    /// <c>Negaflow.Native.dll</c> 이 없으므로, 그것을 부르는 시험은 <c>DllNotFoundException</c>
    /// 으로 프로세스를 통째로 끝냅니다 - 그 뒤 시험은 한 줄도 돌지 않습니다. 네이티브가 하는
    /// 일은 네이티브 작업이 ctest 로 검증합니다.
    ///
    /// 조용히 넘어가지 않습니다. 기록이 없으면 "네이티브가 없어 안 돈 것"과 "돌았는데 아무
    /// 것도 확인하지 않은 것"을 나중에 구별할 수 없습니다.
    /// </remarks>
    public static void RunIfNativeIsPresent(Action work, string? name = null)
    {
        ArgumentNullException.ThrowIfNull(work);
        // 이름은 부르는 쪽이 줍니다 - `Run` 이라는 메서드 이름만으로는 무엇을 건너뛰었는지
        // 알 수 없습니다.
        string label = name ?? (work.Method.DeclaringType?.Name ?? work.Method.Name);
        if (!NativeIsPresent)
        {
            Console.Error.WriteLine("native engine missing; skipped " + label);
            return;
        }
        work();
    }

    /// <summary>
    /// 네이티브 엔진을 부를 수 있는가. 한 번만 확인하고 기억합니다.
    /// </summary>
    /// <remarks>
    /// 예외를 잡는 것만으로는 모자랍니다 - 제품 코드가 <c>DllNotFoundException</c> 을 안에서
    /// 삼키고 "실패" 를 돌려주는 자리가 있어(IR 검출이 그렇습니다), 시험은 예외 대신 그냥
    /// 틀린 답을 받습니다. 그래서 <b>돌리기 전에</b> 묻습니다.
    ///
    /// 무엇을 부르든 상관없지만 값싼 것이어야 합니다. 톤 한계 읽기는 구조체 하나를 채우고
    /// 끝나며, 네이티브가 없으면 그 자리에서 던집니다.
    /// </remarks>
    public static bool NativeIsPresent => nativeIsPresent ??= ProbeNative();

    private static bool? nativeIsPresent;

    private static bool ProbeNative()
    {
        try
        {
            _ = Negaflow.Interop.ToneLimits.Read();
            return true;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
        catch (Negaflow.Interop.NativeBootstrapException)
        {
            return false;
        }
    }

    public static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            failures.Add(name);
        }
    }

    public static bool Near(double actual, double expected) =>
        Math.Abs(actual - expected) <= 1e-9;

    public static bool NearRect(
        CropDisplayRect actual,
        double x,
        double y,
        double width,
        double height) =>
        Near(actual.X, x) && Near(actual.Y, y) &&
        Near(actual.Width, width) && Near(actual.Height, height);
}
