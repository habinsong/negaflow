import SwiftUI

/// 필름 카메라가 남기지 않는 촬영 기록 입력. 저장하면 내보낸 파일의 EXIF/TIFF에 실린다.
struct FilmShotMetadataFields: View {
    @EnvironmentObject private var model: AppModel
    @Binding var draft: AppMetadataOverlayDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Label(localized(.filmShot), systemImage: "camera")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(localized(.cameraMake), text: $draft.cameraMake)
            TextField(localized(.cameraModel), text: $draft.cameraModel)
            TextField(localized(.lensModel), text: $draft.lensModel)
            TextField(localized(.filmStock), text: $draft.filmStock)
            HStack(spacing: 8) {
                TextField(localized(.isoSpeed), text: $draft.isoSpeed)
                TextField(localized(.shutterSpeed), text: $draft.shutterSpeed)
            }
            HStack(spacing: 8) {
                TextField(localized(.aperture), text: $draft.aperture)
                TextField(localized(.focalLength), text: $draft.focalLength)
            }
        }
    }

    private func localized(_ text: AppMetadataOverlayLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
