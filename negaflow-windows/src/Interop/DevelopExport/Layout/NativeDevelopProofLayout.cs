using System.Runtime.InteropServices;

namespace Negaflow.Interop;

// 미리보기 전용 소프트 프루프 레이아웃. 게시 요청에는 필드가 없다.

/// <summary>
/// 목적지 프로파일에서 읽어낸 용지와 잉크입니다.
/// </summary>
/// <remarks>
/// 프로파일을 읽는 것은 태그 테이블을 도는 일이라 프로파일을 고를 때 한 번만 합니다. 이후
/// 프레임마다 넘기는 것은 이 열 개의 숫자뿐입니다.
/// </remarks>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeSoftProofMediaV1
{
    internal uint StructSize;
    internal uint IsRgbOutputProfile;
    internal uint HasWhite;
    internal uint HasBlack;
    internal fixed float PaperWhiteRgb[3];
    internal fixed float BlackInkRgb[3];
}

/// <summary>
/// 미리보기에만 실리는 소프트 프루프입니다. 현상 요청에 들어 있지 않으므로 내보내기가 읽을
/// 필드 자체가 없습니다.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeSoftProofV1
{
    internal uint StructSize;
    internal uint Enabled;
    internal uint SimulatePaperAndBlackInk;
    internal uint WarnOutOfGamut;
    internal fixed float PaperWhiteRgb[3];
    internal fixed float BlackInkRgb[3];
}
