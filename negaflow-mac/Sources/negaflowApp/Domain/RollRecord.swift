import Foundation

// MARK: - RollRecord (롤 단위 기록)
//
// 한 롤은 같은 카메라·렌즈·필름으로 찍힌다. 그 사실을 프레임마다 36번 적게 하는 대신 롤에 한 번
// 적고, 롤에 속한 프레임의 **비어 있는 칸만** 채운다. 이미 적어 둔 프레임 값은 건드리지 않는다 —
// 롤 중간에 렌즈를 바꾸는 일이 실제로 있기 때문이다.
//
// 롤 코드는 파일 이름 토큰(`{rollcode}`)으로도 쓴다. 네거티브 봉투에 적는 코드와 내보낸 파일
// 이름이 같아야 나중에 필름과 파일을 맞출 수 있다.
struct RollRecord: Codable, Equatable, Sendable {
    var code: String?
    var shot: FilmShotMetadata?
    var notes: String?

    init(code: String? = nil, shot: FilmShotMetadata? = nil, notes: String? = nil) {
        self.code = AppMetadataOverlay.normalizedText(code)
        self.shot = shot.flatMap { $0.isEmpty ? nil : $0 }
        self.notes = AppMetadataOverlay.normalizedText(notes)
    }

    var isEmpty: Bool {
        code == nil && notes == nil && (shot?.isEmpty ?? true)
    }

    var isValid: Bool {
        [code, notes].allSatisfy {
            $0.map { !$0.isEmpty && $0.utf8.count <= AppMetadataOverlay.maximumTextBytes } ?? true
        } && (shot.map { !$0.isEmpty && $0.isValid } ?? true)
    }

    /// 프레임의 촬영 기록에서 비어 있는 칸만 롤 값으로 채운다. 채울 것이 없으면 nil.
    func filling(_ frameShot: FilmShotMetadata?) -> FilmShotMetadata? {
        guard let shot else { return nil }
        var merged = frameShot ?? FilmShotMetadata()
        merged.cameraMake = merged.cameraMake ?? shot.cameraMake
        merged.cameraModel = merged.cameraModel ?? shot.cameraModel
        merged.lensModel = merged.lensModel ?? shot.lensModel
        merged.filmStock = merged.filmStock ?? shot.filmStock
        merged.isoSpeed = merged.isoSpeed ?? shot.isoSpeed
        merged.exposureTimeSeconds = merged.exposureTimeSeconds ?? shot.exposureTimeSeconds
        merged.fNumber = merged.fNumber ?? shot.fNumber
        merged.focalLengthMM = merged.focalLengthMM ?? shot.focalLengthMM
        return merged == frameShot ? nil : merged
    }
}
