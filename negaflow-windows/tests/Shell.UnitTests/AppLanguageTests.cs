using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 언어 고르개입니다. 리소스가 없는 언어를 고르면 화면이 영어로 돌아가므로, 목록에 내는 것과
/// 되돌리는 것을 함께 확인합니다.
/// </summary>
internal static class AppLanguageTests
{
    public static void Run()
    {
        VerifyLanguageList();
    }

    private static void VerifyLanguageList()
    {
        // 언어 목록은 리소스가 있는 것만 냅니다.
        Check(AppLanguages.All.Count == 7, "language_list_has_system_plus_six");
        Check(AppLanguages.All[0] == AppLanguages.System, "language_system_comes_first");
        Check(
            AppLanguages.Normalize("ko-KR") == "ko-KR" &&
                AppLanguages.Normalize("KO-kr") == "KO-kr",
            "language_accepts_a_known_tag");
        // 리소스가 없는 언어를 고르면 화면이 영어로 돌아갑니다 — 시스템으로 되돌립니다.
        Check(
            AppLanguages.Normalize("es-ES") == AppLanguages.System &&
                AppLanguages.Normalize(null) == AppLanguages.System,
            "language_unknown_falls_back_to_system");
    }
}
