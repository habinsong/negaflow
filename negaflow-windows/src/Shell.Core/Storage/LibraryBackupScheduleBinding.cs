namespace Negaflow.Shell.Storage;

/// <summary>
/// 일정 백업이 설정을 읽고 고치는 통로입니다. Shell.Core 는 설정 저장소를 모르므로 셸이
/// 이어 줍니다 — 이어 주지 않으면 일정 백업은 돌지 않습니다.
/// </summary>
/// <remarks>
/// macOS 는 <c>backupScheduleStore</c> 를 AppModel 이 직접 들고 있습니다. Windows 는
/// 설정이 <c>presentation.json</c> 한 곳에 모여 있어, 그 저장소를 Shell.Core 로 끌어오는
/// 대신 읽기/고치기 두 동작만 넘겨받습니다.
/// </remarks>
public sealed class LibraryBackupScheduleBinding
{
    private readonly Func<LibraryBackupSettings> read;
    private readonly Action<Func<LibraryBackupSettings, LibraryBackupSettings>> update;

    public LibraryBackupScheduleBinding(
        Func<LibraryBackupSettings> read,
        Action<Func<LibraryBackupSettings, LibraryBackupSettings>> update)
    {
        ArgumentNullException.ThrowIfNull(read);
        ArgumentNullException.ThrowIfNull(update);
        this.read = read;
        this.update = update;
    }

    public LibraryBackupSettings Current => read();

    public void Update(Func<LibraryBackupSettings, LibraryBackupSettings> change)
    {
        ArgumentNullException.ThrowIfNull(change);
        update(change);
    }
}
