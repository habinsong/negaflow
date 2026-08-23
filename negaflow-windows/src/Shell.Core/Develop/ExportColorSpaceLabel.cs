using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 색 공간의 화면 이름입니다. macOS <c>ExportColorSpace.uiLabel</c> 과 같습니다.
/// </summary>
/// <remarks>
/// 색 공간 이름은 고유명사라 번역하지 않습니다 — macOS 도 여섯 언어 모두에서 같은 글자를
/// 냅니다. 다만 <c>enum.ToString()</c> 을 그대로 쓰면 "Srgb"·"AdobeRgb" 처럼 코드 이름이
/// 새어 나오므로, 표기를 한곳에서만 정합니다.
/// </remarks>
public static class ExportColorSpaceLabel
{
    public static string For(ExportColorSpace space) => space switch
    {
        ExportColorSpace.DisplayP3 => "Display P3",
        ExportColorSpace.AdobeRgb => "Adobe RGB",
        _ => "sRGB",
    };
}
