using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// Owns non-slider Develop workflow state: versions, settings copy/paste, user presets,
/// and application metadata persistence.
/// </summary>
internal sealed class DevelopVersionPresetController
{
    private readonly LibraryHostService host;
    private string? userPresetPath;

    public DevelopVersionPresetController(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        this.host = host;
    }

    public LibraryFrameSnapshot? CopiedSettings { get; private set; }

    public string? CopiedSettingsSourceName { get; private set; }

    public DevelopSettingsPasteScope PasteScope { get; set; } = DevelopSettingsPasteScope.All;

    public IReadOnlyList<DevelopUserPreset> UserPresets { get; private set; } = [];

    public DevelopEditResult CaptureVersion(LibraryFrameSnapshot? frame, string name) =>
        EditFrameRecord(frame, record => LibraryVersions.Capture(
            record,
            Guid.NewGuid().ToString("D"),
            name,
            DateTimeOffset.UtcNow));

    public DevelopEditResult RestoreVersion(LibraryFrameSnapshot? frame, string versionId) =>
        EditFrameRecord(frame, record => LibraryVersions.Restore(record, versionId));

    public DevelopEditResult DeleteVersion(LibraryFrameSnapshot? frame, string versionId) =>
        EditFrameRecord(frame, record => LibraryVersions.Delete(record, versionId));

    /// <summary>
    /// macOS <c>AppModel.recordDevelopHistory</c> — 지금 recipe 를 기록 목록 끝에 더합니다.
    /// 이름은 macOS 처럼 순번입니다(`기록 1`, `기록 2`…). 스냅샷과 같은 기계를 쓰되 목록만
    /// <c>developHistory</c> 로 다릅니다.
    /// </summary>
    public DevelopEditResult RecordHistory(LibraryFrameSnapshot? frame, string label) =>
        EditFrameRecord(frame, record => LibraryVersions.Capture(
            record,
            Guid.NewGuid().ToString("D"),
            label,
            DateTimeOffset.UtcNow,
            LibraryVersions.HistoryListName));

    /// <summary>macOS <c>applyDevelopHistory</c> — 골라 둔 기록의 recipe 로 되돌립니다.</summary>
    public DevelopEditResult ApplyHistory(LibraryFrameSnapshot? frame, string entryId) =>
        EditFrameRecord(frame, record => LibraryVersions.Restore(
            record,
            entryId,
            LibraryVersions.HistoryListName));

    public DevelopEditResult SetAppMetadata(
        LibraryFrameSnapshot? frame,
        Func<AppMetadataOverlay, AppMetadataOverlay> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }

        AppMetadataOverlay current = frame.AppMetadata ?? new AppMetadataOverlay();
        AppMetadataOverlay next = update(current).Normalized();
        if (next.IsEmpty)
        {
            return EditFrameRecord(frame, record => AppMetadataWriter.Apply(record, null));
        }
        next = next with
        {
            Revision = current.Revision + 1,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        return EditFrameRecord(frame, record => AppMetadataWriter.Apply(record, next));
    }

    public bool CopyDevelopSettings(LibraryFrameSnapshot? frame)
    {
        if (frame is null)
        {
            return false;
        }
        CopiedSettings = frame;
        CopiedSettingsSourceName = frame.DisplayName ?? Path.GetFileName(frame.SourcePath);
        return true;
    }

    public DevelopEditResult PasteDevelopSettings(LibraryFrameSnapshot? destination)
    {
        if (CopiedSettings is not { } source)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        if (PasteScope.IsEmpty)
        {
            return new(LibraryFrameError.None, false);
        }
        if (destination is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        return EditFrameRecord(
            destination,
            record => DevelopSettingsTransfer.Paste(record, source, destination, PasteScope));
    }

    public void OpenUserPresets(string? path)
    {
        userPresetPath = path;
        UserPresets = string.IsNullOrWhiteSpace(path)
            ? []
            : DevelopUserPresetStore.Load(path);
    }

    public DevelopUserPreset? SaveUserPreset(LibraryFrameSnapshot? frame, string name)
    {
        if (frame is null ||
            string.IsNullOrWhiteSpace(name) ||
            DevelopUserPresetStore.Capture(frame, name.Trim()) is not { } preset)
        {
            return null;
        }
        UserPresets = [.. UserPresets, preset];
        PersistUserPresets();
        return preset;
    }

    public DevelopEditResult ApplyUserPreset(LibraryFrameSnapshot? destination, Guid id)
    {
        if (UserPresets.FirstOrDefault(preset => preset.Id == id) is not { } chosen ||
            destination is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        return EditFrameRecord(
            destination,
            record => DevelopUserPresetStore.Apply(record, chosen, destination));
    }

    public bool DeleteUserPreset(Guid id)
    {
        int before = UserPresets.Count;
        UserPresets = [.. UserPresets.Where(preset => preset.Id != id)];
        if (UserPresets.Count == before)
        {
            return false;
        }
        PersistUserPresets();
        return true;
    }

    private DevelopEditResult EditFrameRecord(
        LibraryFrameSnapshot? frame,
        Func<System.Text.Json.Nodes.JsonObject, LibraryFrameWriteResult> edit)
    {
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        LibraryFrameError error = host.EditFrameRecord(frame.Id, edit);
        return new(error, error == LibraryFrameError.None);
    }

    private void PersistUserPresets()
    {
        if (userPresetPath is { Length: > 0 } path)
        {
            _ = DevelopUserPresetStore.Save(path, UserPresets);
        }
    }
}
