using System.Text.Json;
using System.Text.Json.Serialization;

namespace Negaflow.Catalog;

/// <summary>
/// macOS <c>LookPreset</c> 과 같은 룩 프로파일입니다. catalog 행이 아니라 파일이며 파일명
/// stem 이 곧 id 입니다.
/// </summary>
public sealed record LookPreset(
    string Id,
    string Name,
    int Version,
    IReadOnlyList<FilmType> FilmTypes,
    LookPresetTone Tone,
    LookPresetColor Color,
    LookPresetTexture Texture)
{
    /// <summary>
    /// 프리셋이 정하는 현상 값입니다. macOS <c>LookPreset.baseParameters</c> 와 같은 매핑이며
    /// 두 곳이 미묘합니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// <c>highlightRollOff</c> 는 <b>부호를 뒤집어</b> <c>highlight</c> 에 넣습니다. rollOff 가
    /// 양수면 명부를 shoulder 로 눌러 보호한다는 뜻인데, <c>highlight</c> 의 일반 규약은
    /// 양수가 명부를 밝히는 것이라 그대로 넣으면 이름과 정반대로 동작합니다. macOS 가 과거에
    /// 실제로 겪고 고친 자리입니다.
    /// </para>
    /// <para><c>midtoneLift</c> 는 노출에 0.1 을 곱해 더합니다.</para>
    /// </remarks>
    public ToneAdjustment BaseTone => new(
        Exposure: Tone.Exposure + (Tone.MidtoneLift ?? 0.0) * 0.1,
        Contrast: Tone.Contrast,
        CurveHighlights: 0.0,
        CurveLights: 0.0,
        CurveDarks: 0.0,
        CurveShadows: 0.0,
        Density: Tone.Density,
        Highlight: -Tone.HighlightRollOff,
        Shadow: Tone.BlackSoftness,
        Whites: 0.0,
        Blacks: 0.0);

    public bool AppliesTo(FilmType filmType) => FilmTypes.Contains(filmType);
}

public sealed record LookPresetTone(
    double Exposure,
    double Density,
    double Contrast,
    double HighlightRollOff,
    double BlackSoftness,
    double? MidtoneLift);

public sealed record LookPresetColor(
    double Warmth,
    double Tint,
    double ColorDepth,
    double Saturation);

public sealed record LookPresetTexture(double Grain, double Sharpness, double Halation);

/// <summary>
/// <c>assets/presets</c> 의 프로파일을 읽습니다. macOS 와 같은 여섯 종이며 순서도 같습니다.
/// </summary>
public static class PresetRegistry
{
    /// <summary>macOS <c>PresetRegistry.loadAll</c> 과 같은 이름·같은 순서입니다.</summary>
    public static IReadOnlyList<string> BundledIds { get; } =
        ["neutral", "rich-neutral", "soft-print", "clear-chrome", "warm-lab", "deep-slide"];

    /// <summary>
    /// 읽지 못한 프로파일은 건너뜁니다 — 하나가 깨졌다고 나머지 룩까지 못 쓰게 만들지
    /// 않습니다. 무엇이 빠졌는지는 목록 길이로 드러납니다.
    /// </summary>
    public static IReadOnlyList<LookPreset> LoadAll(string directory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        List<LookPreset> presets = [];
        foreach (string id in BundledIds)
        {
            if (Load(Path.Combine(directory, id + ".json"), id) is { } preset)
            {
                presets.Add(preset);
            }
        }
        return presets;
    }

    public static LookPreset? Load(string path, string id)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }
            using FileStream stream = File.OpenRead(path);
            return Parse(JsonDocument.Parse(stream).RootElement, id);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            JsonException or NotSupportedException)
        {
            return null;
        }
    }

    internal static LookPreset? Parse(JsonElement root, string id)
    {
        if (root.ValueKind != JsonValueKind.Object ||
            !root.TryGetProperty("name", out JsonElement nameElement) ||
            nameElement.ValueKind != JsonValueKind.String ||
            nameElement.GetString() is not { Length: > 0 } name)
        {
            return null;
        }

        List<FilmType> filmTypes = [];
        if (root.TryGetProperty("filmTypes", out JsonElement types) &&
            types.ValueKind == JsonValueKind.Array)
        {
            foreach (JsonElement entry in types.EnumerateArray())
            {
                if (entry.ValueKind == JsonValueKind.String &&
                    ParseFilmType(entry.GetString()) is { } filmType)
                {
                    filmTypes.Add(filmType);
                }
            }
        }
        // 호환 목록이 비면 어느 필름에도 걸리지 않아 조용히 사라집니다. 그런 프로파일은 거부합니다.
        if (filmTypes.Count == 0)
        {
            return null;
        }

        JsonElement tone = Section(root, "tone");
        JsonElement color = Section(root, "color");
        JsonElement texture = Section(root, "texture");
        return new LookPreset(
            id,
            name,
            Number(root, "version") is { } version ? (int)version : 1,
            filmTypes,
            new LookPresetTone(
                Number(tone, "exposure") ?? 0.0,
                Number(tone, "density") ?? 0.0,
                Number(tone, "contrast") ?? 0.0,
                Number(tone, "highlightRollOff") ?? 0.0,
                Number(tone, "blackSoftness") ?? 0.0,
                Number(tone, "midtoneLift")),
            new LookPresetColor(
                Number(color, "warmth") ?? 0.0,
                Number(color, "tint") ?? 0.0,
                Number(color, "colorDepth") ?? 0.0,
                Number(color, "saturation") ?? 0.0),
            new LookPresetTexture(
                Number(texture, "grain") ?? 0.0,
                Number(texture, "sharpness") ?? 0.0,
                Number(texture, "halation") ?? 0.0));
    }

    private static JsonElement Section(JsonElement root, string name) =>
        root.TryGetProperty(name, out JsonElement section) &&
        section.ValueKind == JsonValueKind.Object
            ? section
            : default;

    private static double? Number(JsonElement owner, string name) =>
        owner.ValueKind == JsonValueKind.Object &&
        owner.TryGetProperty(name, out JsonElement value) &&
        value.ValueKind == JsonValueKind.Number &&
        value.TryGetDouble(out double parsed) &&
        double.IsFinite(parsed)
            ? parsed
            : null;

    private static FilmType? ParseFilmType(string? raw) => raw switch
    {
        "colorNegative" => FilmType.ColorNegative,
        "colorPositive" => FilmType.ColorPositive,
        "bwNegative" => FilmType.BlackAndWhiteNegative,
        "bwPositive" => FilmType.BlackAndWhitePositive,
        _ => null,
    };
}
