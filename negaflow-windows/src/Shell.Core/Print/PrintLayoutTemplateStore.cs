using System.Text.Json;
using System.Text.Json.Serialization;

namespace Negaflow.Shell.Print;

/// <summary>
/// 템플릿이 담는 판 설정입니다. macOS <c>PrintLayoutTemplateSettings</c> 와 같은 항목이며,
/// **dpi 는 담지 않습니다** — macOS 도 유효성 검사에 300 을 고정으로 넣고 템플릿에는 안 넣습니다.
/// </summary>
public sealed record PrintLayoutTemplateSettings
{
    public PrintPaperSize PaperSize { get; init; } = PrintPaperSize.A4;

    public PrintPaperOrientation Orientation { get; init; } = PrintPaperOrientation.Automatic;

    public double MarginMm { get; init; } = 10;

    public PrintPerforationStyle PerforationStyle { get; init; } = PrintPerforationStyle.None;

    public PrintLayoutMode LayoutMode { get; init; } = PrintLayoutMode.SingleImage;

    public int ContactRows { get; init; } = 7;

    public int ContactColumns { get; init; } = 6;

    public double HorizontalSpacingMm { get; init; } = 4;

    public double VerticalSpacingMm { get; init; } = 4;

    public PrintPackageContentMode ContentMode { get; init; } = PrintPackageContentMode.Fit;

    public bool RotateToFit { get; init; }

    public bool RepeatOnePhotoPerPage { get; init; }

    public PrintPicturePackageTemplate PictureTemplate { get; init; } =
        PrintPicturePackageTemplate.OneLargeTwoSmall;

    public bool IsValid =>
        Enum.IsDefined(PaperSize) &&
        Enum.IsDefined(Orientation) &&
        Enum.IsDefined(PerforationStyle) &&
        Enum.IsDefined(LayoutMode) &&
        Enum.IsDefined(ContentMode) &&
        Enum.IsDefined(PictureTemplate) &&
        double.IsFinite(MarginMm) && MarginMm is >= 0 and <= 50 &&
        ContactRows is >= 1 and <= 20 &&
        ContactColumns is >= 1 and <= 20 &&
        double.IsFinite(HorizontalSpacingMm) && HorizontalSpacingMm is >= 0 and <= 50 &&
        double.IsFinite(VerticalSpacingMm) && VerticalSpacingMm is >= 0 and <= 50;

    /// <summary>지금 인화 설정에서 템플릿에 담을 부분만 떼어냅니다.</summary>
    public static PrintLayoutTemplateSettings From(PrintPreferences print)
    {
        ArgumentNullException.ThrowIfNull(print);
        return new PrintLayoutTemplateSettings
        {
            PaperSize = print.PaperSize,
            Orientation = print.Orientation,
            MarginMm = print.MarginMm,
            PerforationStyle = print.PerforationStyle,
            LayoutMode = print.LayoutMode,
            ContactRows = print.ContactRows,
            ContactColumns = print.ContactColumns,
            HorizontalSpacingMm = print.HorizontalSpacingMm,
            VerticalSpacingMm = print.VerticalSpacingMm,
            ContentMode = print.ContentMode,
            RotateToFit = print.RotateToFit,
            RepeatOnePhotoPerPage = print.RepeatOnePhotoPerPage,
            PictureTemplate = print.PictureTemplate,
        };
    }

    /// <summary>템플릿을 지금 설정 위에 얹습니다. 담지 않은 값(dpi·눈금자 등)은 그대로 둡니다.</summary>
    public PrintPreferences ApplyTo(PrintPreferences print)
    {
        ArgumentNullException.ThrowIfNull(print);
        return print with
        {
            PaperSize = PaperSize,
            Orientation = Orientation,
            MarginMm = MarginMm,
            PerforationStyle = PerforationStyle,
            LayoutMode = LayoutMode,
            ContactRows = ContactRows,
            ContactColumns = ContactColumns,
            HorizontalSpacingMm = HorizontalSpacingMm,
            VerticalSpacingMm = VerticalSpacingMm,
            ContentMode = ContentMode,
            RotateToFit = RotateToFit,
            RepeatOnePhotoPerPage = RepeatOnePhotoPerPage,
            PictureTemplate = PictureTemplate,
        };
    }
}

/// <summary>담아 둔 판 배치 하나입니다. macOS <c>PrintLayoutTemplate</c>.</summary>
public sealed record PrintLayoutTemplate
{
    /// <summary>macOS 와 같이 80자까지입니다.</summary>
    public const int MaximumNameLength = 80;

    public Guid Id { get; init; } = Guid.NewGuid();

    public string Name { get; init; } = string.Empty;

    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;

    public PrintLayoutTemplateSettings Settings { get; init; } = new();

