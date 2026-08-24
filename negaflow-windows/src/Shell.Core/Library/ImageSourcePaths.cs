namespace Negaflow.Shell;

/// <summary>가져오기가 파일 경로만 보고 내릴 수 있는 판정입니다.</summary>
/// <remarks>
/// <para>
/// ☠️ <b>확장자 allowlist 를 여기에 다시 만들면 안 됩니다.</b> 예전에 31개짜리 목록이
/// 있었고, 그것이 설치된 codec 이 실제로 읽을 수 있는 파일을 picker 와 <c>FrameImport</c>
/// 앞단에서 막았습니다. 목록은 실제 디코더보다 <b>항상</b> 뒤처집니다. 목록을 지운 뒤에도
/// 죽은 채로 남아 있었기에 함께 지웠습니다 — 남겨 두면 다음 사람이 "이미 있네" 하고 다시
/// 그 목록으로 거릅니다.
/// </para>
/// <para>
/// 실제 raster decode 가능 여부는 <c>LibrarySourceMetadataReader</c> 가 파일을 열어서
/// 판정합니다. 그 뒤에는 두 디코더가 있습니다.
/// </para>
/// <list type="number">
///   <item>Windows 내장 WIC codec — BMP·GIF·ICO·JPEG·JPEG XR·PNG·TIFF·HD Photo·DDS
///   아홉 개입니다. <b>카메라 RAW 은 여기 없습니다</b>(Microsoft 공식 WIC 문서).
///   RAW 은 Microsoft Store 의 별도 무료 패키지 <c>Raw Image Extension</c> 이며 선탑재가
///   보장되지 않습니다.</item>
///   <item>함께 배포하는 <c>libraw.dll</c> — 1번이 못 여는 카메라 RAW 을 대신 현상합니다.
///   macOS 는 ImageIO 에 RAW 이 들어 있어 맥 사용자는 이 문제를 겪지 않으므로, 이 대체가
///   없으면 같은 파일이 맥에서만 열리는 parity 결함이 됩니다.</item>
/// </list>
/// </remarks>
public static class ImageSourcePaths
{
    public static bool UsesWicStandardDecoder(string path)
    {
        string extension = Path.GetExtension(path);
        return !IsTiff(extension);
    }

    public static bool IsSupportedImportPath(string path)
    {
        string extension = Path.GetExtension(path);
        // SVG 만 제품 계약으로 제외합니다. 무엇을 설치해도 raster 로 열리지 않기 때문이고,
        // 그 외에는 실제 decode 성공 여부가 판정합니다.
        return !string.Equals(extension, ".svg", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsTiff(string extension) =>
        string.Equals(extension, ".tif", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(extension, ".tiff", StringComparison.OrdinalIgnoreCase);
}
