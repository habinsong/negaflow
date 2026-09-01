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
        // 저장된 설정을 고치는 자리는 여기 하나입니다. Normalize 는 저장할 때마다 도므로
        // **한 번만** 해야 하는 승격을 거기 두면 사용자의 선택을 매번 덮습니다.
        ShellPreferences loaded = Load(this.settingsPath);
        Current = loaded with { Backup = loaded.Backup.UpgradeDeadScheduleDefault() };
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
            Diagnostics.SettingsChangeLog.Write("update: no change");
            return;
        }

        Diagnostics.SettingsChangeLog.Write(Describe(Current, next));
        Current = next;
        Save(next);
        Changed?.Invoke(this, next);
    }

    /// <summary>무엇이 바뀌었는지 한 줄로 적습니다. 값 자체는 담지 않습니다.</summary>
    private static string Describe(ShellPreferences before, ShellPreferences after)
    {
        List<string> changed = [];
        if (before.CanvasBackground != after.CanvasBackground)
        {
            changed.Add($"canvasBackground={after.CanvasBackground}");
        }
        if (before.Appearance != after.Appearance)
        {
            changed.Add($"appearance={after.Appearance}");
        }
        if (before.DeveloperMode != after.DeveloperMode)
        {
            changed.Add($"developerMode={after.DeveloperMode}");
        }
        if (before.ScannerSimulatorEnabled != after.ScannerSimulatorEnabled)
        {
            changed.Add($"scannerSimulator={after.ScannerSimulatorEnabled}");
        }
        if (before.Disk != after.Disk)
        {
            changed.Add($"disk.mode={after.Disk.LocationMode}");
        }
        if (before.Shortcuts != after.Shortcuts)
        {
            changed.Add("shortcuts");
        }
        if (before.SelectedSettingsCategory != after.SelectedSettingsCategory)
        {
            changed.Add($"settingsTab={after.SelectedSettingsCategory}");
        }
        return changed.Count == 0
            ? "update: other"
            : "update: " + string.Join(", ", changed);
    }

    private static ShellPreferences Load(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return new ShellPreferences();
            }

            ShellPreferences stored =
                (JsonSerializer.Deserialize<ShellPreferences>(File.ReadAllText(path), JsonOptions)
                    ?? new ShellPreferences()).Normalize();
            // macOS 는 인화 출력 방식만 기억하지 않습니다 — 켜 둔 채 다음 실행에서 일반 출력인
            // 줄 알고 C-print 프루프가 걸린 결과를 받는 일을 막습니다.
            // 스캐너 시뮬레이터도 같은 이유로 실행마다 꺼진 채로 시작합니다.
            return stored with
            {
                Print = stored.Print.Restored(),
                ScannerSimulatorEnabled = false,
            };
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