    public bool IsValid =>
        Name.Length > 0 &&
        Name.Length <= MaximumNameLength &&
        string.Equals(Name, NormalizedName(Name), StringComparison.Ordinal) &&
        Settings.IsValid;

    public static string NormalizedName(string value)
    {
        string trimmed = (value ?? string.Empty).Trim();
        return trimmed.Length <= MaximumNameLength
            ? trimmed
            : trimmed[..MaximumNameLength];
    }
}

/// <summary>
/// 판 배치 템플릿 저장소입니다. macOS <c>PrintLayoutTemplateStore</c> 를 그대로 옮겼습니다 —
/// 봉투에 버전 1 을 담고, 읽을 때 **하나라도 어긋나면 통째로 버리고 쓰기를 잠급니다**
/// (`canModify = false`). 반쯤 깨진 파일 위에 덧쓰면 남은 것까지 잃기 때문입니다.
/// </summary>
public sealed class PrintLayoutTemplateStore
{
    /// <summary>macOS 와 같은 상한입니다.</summary>
    public const int MaximumTemplateCount = 100;

    private sealed record Envelope(int Version, IReadOnlyList<PrintLayoutTemplate> Templates);

    private const int CurrentVersion = 1;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    private readonly string path;

    public PrintLayoutTemplateStore(string filePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        path = filePath;
        (Templates, CanModify) = Load(filePath);
    }

    public IReadOnlyList<PrintLayoutTemplate> Templates { get; private set; }

    /// <summary>읽기에 실패했으면 덧쓰지 않습니다. macOS <c>canModify</c> 와 같습니다.</summary>
    public bool CanModify { get; }

    public PrintLayoutTemplate? Add(string name, PrintLayoutTemplateSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        string normalized = PrintLayoutTemplate.NormalizedName(name);
        if (!CanModify ||
            Templates.Count >= MaximumTemplateCount ||
            normalized.Length == 0 ||
            !settings.IsValid ||
            Templates.Any(template =>
                string.Equals(template.Name, normalized, StringComparison.OrdinalIgnoreCase)))
        {
            return null;
        }
        PrintLayoutTemplate added = new() { Name = normalized, Settings = settings };
        List<PrintLayoutTemplate> updated = [.. Templates, added];
        if (!Persist(updated))
        {
            return null;
        }
        Templates = updated;
        return added;
    }

    public bool Rename(Guid id, string name)
    {
        string normalized = PrintLayoutTemplate.NormalizedName(name);
        int index = Templates.ToList().FindIndex(template => template.Id == id);
        if (!CanModify ||
            normalized.Length == 0 ||
            index < 0 ||
            Templates.Any(template =>
                template.Id != id &&
                string.Equals(template.Name, normalized, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }
        List<PrintLayoutTemplate> updated = [.. Templates];
        updated[index] = updated[index] with { Name = normalized };
        if (!Persist(updated))
        {
            return false;
        }
        Templates = updated;
        return true;
    }

    public bool Delete(Guid id)
    {
        if (!CanModify)
        {
            return false;
        }
        List<PrintLayoutTemplate> updated =
            [.. Templates.Where(template => template.Id != id)];
        if (updated.Count == Templates.Count || !Persist(updated))
        {
            return false;
        }
        Templates = updated;
        return true;
    }

    private static (IReadOnlyList<PrintLayoutTemplate> Templates, bool CanModify) Load(string path)
    {
        if (!File.Exists(path))
        {
            return ([], true);
        }
        try
        {
            Envelope? envelope =
                JsonSerializer.Deserialize<Envelope>(File.ReadAllText(path), JsonOptions);
            if (envelope is null ||
                envelope.Version != CurrentVersion ||
                envelope.Templates.Count > MaximumTemplateCount ||
                envelope.Templates.Select(template => template.Id).Distinct().Count() !=
                    envelope.Templates.Count ||
                envelope.Templates
                    .Select(template => template.Name.ToLowerInvariant())
                    .Distinct()
                    .Count() != envelope.Templates.Count ||
                !envelope.Templates.All(template => template.IsValid))
            {
                return ([], false);
            }
            return (envelope.Templates, true);
        }
        catch (JsonException)
        {
            return ([], false);
        }
        catch (IOException)
        {
            return ([], false);
        }
        catch (UnauthorizedAccessException)
        {
            return ([], false);
        }
    }

    private bool Persist(IReadOnlyList<PrintLayoutTemplate> templates)
    {
        try
        {
            string? directory = Path.GetDirectoryName(path);
            if (directory is { Length: > 0 })
            {
                Directory.CreateDirectory(directory);
            }
            // macOS 는 원자적으로 씁니다. 중간에 끊기면 목록 전체를 잃습니다.
            string temporary = path + ".tmp";
            File.WriteAllText(
                temporary,
                JsonSerializer.Serialize(new Envelope(CurrentVersion, templates), JsonOptions));
            File.Move(temporary, path, overwrite: true);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }
}
