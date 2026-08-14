namespace Negaflow.Shell.Develop;

/// <summary>
/// 내보내기 파일명 패턴입니다. macOS <c>ExportNamingTemplate</c> 과 같은 중괄호 토큰 문법,
/// 같은 길이 한계, 같은 정규화 순서를 씁니다.
/// </summary>
/// <remarks>
/// macOS 는 아홉 개 토큰을 냅니다. 그중 <c>frame</c>·<c>date</c> 는 카탈로그가 아직 읽지 않는
/// 촬영 순번과 촬영 일시를 필요로 하므로 여기서는 내지 않습니다 — 무엇으로도 치환되지 않는
/// 토큰을 목록에 올리면 사용자가 빈 파일명을 만들게 됩니다. 나머지 일곱은 macOS 와 같은 이름·
/// 같은 자리수·같은 치환 규칙입니다.
/// </remarks>
public static class ExportNamingTemplate
{
    public const string DefaultPattern = "{name}";

    public const string PhotoNameSequencePattern = "{name}-{sequence}";

    public const string SequenceOnlyPattern = "{sequence}";

    /// <summary>패턴 자체의 UTF-8 바이트 한계입니다. macOS 와 같은 값입니다.</summary>
    public const int MaximumPatternBytes = 160;

    /// <summary>치환이 끝난 이름의 UTF-8 바이트 한계입니다. 확장자는 여기에 들어가지 않습니다.</summary>
    public const int MaximumRenderedBytes = 200;

    /// <summary>목록 순서는 macOS 와 같습니다.</summary>
    public static IReadOnlyList<string> Tokens { get; } =
        ["roll", "name", "preset", "sequence", "rollcode", "film", "camera"];

    public static bool UsesSequence(string? pattern) =>
        Normalize(pattern).Contains("{sequence}", StringComparison.Ordinal);

    /// <summary>앞뒤 공백을 걷고 바이트 한계까지 자릅니다.</summary>
    public static string Normalize(string? pattern)
    {
        string value = (pattern ?? string.Empty).Trim();
        while (System.Text.Encoding.UTF8.GetByteCount(value) > MaximumPatternBytes)
        {
            value = value[..^1];
        }
        return value;
    }

    /// <summary>알려진 토큰만 쓰고 짝이 맞는 패턴인지 봅니다.</summary>
    public static bool IsValid(string? pattern)
    {
        ReadOnlySpan<char> remainder = Normalize(pattern);
        if (remainder.IsEmpty)
        {
            return false;
        }
        while (true)
        {
            int open = remainder.IndexOf('{');
            if (open < 0)
            {
                break;
            }
            ReadOnlySpan<char> tail = remainder[open..];
            int close = tail.IndexOf('}');
            if (close < 0)
            {
                return false;
            }
            string token = tail[1..close].ToString();
            if (!Tokens.Contains(token))
            {
                return false;
            }
            remainder = tail[(close + 1)..];
        }
        // 여는 괄호 없이 남은 닫는 괄호는 사용자가 토큰을 잘못 적었다는 뜻입니다.
        return remainder.IndexOf('}') < 0;
    }

    /// <summary>치환한 이름입니다. 패턴이 잘못됐거나 결과가 비면 null 입니다.</summary>
    public static string? Render(string? pattern, ExportNamingContext context)
    {
        if (!IsValid(pattern))
        {
            return null;
        }
        string rendered = Normalize(pattern)
            .Replace("{roll}", SanitizeComponent(context.Roll), StringComparison.Ordinal)
            .Replace("{name}", SanitizeComponent(context.FrameName), StringComparison.Ordinal)
            .Replace("{preset}", SanitizeComponent(context.Preset), StringComparison.Ordinal)
            .Replace("{sequence}", Padded(context.Sequence), StringComparison.Ordinal)
            .Replace("{rollcode}", SanitizeComponent(context.RollCode), StringComparison.Ordinal)
            .Replace("{film}", SanitizeComponent(context.Film), StringComparison.Ordinal)
            .Replace("{camera}", SanitizeComponent(context.Camera), StringComparison.Ordinal);
        rendered = SanitizeComponent(rendered);
        while (System.Text.Encoding.UTF8.GetByteCount(rendered) > MaximumRenderedBytes)
        {
            rendered = rendered[..^1];
        }
        return rendered.Length == 0 ? null : rendered;
    }

    private static string Padded(int value) => Math.Max(0, value).ToString("D4");

    /// <summary>경로 한 칸으로 쓸 수 있게 다듬습니다. 파일 이름에 못 쓰는 글자는 밑줄이 됩니다.</summary>
    public static string SanitizeComponent(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return string.Empty;
        }
        Span<char> buffer = value.Length <= 260 ? stackalloc char[value.Length] : new char[value.Length];
        ReadOnlySpan<char> invalid = Path.GetInvalidFileNameChars();
        for (int index = 0; index < value.Length; ++index)
        {
            buffer[index] = invalid.Contains(value[index]) ? '_' : value[index];
        }
        return new string(buffer).Trim();
    }
}

/// <summary>파일명 토큰을 채울 값입니다.</summary>
public readonly record struct ExportNamingContext(
    string FrameName,
    string Preset,
    int Sequence)
{
    /// <summary>롤 이름입니다. 롤에 속하지 않으면 빈 문자열이며 토큰은 사라집니다.</summary>
    public string Roll { get; init; } = string.Empty;

    /// <summary>네거티브 봉투에 적는 코드입니다.</summary>
    public string RollCode { get; init; } = string.Empty;

    /// <summary>촬영 기록의 필름 이름입니다. frame 값이 없으면 롤 값이 옵니다.</summary>
    public string Film { get; init; } = string.Empty;

    public string Camera { get; init; } = string.Empty;
}
