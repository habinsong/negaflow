import AppKit
import Chromabase
import Foundation

// 워터마크의 카메라·렌즈·노출 칸은 사용자가 적은 값이 먼저다. 비워 둔 칸만 그 사진의 촬영 기록
// (`FilmShotMetadata`)으로 채운다. 스캔 파일 EXIF 의 카메라는 스캐너라서 쓰지 않는다. 촬영 일시는
// 기록에 없으므로 채우지 않는다.
extension PrintWatermarkSettings {
    func filling(from shot: FilmShotMetadata?) -> PrintWatermarkSettings {
        guard let shot else { return self }
        var result = self
        if isBlank(cameraName), let camera = Self.cameraName(make: shot.cameraMake, model: shot.cameraModel) {
            result.cameraName = camera
        }
        if isBlank(lensName), let lens = shot.lensModel {
            result.lensName = lens
        }
        if isBlank(focalLength), let focal = shot.focalLengthMM {
            result.focalLength = PrintWatermarkFormat.number(focal)
        }
        if isBlank(aperture), let fNumber = shot.fNumber {
            result.aperture = PrintWatermarkFormat.number(fNumber)
        }
        if isBlank(shutterSpeed), let exposure = shot.exposureTimeSeconds {
            result.shutterSpeed = PrintWatermarkFormat.exposureTime(exposure)
        }
        if isBlank(iso), let isoSpeed = shot.isoSpeed {
            result.iso = String(isoSpeed)
        }
        return result
    }

    /// `Canon` + `Canon EOS R5` 처럼 모델명에 제조사가 이미 있으면 한 번만 적는다.
    static func cameraName(make: String?, model: String?) -> String? {
        switch (make, model) {
        case let (make?, model?):
            return model.lowercased().hasPrefix(make.lowercased()) ? model : "\(make) \(model)"
        case let (make?, nil):
            return make
        case let (nil, model?):
            return model
        case (nil, nil):
            return nil
        }
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension ScanFrame {
    /// 필름스트립 썸네일이 지금 레시피·회전·자르기로 만든 것이면 그 이미지. 블러 바탕과 히스토그램은
    /// 큰 화면 이미지 대신 이것을 쓴다(작은 이미지로 충분한 일이다). 오래됐으면 nil.
    var watermarkReferenceImage: CGImage? {
        guard let thumbnail = thumbnailImage,
              thumbnailTransform == imageTransform,
              let recipe = thumbnailRecipeID,
              recipe == currentThumbnailRecipeID() else { return nil }
        return thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

extension PrintCompositionSettings {
    @MainActor
    func fillingWatermark(from frame: ScanFrame) -> PrintCompositionSettings {
        guard let watermark else { return self }
        var result = self
        // 로고는 저장된 경로에서 이 자리에서 읽는다(지워졌으면 로고만 빠진다).
        result.watermark = watermark.filling(from: frame.appMetadataOverlay?.filmShot).resolvingLogo()
        return result
    }
}
