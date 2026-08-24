using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>현상 버전·기록·사용자 프리셋·복사/붙여넣기 몫입니다.</summary>
public sealed partial class DevelopPanelState
{
    /// <summary>이 frame 에 담긴 현상 버전입니다. 최근에 담은 것이 뒤에 옵니다.</summary>
    public IReadOnlyList<LibraryVersionSnapshot> Versions =>
        SelectedFrame?.Versions ?? [];

    /// <summary>
    /// 지금 recipe 를 이름 붙여 담습니다. macOS 처럼 현재 상태는 그대로 두고 목록에만 더합니다 —
    /// 담는 것이 되돌리는 것을 뜻하지는 않습니다.
    /// </summary>
    public LibraryFrameError CaptureVersion(string name) =>
        RefreshAfterEdit(versionPresets.CaptureVersion(SelectedFrame, name));

    /// <summary>담아 둔 버전의 recipe 로 되돌립니다. 버전 목록은 남습니다.</summary>
    public LibraryFrameError RestoreVersion(string versionId) =>
        RefreshAfterEdit(versionPresets.RestoreVersion(SelectedFrame, versionId));

    public LibraryFrameError DeleteVersion(string versionId) =>
        RefreshAfterEdit(versionPresets.DeleteVersion(SelectedFrame, versionId));

    /// <summary>macOS <c>frame.developHistory</c> — 오래된 것이 앞입니다.</summary>
    public IReadOnlyList<LibraryVersionSnapshot> History => SelectedFrame?.History ?? [];

    /// <summary>
    /// macOS <c>AppModel.createVirtualCopy(from:)</c> — 같은 원본을 가리키는 사본을 하나
    /// 만듭니다. 원본의 recipe·기록·스냅샷을 그대로 물려받되 파일은 복사하지 않습니다.
    /// </summary>
    public bool CreateVirtualCopy()
    {
        if (SelectedFrame is not { } frame)
        {
            return false;
        }
        if (host.CreateVirtualCopy(frame.Id) is not { Length: > 0 } copyId)
        {
            return false;
        }
        host.SetSelection([copyId], copyId);
        return string.Equals(SelectedFrame?.Id, copyId, StringComparison.Ordinal) || Select(copyId);
    }

    /// <summary>
    /// 지금 recipe 를 기록으로 남깁니다. macOS 는 이름을 순번으로 붙이므로(`기록 N`) 다음
    /// 번호는 지금 목록 길이 + 1 입니다.
    /// </summary>
    public LibraryFrameError RecordHistory(string labelFormat)
    {
        ArgumentNullException.ThrowIfNull(labelFormat);
        string label = string.Format(
            System.Globalization.CultureInfo.CurrentCulture,
            labelFormat,
            History.Count + 1);
        return RefreshAfterEdit(versionPresets.RecordHistory(SelectedFrame, label));
    }

    /// <summary>골라 둔 기록의 recipe 로 되돌립니다. 기록 목록은 남습니다.</summary>
    public LibraryFrameError ApplyHistory(string entryId) =>
        RefreshAfterEdit(versionPresets.ApplyHistory(SelectedFrame, entryId));

    /// <summary>
    /// 적어 둔 메타데이터를 바꿉니다. 레시피가 아니므로 미리보기를 다시 돌리지 않습니다 —
    /// 제목을 적었다고 사진이 다시 현상될 이유가 없습니다.
    /// </summary>
    public LibraryFrameError SetAppMetadata(
        Func<AppMetadataOverlay, AppMetadataOverlay> update)
    {
        return RefreshAfterEdit(versionPresets.SetAppMetadata(SelectedFrame, update));
    }

    /// <summary>
    /// 복사해 둔 현상 설정입니다. macOS 처럼 앱이 사는 동안만 남고 저장되지 않습니다 — 클립보드에
    /// 가까운 물건이지 카탈로그의 일부가 아닙니다.
    /// </summary>
    public LibraryFrameSnapshot? CopiedSettings => versionPresets.CopiedSettings;

    public string? CopiedSettingsSourceName => versionPresets.CopiedSettingsSourceName;

    /// <summary>
    /// macOS 의 붙여넣기 범위입니다. 한 번 정하면 다음 붙여넣기에도 그대로 쓰입니다.
    /// </summary>
    public DevelopSettingsPasteScope PasteScope
    {
        get => versionPresets.PasteScope;
        set => versionPresets.PasteScope = value;
    }

    public IReadOnlyList<DevelopUserPreset> UserPresets => versionPresets.UserPresets;

    /// <summary>지금 프레임의 현상 설정을 복사해 둡니다.</summary>
    public bool CopyDevelopSettings()
    {
        return versionPresets.CopyDevelopSettings(SelectedFrame);
    }

    /// <summary>
    /// 복사해 둔 설정을 지금 프레임에 <see cref="PasteScope"/> 만큼 붙입니다. 복사한 것이 없거나
    /// 범위가 비어 있으면 아무것도 하지 않습니다.
    /// </summary>
    public LibraryFrameError PasteDevelopSettings()
    {
        return RefreshAfterEdit(versionPresets.PasteDevelopSettings(SelectedFrame));
    }

    /// <summary>
    /// 사용자 프리셋 목록을 이 파일에서 읽고, 이후 저장·삭제도 여기에 씁니다. 경로를 주지 않으면
    /// 목록 기능이 그냥 비어 있습니다 — 셸이 저장소를 열지 못한 경우입니다.
    /// </summary>
    public void OpenUserPresets(string? path)
    {
        versionPresets.OpenUserPresets(path);
    }

    /// <summary>지금 프레임의 현상 설정을 이름 붙여 프리셋으로 저장합니다.</summary>
    public DevelopUserPreset? SaveUserPreset(string name)
    {
        return versionPresets.SaveUserPreset(SelectedFrame, name);
    }

    public LibraryFrameError ApplyUserPreset(Guid id)
    {
        return RefreshAfterEdit(versionPresets.ApplyUserPreset(SelectedFrame, id));
    }

    public bool DeleteUserPreset(Guid id)
    {
        return versionPresets.DeleteUserPreset(id);
    }

}
