import Foundation

// 가져온 파일의 IR 짝을 라이브러리 상태에 반영하는 두 가지 경로.
//   attachInfraredToExistingFrames — 본 스캔이 이미 프레임으로 있을 때 IR 만 붙인다.
//   repairStrayInfraredFrames      — 예전 가져오기가 사진으로 세워 둔 IR 프레임을 접는다.
// 둘 다 원본 파일은 건드리지 않는다(카탈로그 참조만 바뀐다).
extension AppModel {

    /// 짝의 본 스캔이 이미 라이브러리에 있으면 그 프레임에 IR 을 붙이고 맵에서 소비한다.
    /// 남은 항목은 이번 가져오기에서 새로 만들 프레임의 몫이다.
    func attachInfraredToExistingFrames(_ infraredByBaseIdentity: inout [String: URL]) {
        guard !infraredByBaseIdentity.isEmpty else { return }
        var didAttach = false
        for frame in frames {
            let identity = Self.importIdentity(frame.rawScanURL)
            guard let infraredURL = infraredByBaseIdentity[identity] else { continue }
            infraredByBaseIdentity.removeValue(forKey: identity)
            guard frame.infraredScanURL == nil else { continue }
            frame.attachInfraredScan(infraredURL)
            // 이 세션에서 이미 "IR 없음"으로 지나갔을 수 있다 — 다시 시도할 수 있게 표시를 푼다.
            rearmInfraredAutoClean(frame)
            didAttach = true
            if frame.id == selectedFrameID { scheduleInfraredCleanForSelection(frame) }
        }
        if didAttach { scheduleLibrarySave() }
    }

    /// IR 짝짓기를 모르던 가져오기가 IR 채널을 사진 한 장으로 세워 둔 흔적을 정리한다.
    /// 짝이 되는 본 스캔 프레임에 IR 을 붙이고, IR 프레임은 카탈로그에서만 뺀다(파일은 유지).
    ///
    /// 사용자가 하지 않은 정리라 undo 스택에 올리지 않는다 — 원본 IR 파일은 그대로 남아 있고,
    /// 이 상태가 본래 의도된 상태다.
    func repairStrayInfraredFrames() {
        guard allowsLibraryMutation else { return }
        let pairing = InfraredImportPairing.resolve(frames.map(\.rawScanURL))
        guard !pairing.pairedInfraredURLs.isEmpty else { return }
        var infraredByBaseIdentity = pairing.infraredByBaseIdentity
        attachInfraredToExistingFrames(&infraredByBaseIdentity)
        let strayIdentities = Set(pairing.pairedInfraredURLs.map(Self.importIdentity))
        let strayFrames = frames.filter {
            strayIdentities.contains(Self.importIdentity($0.rawScanURL))
        }
        guard !strayFrames.isEmpty else { return }
        removeFramesFromLibrary(strayFrames, undoable: false)
    }
}
