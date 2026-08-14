namespace Negaflow.Interop;

/// <summary>
/// 색역을 벗어나는 화소를 표시할 수 있는지 묻습니다.
/// </summary>
/// <remarks>
/// 판정은 Windows 의 ICM 이 하는 진짜 gamut-check 변환입니다. 행렬 뒤 클리핑으로 근사하지
/// 않습니다 — 근사하면 같은 그림에서 macOS 와 다른 화소가 표시되어, 이식이 아니라 다른
/// 기능이 됩니다. 판정할 수 없으면 <b>표시하지 않습니다.</b>
/// </remarks>
public static unsafe class NativeGamutCheck
{
    /// <summary>
    /// 이 색공간으로 색역 판정을 할 수 있는지입니다. 설정 화면이 색역 경고를 내주기 전에
    /// 묻는 자리입니다 — 계산할 수 없는 경고를 켤 수 있게 두면 안 됩니다.
    /// </summary>
    public static bool IsSupported(ExportColorSpace space)
    {
        uint supported = 0U;
        uint status = NativeMethods.nf_gamut_check_supported_v1((uint)space, &supported);
        return status == 0U && supported != 0U;
    }
}
