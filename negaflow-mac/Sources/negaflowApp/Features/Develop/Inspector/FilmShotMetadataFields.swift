import SwiftUI

/// 필름 카메라가 남기지 않는 촬영 기록 입력. 프레임과 롤 편집이 같은 필드를 쓴다.
struct FilmShotMetadataFields: View {
    @EnvironmentObject private var model: AppModel
    @Binding var draft: FilmShotDraft
    /// 롤 기록에는 컷마다 달라지는 셔터·조리개·초점 거리를 두지 않는다.
    var showsExposure = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(localized(.cameraMake), text: $draft.cameraMake)
            TextField(localized(.cameraModel), text: $draft.cameraModel)
            TextField(localized(.lensModel), text: $draft.lensModel)
            HStack(spacing: 8) {
                TextField(localized(.filmStock), text: $draft.filmStock)
                TextField(localized(.isoSpeed), text: $draft.isoSpeed)
                    .frame(width: 72)
            }
            if showsExposure {
                HStack(spacing: 8) {
                    TextField(localized(.shutterSpeed), text: $draft.shutterSpeed)
                    TextField(localized(.aperture), text: $draft.aperture)
                }
                TextField(localized(.focalLength), text: $draft.focalLength)
            }
        }
    }

    private func localized(_ text: AppMetadataOverlayLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
