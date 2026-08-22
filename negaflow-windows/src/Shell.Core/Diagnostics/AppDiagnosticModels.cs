namespace Negaflow.Shell.Diagnostics;

/// <summary>macOS <c>AppDiagnosticCategory</c> 이식본입니다.</summary>
public enum AppDiagnosticCategory
{
    Import,
    Develop,
    Defects,
    Export,
    Catalog,
}

/// <summary>macOS <c>AppDiagnosticOperation</c> 이식본입니다.</summary>
public enum AppDiagnosticOperation
{
    ImportFiles,
    DevelopFrame,
    RegionDefect,
    InfraredDefect,
    CleanedRawBuild,
    CleanedRawRebuild,
    ExportFrame,
    CatalogRestore,
    CatalogSave,
}

/// <summary>macOS <c>AppDiagnosticPhase</c> 이식본입니다.</summary>
public enum AppDiagnosticPhase
{
    Begin,
    Event,
    End,
    Error,
}

/// <summary>macOS <c>AppDiagnosticSeverity</c> 이식본입니다.</summary>
public enum AppDiagnosticSeverity
{
    Debug,
    Info,
    Notice,
    Error,
    Fault,
}

/// <summary>
/// 진단 사건 하나입니다. macOS <c>AppDiagnosticEvent</c> 와 같은 필드입니다.
/// </summary>
/// <remarks>
/// macOS 주석 원문: 경로·파일명·사용자 metadata 를 받지 않는 짧은 machine code 만 저장한다.
/// </remarks>
public sealed record AppDiagnosticEvent(
    DateTimeOffset Timestamp,
    Guid OperationId,
    AppDiagnosticCategory Category,
    AppDiagnosticOperation Operation,
    AppDiagnosticPhase Phase,
    AppDiagnosticSeverity Severity,
    string? Code);

/// <summary>
/// 최근 사건을 담는 고리 버퍼입니다. macOS <c>AppDiagnosticEventStore</c> 와 같은 상한(200)입니다.
/// </summary>
public sealed class AppDiagnosticEventStore
{
    private readonly Lock gate = new();
    private readonly int capacity;
    private readonly List<AppDiagnosticEvent> events = [];

    public AppDiagnosticEventStore(int capacity = 200) =>
        this.capacity = Math.Max(1, capacity);

    public void Append(AppDiagnosticEvent value)
    {
        ArgumentNullException.ThrowIfNull(value);
        lock (gate)
        {
            events.Add(value);
            if (events.Count > capacity)
            {
                events.RemoveRange(0, events.Count - capacity);
            }
        }
    }

    public IReadOnlyList<AppDiagnosticEvent> Snapshot()
    {
        lock (gate)
        {
            return [.. events];
        }
    }

    public void RemoveAll()
    {
        lock (gate)
        {
            events.Clear();
        }
    }
}
