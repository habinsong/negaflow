import Foundation

extension AppModel {
    /// 현상이 원본을 디스크에서 읽기 직전에, 그 원본이 로컬에 있는지 확인하고 iCloud 가
    /// 사본을 내려놓았으면 먼저 받아온다.
    ///
    /// 렌더러가 dataless 파일을 열면 커널이 그 워커 스레드를 다운로드가 끝날 때까지 붙잡는다.
    /// 현상 슬롯은 개수가 정해져 있어서, 그렇게 물린 프레임 하나가 뒤따르는 모든 현상과
    /// 썸네일 갱신을 멈춰 세운다 — 사진 한 장을 골랐을 뿐인데 앱이 죽은 것처럼 보이던 경로다.
    ///
    /// 이미 메모리에 현상 결과가 있는 동안(슬라이더 드래그 등)에는 디스크를 읽지 않으므로
    /// 확인도 하지 않는다.
    func materializeDevelopSourceIfNeeded(_ frame: ScanFrame) async -> Bool {
        guard !frame.hasDevelopedOnce || frame.developedImage == nil else { return true }
        let url = frame.rawScanURL
        let isEvicted = await Task.detached(priority: .userInitiated) {
            ExportSourceMaterialization.isEvicted(url)
        }.value
        guard isEvicted else { return true }
        guard ownsFrame(frame), frame.rawScanURL == url else { return false }

        statusMessage = text(AppLocalizedPhrase.exportDownloadingSourcesFormat, "0", "1")
        let ready = await ExportSourceMaterialization.materialize([url], timeout: 120)
        guard ownsFrame(frame), frame.rawScanURL == url else { return false }
        if !ready {
            statusMessage = text(AppLocalizedPhrase.exportSourceDownloadFailed)
        }
        return ready
    }
}
