using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 사용자가 저장해 둔 현상 설정입니다. macOS <c>DevelopUserPreset</c> 과 같으며 프레임 하나의
/// 현상 레시피 전체를 담습니다.
/// </summary>
/// <param name="Recipe">
/// catalog frame record 와 같은 모양입니다. 새 직렬화기를 하나 더 만드는 대신 이미 검증된
/// reader/writer 를 그대로 쓰기 위해서이며, 그 덕에 저장·적용이 붙여넣기와 같은 코드를 지납니다.
/// 사진을 가리키는 값(id, 경로, 별점, 버전)은 들어 있지 않습니다.
/// </param>
public sealed record DevelopUserPreset(
    Guid Id,
    string Name,
    DateTimeOffset CreatedAt,
    JsonObject Recipe);

/// <summary>
/// 사용자 프리셋 목록을 파일 하나에 담습니다. macOS 는 UserDefaults 를 쓰지만 Windows 에서
/// 같은 자리는 앱 데이터 폴더의 JSON 입니다.
/// </summary>
public static class DevelopUserPresetStore
{
    /// <summary>
    /// 레시피만 담은 record 를 만들기 위한 자리표시자입니다. 실제 사진을 가리키지 않습니다.
    /// </summary>
    private const string RecipeFrameId = "user-preset";
    private const string RecipeSourcePath = @"C:\Negaflow\UserPreset";

    private static readonly JsonWriterOptions WriterOptions = new() { Indented = true };

    /// <summary>
    /// 프레임의 현상 레시피를 프리셋으로 뜹니다. 빈 record 에서 시작해 writer 로 채우므로
    /// 사진에 딸린 값이 딸려 들어올 길이 없습니다.
    /// </summary>
    public static DevelopUserPreset? Capture(LibraryFrameSnapshot frame, string name)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentException.ThrowIfNullOrWhiteSpace(name);

        JsonObject seed = new()
        {
            ["id"] = RecipeFrameId,
            [LibraryFrameReader.SourcePathName] = RecipeSourcePath,
            ["sourceKind"] = "scanner",
        };
        LibraryFrameWriteResult written = DevelopSettingsTransfer.Paste(
            seed,
            frame,
            frame,
            DevelopSettingsPasteScope.Preset);
        return written.FrameRecord is { } recipe
            ? new DevelopUserPreset(Guid.NewGuid(), name, DateTimeOffset.Now, recipe)
            : null;
    }

    /// <summary>프리셋을 프레임에 통째로 적용합니다. 범위를 나누지 않는 점이 붙여넣기와 다릅니다.</summary>
    public static LibraryFrameWriteResult Apply(
        JsonObject destinationRecord,
        DevelopUserPreset preset,
        LibraryFrameSnapshot destination)
    {
        ArgumentNullException.ThrowIfNull(destinationRecord);
        ArgumentNullException.ThrowIfNull(preset);
        ArgumentNullException.ThrowIfNull(destination);

        using JsonDocument document = JsonDocument.Parse(
            CatalogJson.SerializeCanonical(preset.Recipe));
        LibraryFrameReadResult read = LibraryFrameReader.Read(document.RootElement);
        return read.Frame is { } source
            ? DevelopSettingsTransfer.Paste(
                destinationRecord,
                source,
                destination,
                DevelopSettingsPasteScope.Preset)
            : LibraryFrameWriteResult.Failure(read.Error);
    }

    /// <summary>
    /// 읽지 못한 프리셋은 건너뜁니다. 목록 파일 하나가 깨졌다고 나머지 프리셋까지 잃게 하지
    /// 않습니다.
    /// </summary>
    public static IReadOnlyList<DevelopUserPreset> Load(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        try
        {
            if (!File.Exists(path))
            {
                return [];
            }
            using FileStream stream = File.OpenRead(path);
            using JsonDocument document = JsonDocument.Parse(stream);
            if (document.RootElement.ValueKind != JsonValueKind.Array)
            {
                return [];
            }
            List<DevelopUserPreset> presets = [];
            foreach (JsonElement entry in document.RootElement.EnumerateArray())
            {
                if (Parse(entry) is { } preset)
                {
                    presets.Add(preset);
                }
            }
            return presets;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            JsonException or NotSupportedException)
        {
            return [];
        }
    }

    /// <summary>
    /// 임시 파일에 다 쓴 뒤 바꿔치기합니다. 쓰는 도중 끊겨도 이전 목록이 남습니다.
    /// </summary>
    public static bool Save(string path, IReadOnlyList<DevelopUserPreset> presets)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        ArgumentNullException.ThrowIfNull(presets);

        string temporaryPath = path + ".tmp";
        try
        {
            if (Path.GetDirectoryName(path) is { Length: > 0 } directory)
            {
                Directory.CreateDirectory(directory);
            }

            JsonArray array = [];
            foreach (DevelopUserPreset preset in presets)
            {
                array.Add(new JsonObject
                {
                    ["id"] = preset.Id.ToString("D"),
                    ["name"] = preset.Name,
                    ["createdAt"] = preset.CreatedAt.ToString("O"),
                    ["recipe"] = preset.Recipe.DeepClone(),
                });
            }

            using (FileStream stream = File.Create(temporaryPath))
            using (var writer = new Utf8JsonWriter(stream, WriterOptions))
            {
                array.WriteTo(writer);
            }
            File.Move(temporaryPath, path, overwrite: true);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException)
        {
            try
            {
                File.Delete(temporaryPath);
            }
            catch (Exception cleanup) when (cleanup is IOException or UnauthorizedAccessException)
            {
                // 임시 파일을 못 지워도 본 파일은 온전합니다.
            }
            return false;
        }
    }

    private static DevelopUserPreset? Parse(JsonElement entry)
    {
        if (entry.ValueKind != JsonValueKind.Object ||
            !entry.TryGetProperty("id", out JsonElement idElement) ||
            !Guid.TryParse(idElement.GetString(), out Guid id) ||
            !entry.TryGetProperty("name", out JsonElement nameElement) ||
            nameElement.ValueKind != JsonValueKind.String ||
            nameElement.GetString() is not { Length: > 0 } name ||
            !entry.TryGetProperty("recipe", out JsonElement recipeElement) ||
            recipeElement.ValueKind != JsonValueKind.Object ||
            JsonNode.Parse(recipeElement.GetRawText()) is not JsonObject recipe)
        {
            return null;
        }
        DateTimeOffset createdAt =
            entry.TryGetProperty("createdAt", out JsonElement createdElement) &&
            createdElement.ValueKind == JsonValueKind.String &&
            DateTimeOffset.TryParse(createdElement.GetString(), out DateTimeOffset parsed)
                ? parsed
                : DateTimeOffset.MinValue;
        return new DevelopUserPreset(id, name, createdAt, recipe);
    }
}
