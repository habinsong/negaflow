namespace Negaflow.Interop;

/// <summary>
/// WIC 를 타는 네이티브 일을 <b>MTA 스레드에서</b> 돌립니다.
/// </summary>
/// <remarks>
/// **STA 에서는 WIC 경로가 통째로 죽습니다.**
///
/// 네이티브 디코더·인코더는 먼저 <c>CoInitializeEx(COINIT_MULTITHREADED)</c> 를 겁니다. 부르는
/// 스레드가 이미 STA 면 COM 이 <c>RPC_E_CHANGED_MODE</c> 를 돌려주고, 코드는
/// <c>com_apartment_mismatch</c> 로 물러납니다 — 파일이 멀쩡해도 한 줄도 읽지 못하고, 화면에는
/// 그저 "읽을 수 없음" 으로 보입니다. WinUI 의 UI 스레드가 바로 그 STA 입니다.
///
/// 실기에서 이것이 IR 로 드러났습니다: 배치의 <b>첫 장만</b> 늘 실패했고
/// (<c>visible-full-decode-failed(밑=4)</c> = <c>com_apartment_mismatch</c>), 같은 파일을
/// 콘솔에서 읽으면 언제나 성공했습니다. 첫 장은 아직 UI 스레드에서 이어지고, 둘째 장부터는
/// 스캔을 기다리며 한 번 끊긴 뒤라 워커에서 이어지기 때문입니다.
///
/// 같은 함정이 <b>현상 디코드·미리보기·내보내기 인코드·GrainMend 굽기·검출</b>에 전부 있습니다.
/// 한 자리에서 막습니다. 이미 MTA 면 아무 일도 하지 않으므로 값이 들지 않습니다.
///
/// 옮겨 도는 동안 부르는 스레드는 막힙니다. 그것은 STA 에서만 일어나고, 그 자리에서 대안은
/// <b>실패</b>뿐입니다 — 느린 것이 낫습니다. 애초에 UI 스레드에서 47MB TIFF 를 펴는 것이
/// 잘못이므로, 이 길로 들어오는 것 자체가 고쳐야 할 신호입니다.
/// </remarks>
public static class NativeApartment
{
    /// <summary>지금 스레드가 STA 인가. 그렇다면 WIC 를 직접 부르면 안 됩니다.</summary>
    public static bool IsSingleThreaded =>
        Thread.CurrentThread.GetApartmentState() == ApartmentState.STA;

    /// <summary>필요하면 MTA 스레드로 옮겨 돌립니다.</summary>
    public static T Run<T>(Func<T> work)
    {
        ArgumentNullException.ThrowIfNull(work);
        return IsSingleThreaded ? Task.Run(work).GetAwaiter().GetResult() : work();
    }

    /// <summary>필요하면 MTA 스레드로 옮겨 돌립니다.</summary>
    public static void Run(Action work)
    {
        ArgumentNullException.ThrowIfNull(work);
        if (IsSingleThreaded)
        {
            Task.Run(work).GetAwaiter().GetResult();
            return;
        }
        work();
    }
}
