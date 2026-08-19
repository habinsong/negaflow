namespace Negaflow.Catalog;

/// <summary>
/// 디렉터리 승격(이름 바꾸기)이 잠깐 막혔을 때 다시 걸 조건입니다.
/// </summary>
/// <remarks>
/// <para>
/// Windows 는 폴더 안에 열린 파일이 하나라도 있으면 <c>MoveFileExW</c> 를
/// <c>ERROR_ACCESS_DENIED</c>(5) 또는 <c>ERROR_SHARING_VIOLATION</c>(32) 로 거절합니다.
/// 우리 코드는 쓰기·읽기 스트림을 모두 닫고 부르지만, 방금 쓴 파일을 바이러스 검사기나
/// 인덱서가 몇 ms 동안 붙잡고 있는 일이 실제로 있습니다.
/// </para>
/// <para>
/// 실측(2026-08-19, x64 Release): 카탈로그 시험을 12회 돌려 5회가 깨졌고, 계측을 붙여
/// 잡은 실패는 전부 <c>promote failed win32=5</c> 였습니다. 격리된 %TEMP% 에서 같은 순서를
/// 2,000회 돌렸을 때는 한 번도 나지 않았습니다 — 저장소 <c>out\build</c> 트리처럼 검사기가
/// 자주 훑는 자리에서만 났습니다.
/// </para>
/// <para>
/// 그래서 <b>이 두 오류에 한해</b> 짧게 물러섰다가 다시 겁니다. 다른 오류는 그대로
/// 실패입니다 — 권한·경로·존재 여부 문제를 재시도로 덮지 않기 위해서입니다. 대상 경로는
/// 부르는 쪽이 새 GUID 로 만들고 원본은 실패해도 그대로 남으므로, 다시 거는 것이 값을
/// 바꾸지 않습니다.
/// </para>
/// </remarks>
internal static class StorageMoveRetryPolicy
{
    internal const int AccessDenied = 5;

    internal const int SharingViolation = 32;

    /// <summary>합이 255 ms 입니다. 검사기가 파일을 놓는 데 걸리는 시간보다 넉넉합니다.</summary>
    private static readonly int[] BackoffMilliseconds = [1, 2, 4, 8, 16, 32, 64, 128];

    internal static int MaximumRetries => BackoffMilliseconds.Length;

    internal static bool ShouldRetry(int win32Error, int attempt) =>
        attempt < BackoffMilliseconds.Length &&
        win32Error is AccessDenied or SharingViolation;

    internal static void Wait(int attempt) =>
        Thread.Sleep(BackoffMilliseconds[attempt]);
}
