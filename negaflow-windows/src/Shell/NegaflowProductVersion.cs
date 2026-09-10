using System;

namespace Negaflow.Shell;

/// <summary>
/// macOS <c>NegaflowProductVersion</c> — 앱 정보, 빠른 시작, 내보내기 사이드카가 함께 읽는
/// 제품 판 하나입니다.
///
/// macOS 는 <c>CFBundleShortVersionString</c> 을 그대로 보여 주므로 세 자리입니다. MSIX 신원과
/// 어셈블리 판은 네 자리를 강제하지만 그 네 번째 자리는 저장소 어디에서도 오지 않습니다 —
/// `build-release.ps1` 이 <c>ProductVersion.txt</c> 뒤에 `.0` 을 붙여 만들어 냅니다. 그것을
/// 화면이나 사이드카에 그대로 흘리면 같은 빌드가 mac 에서는 `1.1.6`, Windows 에서는
/// `1.1.6.0` 이라고 말합니다.
/// </summary>
internal static class NegaflowProductVersion
{
    /// <summary>패키지 신원의 앞 세 자리. 그 자리가 <c>ProductVersion.txt</c> 값입니다.</summary>
    internal static string Current { get; } = Resolve();

    private static string Resolve()
    {
        try
        {
            Windows.ApplicationModel.PackageVersion version =
                Windows.ApplicationModel.Package.Current.Id.Version;
            return $"{version.Major}.{version.Minor}.{version.Build}";
        }
        catch (Exception)
        {
            // 패키지 밖에서 돌 때입니다 - macOS 가 번들이 앱이 아니면 ProductVersion.txt 로
            // 물러나는 자리와 같습니다. 어셈블리 판도 같은 파일에서 왔습니다.
            Version? assembly = typeof(NegaflowProductVersion).Assembly.GetName().Version;
            return assembly is null
                ? "0.0.0"
                : $"{assembly.Major}.{assembly.Minor}.{assembly.Build}";
        }
    }
}
