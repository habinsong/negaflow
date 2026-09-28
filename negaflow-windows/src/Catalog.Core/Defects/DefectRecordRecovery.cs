using System.Security.AccessControl;
using System.Security.Principal;

namespace Negaflow.Catalog;

/// <summary>
/// 카탈로그가 선언한 결함 기록이 사라졌거나 깨졌을 때, 가장 새 검증된 백업 세대에 남은 같은
/// 사진의 기록으로 되살립니다. macOS <c>DefectRecordRecovery.restoreFromBackup</c> 이식본입니다.
/// </summary>
/// <remarks>
/// 내용을 새로 만들지 않고 백업의 기록을 그대로 가져옵니다. 백업에 멀쩡히 있는데도 편집을 비우면
/// 사용자가 한 결함 제거를 통째로 잃습니다. 깨진 파일은 지우지 않고 <c>defects.corrupt-*</c> 에
/// 보관합니다. 읽힌 기록·권한/입출력 오류·더 새 버전은 건드리지 않습니다.
/// </remarks>
internal static class DefectRecordRecovery
{
    /// <summary>
    /// macOS <c>restoreOwnerAccessIfNeeded</c> — 앱이 쓴 기록인데 읽기 권한이 빠졌거나(다른 계정에서
    /// 복사, 권한 정리 도구 등) 읽기 전용 속성이 붙어 이후 쓰기가 막히는 경우, 소유자가 지금
    /// 사용자이면 그 사용자를 막는 거부 항목을 걷고 읽기·쓰기를 허용한 뒤 읽기 전용을 풉니다.
    /// 남의 파일이면 건드리지 않습니다. 다른 프로세스가 잡고 있는 공유 잠금은 권한 문제가 아닙니다.
    /// </summary>
    internal static bool RestoreOwnerAccessIfNeeded(StorageRootSet roots, Guid frameId)
    {
        ArgumentNullException.ThrowIfNull(roots);
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }
        lock (DefectSidecarStore.Gate)
        {
            FileInfo file = new(DefectSidecarStore.PathFor(roots, frameId));
            try
            {
                if (!file.Exists || !file.IsReadOnly && CanRead(file.FullName))
                {
                    return false;
                }
                using WindowsIdentity user = WindowsIdentity.GetCurrent();
                FileSecurity security = file.GetAccessControl();
                // 이 프로세스가 만든 파일의 소유자는 사용자이거나, 관리자 권한으로 돌면 토큰의 기본
                // 소유자(Administrators)입니다 — 그래서 둘 다 "자기 파일" 입니다.
                IdentityReference? owner = security.GetOwner(typeof(SecurityIdentifier));
                if (user.User is not { } sid ||
                    !(sid.Equals(owner) || user.Owner?.Equals(owner) == true))
                {
                    return false;
                }
                foreach (FileSystemAccessRule rule in security.GetAccessRules(
                    includeExplicit: true, includeInherited: false, typeof(SecurityIdentifier)))
                {
                    if (rule.AccessControlType == AccessControlType.Deny &&
                        (sid.Equals(rule.IdentityReference) ||
                         user.Groups?.Contains(rule.IdentityReference) == true))
                    {
                        security.RemoveAccessRuleSpecific(rule);
                    }
                }
                security.AddAccessRule(new FileSystemAccessRule(
                    sid,
                    FileSystemRights.Read | FileSystemRights.Write | FileSystemRights.Delete,
                    AccessControlType.Allow));
                file.SetAccessControl(security);
                file.IsReadOnly = false;
                return true;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or
                InvalidOperationException)
            {
                return false;
            }
        }
    }

    /// <summary>읽기 권한이 없을 때만 <see langword="false"/> 입니다. 공유 위반은 읽을 수 있는 것으로 봅니다.</summary>
    private static bool CanRead(string path)
    {
        try
        {
            using FileStream _ = new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (IOException)
        {
            return true;
        }
    }

    internal static bool RestoreFromBackup(StorageRootSet roots, Guid frameId)
    {
        ArgumentNullException.ThrowIfNull(roots);
        lock (DefectSidecarStore.Gate)
        {
            string destination = DefectSidecarStore.PathFor(roots, frameId);
            DefectSidecarReadResult current = DefectSidecarFile.ReadFile(destination, frameId);
            if (current.Snapshot is not null ||
                current.Error is not (DefectSidecarError.NotFound or DefectSidecarError.InvalidContent or
                    DefectSidecarError.InvalidSnapshot or DefectSidecarError.InvalidFrameId or
                    DefectSidecarError.ConflictingSameRevision))
            {
                return false;
            }
            foreach (CatalogBackupGeneration generation in CatalogBackupInspector.Enumerate(roots))
            {
                string source = Path.Combine(
                    roots.BackupRoot,
                    generation.Id,
                    CatalogBackupStore.DefectsDirectoryName,
                    DefectSidecarStore.FileName(frameId));
                if (!generation.IsRestorable || DefectSidecarFile.ReadFile(source, frameId).Snapshot is null)
                {
                    continue;
                }
                try
                {
                    Directory.CreateDirectory(roots.DefectRecipeRoot);
                    if (File.Exists(destination))
                    {
                        string preserved = Path.Combine(
                            roots.LibraryRoot,
                            $"{CatalogSidelinedFiles.DefectPrefix}{Guid.NewGuid():N}");
                        Directory.CreateDirectory(preserved);
                        File.Move(destination, Path.Combine(preserved, Path.GetFileName(destination)));
                        CatalogSidelinedFiles.Prune(roots.LibraryRoot);
                    }
                    File.Copy(source, destination);
                    return true;
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    // 다음 세대를 봅니다.
                }
            }
            return false;
        }
    }
}
