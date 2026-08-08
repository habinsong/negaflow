import Foundation

extension AppModel {
    /// 결함 기록은 디스크에 저장하지 않는다(종료 시 이미지에 굽고 기록은 폐기). catalog에도
    /// 결함 상태를 쓰지 않으므로 sidecar 세대 검사는 항상 통과한다. 과거에는 이 검사가 매
    /// 저장마다 sidecar JSON을 읽고 마스크 전체를 재지문해 MainActor를 수 초씩 정지시켰다.
    func defectSidecarsMatchCurrentFrames(_ snapshotFrames: [ScanFrame]) -> Bool {
        true
    }
}
