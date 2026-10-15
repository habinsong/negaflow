/// 캔버스 스포이드가 찍는 대상. 두 스포이드는 같은 도구 슬롯(basePickerMode)과 캔버스 오버레이를
/// 공유한다 — 결함 도구의 자동/가이드(defectAutoMode)와 같은 방식.
enum EyedropperTarget: Equatable {
    /// 반전 전 raw 에서 미노광 베이스(Dmin)를 잰다.
    case filmBase
    /// 현상본에서 회색·흰색이어야 할 점으로 색온도·틴트를 맞춘다.
    case neutralWhiteBalance
}
