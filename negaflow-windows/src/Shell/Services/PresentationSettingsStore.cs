using System.Text.Json;

namespace Negaflow.Shell;

public sealed class PresentationSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    private readonly string settingsPath;

    public PresentationSettingsStore(string? settingsPath = null)
    {
        this.settingsPath = settingsPath ?? DefaultSettingsPath();
        Current = Load(this.settingsPath);
    }

    public event EventHandler<ShellPreferences>? Changed;

    public ShellPreferences Current { get; private set; }

    public string? LastWriteError { get; private set; }

    public void Update(Func<ShellPreferences, ShellPreferences> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        ShellPreferences next = update(Current).Normalize();
        if (next == Current)
        {
            return;
        }

        Current = next;
        Save(next);
        Changed?.Invoke(this, next);
    }

    private static ShellPreferences Load(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return new ShellPreferences();
            }

            return (JsonSerializer.Deserialize<ShellPreferences>(File.ReadAllText(path), JsonOptions)
                ?? new ShellPreferences()).Normalize();
        }
        catch (JsonException)
        {
            return new ShellPreferences();
        }
        catch (IOException)
        {
            return new ShellPreferences();
        }
        catch (UnauthorizedAccessException)
        {
            return new ShellPreferences();
        }
    }

    private void Save(ShellPreferences preferences)
    {
        string temporaryPath = settingsPath + ".tmp";
        try
        {
            string? directory = Path.GetDirectoryName(settingsPath);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(preferences, JsonOptions));
            File.Move(temporaryPath, settingsPath, true);
            LastWriteError = null;
        }
        catch (IOException exception)
        {
            LastWriteError = exception.Message;
        }
        catch (UnauthorizedAccessException exception)
        {
            LastWriteError = exception.Message;
        }
    }

    private static string DefaultSettingsPath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Negaflow",
        "Development",
        "presentation.json");
}
