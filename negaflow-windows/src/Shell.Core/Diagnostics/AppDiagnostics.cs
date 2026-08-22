namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 앱이 하는 일의 시작·끝·실패를 남기는 자리입니다. macOS <c>AppDiagnostics</c> 이식본입니다.
/// </summary>
/// <remarks>
/// macOS 는 여기에 OSLog signpost 를 함께 겁니다. Windows 에는 그 장치가 없으므로 사건 저장만
/// 합니다 - 진단 보고서가 읽는 것은 저장된 사건이고, signpost 는 Instruments 전용이었습니다.
/// </remarks>
public static class AppDiagnostics
{
    private static readonly AppDiagnosticEventStore EventStore = new();

    /// <summary>일 하나를 시작합니다. 끝나거나 실패하면 그 자취가 남습니다.</summary>
    public static AppOperationTrace Start(
        AppDiagnosticOperation operation,
        AppDiagnosticCategory category) => new(category, operation);

    public static IReadOnlyList<AppDiagnosticEvent> RecentEvents => EventStore.Snapshot();

    /// <summary>예외를 짧은 기계 코드로 줄입니다. macOS <c>errorCode(_:)</c>.</summary>
    public static string ErrorCode(Exception error)
    {
        ArgumentNullException.ThrowIfNull(error);
        return SanitizedCode($"{error.GetType().FullName}#{error.HResult}");
    }

    /// <summary>
    /// 코드에 경로나 이름이 섞여 들어오지 못하게 합니다. macOS <c>sanitizedCode(_:)</c> —
    /// 영숫자와 <c>._#-</c> 만 남기고 120자로 자릅니다.
    /// </summary>
    public static string SanitizedCode(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        return string.Create(
            Math.Min(value.Length, 120),
            value,
            static (span, source) =>
            {
                for (int index = 0; index < span.Length; ++index)
                {
                    char character = source[index];
                    span[index] = char.IsAsciiLetterOrDigit(character) ||
                        character is '.' or '_' or '#' or '-'
                        ? character
                        : '_';
                }
            });
    }

    public static void Publish(AppDiagnosticEvent value) => EventStore.Append(value);

    public static void ClearForTesting() => EventStore.RemoveAll();
}

/// <summary>
/// 한 번의 일에 붙는 자취입니다. macOS <c>AppOperationTrace</c> 이식본이며 같은 규칙입니다 —
/// <b>한 번만 끝납니다.</b> 끝난 뒤에 다시 부르면 아무 것도 남기지 않습니다.
/// </summary>
public sealed class AppOperationTrace
{
    private readonly Lock gate = new();
    private bool completed;

    internal AppOperationTrace(
        AppDiagnosticCategory category,
        AppDiagnosticOperation operation)
    {
        OperationId = Guid.NewGuid();
        Category = category;
        Operation = operation;
        Publish(AppDiagnosticPhase.Begin, AppDiagnosticSeverity.Debug, code: null);
    }

    public Guid OperationId { get; }

    public AppDiagnosticCategory Category { get; }

    public AppDiagnosticOperation Operation { get; }

    /// <summary>도중에 알릴 것이 있을 때입니다.</summary>
    public void Event(string? code) =>
        Publish(AppDiagnosticPhase.Event, AppDiagnosticSeverity.Info, code);

    public void Finish(string? code = null)
    {
        if (TryComplete())
        {
            Publish(AppDiagnosticPhase.End, AppDiagnosticSeverity.Info, code);
        }
    }

    public void Fail(string code)
    {
        ArgumentNullException.ThrowIfNull(code);
        if (TryComplete())
        {
            Publish(
                AppDiagnosticPhase.Error,
                AppDiagnosticSeverity.Error,
                AppDiagnostics.SanitizedCode(code));
        }
    }

    public void Fail(Exception error) => Fail(AppDiagnostics.ErrorCode(error));

    private bool TryComplete()
    {
        lock (gate)
        {
            if (completed)
            {
                return false;
            }
            completed = true;
            return true;
        }
    }

    private void Publish(
        AppDiagnosticPhase phase,
        AppDiagnosticSeverity severity,
        string? code) =>
        AppDiagnostics.Publish(new AppDiagnosticEvent(
            DateTimeOffset.Now, OperationId, Category, Operation, phase, severity, code));
}
