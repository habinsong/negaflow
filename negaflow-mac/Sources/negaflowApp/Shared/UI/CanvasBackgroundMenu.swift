import SwiftUI

/// 현상·인화 캔버스 우클릭 메뉴의 배경색 고르기.
///
/// 항목마다 버튼이 값을 직접 넣는다. 예전의 inline `Picker` 는 메뉴 안에서 선택 바인딩을 거치는데,
/// macOS 메뉴 속 inline Picker 는 선택이 반영되지 않는 알려진 결함이 있고(Apple Developer Forums
/// 763217), 2026-10-15 사용자 보고로 macOS 27 에서 배경색이 바뀌지 않았다(26 에서는 됨). 앱의 다른
/// 우클릭 메뉴는 모두 버튼이라 정상이다.
struct CanvasBackgroundMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            ForEach(CanvasBackground.allCases) { background in
                Button {
                    model.canvasBackground = background
                } label: {
                    if model.canvasBackground == background {
                        Label(background.label(language: model.appLanguage), systemImage: "checkmark")
                    } else {
                        Text(background.label(language: model.appLanguage))
                    }
                }
            }
        } header: {
            Text(model.text(AppLocalizedPhrase.canvasBackgroundMenu))
        }
    }
}
