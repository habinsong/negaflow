using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

public sealed class WorkspacePresentationState
{
    private readonly PresentationSettingsStore settingsStore;

    public WorkspacePresentationState(PresentationSettingsStore settingsStore)
    {
        this.settingsStore = settingsStore;
        settingsStore.Changed += OnSettingsChanged;
    }

    public event EventHandler<ShellPreferences>? Changed;

    public ShellPreferences Current => settingsStore.Current;

    public void SelectWorkspace(WorkspaceModule module) =>
        settingsStore.Update(value => value with { SelectedWorkspace = module });

    public void SetAppearance(AppearanceMode appearance) =>
        settingsStore.Update(value => value with { Appearance = appearance });

    public void SetImageContentHashMode(ImageContentHashMode mode) =>
        settingsStore.Update(value => value with { ImageContentHash = mode });

    public void SelectSettingsCategory(SettingsCategory category) =>
        settingsStore.Update(value => value with { SelectedSettingsCategory = category });

    public void ToggleSidebar() => settingsStore.Update(value => value with
    {
        IsSidebarVisible = !value.IsSidebarVisible,
    });

    public void ToggleInspector() => settingsStore.Update(value => value with
    {
        IsInspectorVisible = !value.IsInspectorVisible,
    });

    public void ToggleFilmstrip() => settingsStore.Update(value => value with
    {
        IsFilmstripVisible = !value.IsFilmstripVisible,
    });

    public void SetSidebarWidth(double width) =>
        settingsStore.Update(value => value with { SidebarWidth = width });

    public void SetInspectorWidth(double width) =>
        settingsStore.Update(value => value with { InspectorWidth = width });

    public void SetLibraryControlsWidth(double width) =>
        settingsStore.Update(value => value with { LibraryControlsWidth = width });

    public void SetFilmstripHeight(double height) =>
        settingsStore.Update(value => value with { FilmstripHeight = height });

    public void UpdateExport(Func<ExportSettings, ExportSettings> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { Export = update(value.Export) });
    }

    public void UpdateSoftProof(Func<SoftProofPreferences, SoftProofPreferences> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { SoftProof = update(value.SoftProof) });
    }

    public void UpdateExportRecipes(Func<ExportRecipeLibrary, ExportRecipeLibrary> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { ExportRecipes = update(value.ExportRecipes) });
    }

    public void UpdateShortcuts(
        Func<Shortcuts.WorkflowShortcutMap, Shortcuts.WorkflowShortcutMap> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { Shortcuts = update(value.Shortcuts) });
    }

    public void UpdatePrint(Func<Print.PrintPreferences, Print.PrintPreferences> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { Print = update(value.Print) });
    }

    public void UpdateQuickExport(Func<QuickExportSettings, QuickExportSettings> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        settingsStore.Update(value => value with { QuickExport = update(value.QuickExport) });
    }

    private void OnSettingsChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        Changed?.Invoke(this, preferences);
    }
}
