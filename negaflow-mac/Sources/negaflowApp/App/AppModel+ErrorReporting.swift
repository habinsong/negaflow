import Foundation

extension AppModel {
    /// 사용자 표시 오류를 한 곳에서 보고한다: 토스트 메시지(3초 뒤 사라짐) + 오류 상태(빨간 점) +
    /// 지속 기록(errorLog — 진단·빨간 점 팝오버가 읽음). 오류 경로는 statusMessage/scanPhase 를
    /// 직접 세팅하는 대신 이걸 호출한다.
    func reportError(_ message: String) {
        statusMessage = message
        scanPhase = .error
        errorLog.record(message)
    }
}
