using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.LibraryCatalogMaintenanceTests;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 사라졌거나 깨진 결함 기록을 백업의 같은 사진 기록으로 되살립니다. macOS 31531f36
/// <c>testDeletedRecordIsRestoredFromTheNewestBackup</c>·
/// <c>testRepairRestoresADeletedRecordFromBackupInsteadOfClearingEdits</c> 와 같은 보장입니다 —
/// 백업에 멀쩡히 있는데 편집을 비우면 결함 제거를 통째로 잃고, 그동안 저장도 막힙니다.
/// </summary>
internal static class LibraryDefectRecordRecoveryTests
{
    internal static void Run()
    {
        RestoredAtOpen("deleted", (roots, frameId) => File.Delete(Sidecar(roots, frameId)));
        RestoredAtOpen("corrupt", (roots, frameId) => File.WriteAllText(Sidecar(roots, frameId), "{ broken"));
        RepairRestoresFromBackupInsteadOfClearing();
        if (OperatingSystem.IsWindows())
        {
            OwnRecordAccessComesBack();
        }
    }

    /// <summary>
    /// macOS <c>testOwnRecordWithoutReadPermissionOpensAgain</c> — 자기 기록에 읽기 거부가 걸렸거나
    /// 읽기 전용이 붙어도 열 때 권한을 되돌려 편집을 그대로 엽니다. 예전에는 복원 대기가 되어 저장이
    /// 전부 막혔습니다(읽기 전용이면 그 사진의 다음 쓰기가 막혔습니다).
    /// </summary>
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static void OwnRecordAccessComesBack()
    {
        RunIsolated("access-denied", (roots, frameId) =>
        {
            FileInfo sidecar = new(Sidecar(roots, frameId));
            System.Security.Principal.SecurityIdentifier user =
                System.Security.Principal.WindowsIdentity.GetCurrent().User!;
            System.Security.AccessControl.FileSystemAccessRule deny = new(
                user,
                System.Security.AccessControl.FileSystemRights.ReadData,
                System.Security.AccessControl.AccessControlType.Deny);
            System.Security.AccessControl.FileSecurity denied = sidecar.GetAccessControl();
            denied.AddAccessRule(deny);
            sidecar.SetAccessControl(denied);
            sidecar.IsReadOnly = true;
            try
            {
                Check(!CanRead(sidecar.FullName), "record_access_fixture_denies_reading");
                using LibraryHostService host = OpenHost(roots, "record_access_opens");
                Check(host.Frames.Single() is { DefectRestorePending: false, DefectRecipe.Items.Count: 1 },
                    "record_access_restores_the_owner_access_and_keeps_the_edits",
                    () => $"pending={host.Frames.Single().DefectRestorePending}");
                sidecar.Refresh();
                Check(CanRead(sidecar.FullName) && !sidecar.IsReadOnly,
                    "record_access_file_is_readable_and_writable_again");
                Check(host.Save() == CatalogStoreError.None, "record_access_saves");
            }
            finally
            {
                sidecar.Refresh();
                if (sidecar.Exists)
                {
                    System.Security.AccessControl.FileSecurity security = sidecar.GetAccessControl();
                    security.RemoveAccessRuleSpecific(deny);
                    sidecar.SetAccessControl(security);
                    sidecar.IsReadOnly = false;
                }
            }
        });
    }

    private static bool CanRead(string path)
    {
        try
        {
            _ = File.ReadAllBytes(path);
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static void RestoredAtOpen(string name, Action<StorageRootSet, Guid> damage)
    {
        RunIsolated($"backup-{name}", (roots, frameId) =>
        {
            Backup(roots);
            damage(roots, frameId);
            using LibraryHostService host = OpenHost(roots, $"record_recovery_{name}_opens");
            Check(host.Frames.Single() is { DefectRestorePending: false, DefectRecipe.Items.Count: 1 },
                $"record_recovery_{name}_restores_the_edits_from_backup",
                () => $"pending={host.Frames.Single().DefectRestorePending}");
            Check(host.Save() == CatalogStoreError.None, $"record_recovery_{name}_saves");
            if (name == "corrupt")
            {
                Check(Directory.EnumerateDirectories(roots.LibraryRoot, "defects.corrupt-*")
                        .Any(directory => File.Exists(Path.Combine(directory, $"{frameId:D}.json"))),
                    "record_recovery_corrupt_keeps_the_damaged_file");
            }
        });
    }

    /// <summary>열 때는 백업이 없었고, 수동 복구 때는 있습니다. 비우기 전에 백업부터 봅니다.</summary>
    private static void RepairRestoresFromBackupInsteadOfClearing()
    {
        RunIsolated("backup-repair", (roots, frameId) =>
        {
            Backup(roots);
            string parked = $"{roots.BackupRoot}.parked";
            Directory.Move(roots.BackupRoot, parked);
            File.Delete(Sidecar(roots, frameId));
            using LibraryHostService host = OpenHost(roots, "record_recovery_repair_opens");
            Check(host.Frames.Single().DefectRestorePending, "record_recovery_repair_starts_pending");
            Directory.Move(parked, roots.BackupRoot);
            LibraryCatalogMaintenanceResult repaired = host.RepairCatalog(Idle);
            Check(repaired.IsSuccess &&
                  host.Frames.Single() is { DefectRestorePending: false, DefectRecipe.Items.Count: 1 },
                "record_recovery_repair_restores_instead_of_clearing",
                () => $"{repaired.Error} pending={host.Frames.Single().DefectRestorePending}");
            Check(host.Save() == CatalogStoreError.None && Quit(host).IsSuccess,
                "record_recovery_repair_unblocks_save_and_quit");
        });
    }

    private static void Backup(StorageRootSet roots)
    {
        using CatalogSession session = CatalogSession.Open(roots).Session!;
        CatalogBackupCreateResult created = session.CreateBackup();
        Check(created.IsSuccess, "record_recovery_backup_seed", () => created.Error.ToString());
    }
}
