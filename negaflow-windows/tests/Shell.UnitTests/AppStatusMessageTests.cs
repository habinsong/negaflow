using Negaflow.Shell.Diagnostics;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 하단 상태바 가운데 메시지(macOS <c>StatusMessageCenter</c>)입니다. 셸이 늦게 뜨는 큰 라이브러리에서
/// 열기 알림이 시작 로고 뒤에서 지나가 버렸습니다 — 화면이 보인 순간부터 다시 세야 합니다.
/// </summary>
internal static class AppStatusMessageTests
{
    internal static void Run()
    {
        AppStatusMessage center = new();
        int changes = 0;
        center.Changed += (_, _) => changes++;

        center.Reannounce();
        Check(changes == 0, "status_message_reannounce_without_message_is_silent");

        center.Post("  라이브러리 복원: 사진 138장  ");
        Check(center.Message == "라이브러리 복원: 사진 138장" && changes == 1,
            "status_message_post_trims_and_notifies");
        DateTimeOffset posted = center.PostedAt;
        Thread.Sleep(20);
        center.Reannounce();
        Check(center.PostedAt > posted && changes == 2 &&
              center.Message == "라이브러리 복원: 사진 138장",
            "status_message_reannounce_restarts_the_clock_once_the_screen_shows");
    }
}
