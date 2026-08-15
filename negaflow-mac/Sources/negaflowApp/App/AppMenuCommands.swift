import SwiftUI

// MARK: 메뉴 항목에 `.disabled(!canPerformWorkflowShortcutAction(...))` 를 붙이지 말 것
//
// SwiftUI 의 Commands 트리는 이 앱에서 다시 평가되지 않는다. `.disabled` 를 붙이면 앱을 켠
// 직후 값(선택된 사진 없음 → 비활성)이 그대로 굳고, 그 뒤 사진을 골라도 메뉴는 계속 비활성
// 이며 **macOS 가 키 이퀴벌런트를 아예 배달하지 않는다**.
//
// 실측(2026-08-16, 계측 빌드): 사진 선택 직후 로그가
// `selection ... scope=360 actionableFrame=true` — 즉 활성 조건은 참인데도 현상 메뉴의
// 자동 톤/자동 화이트 밸런스/자동 색상/자동 레벨/크롭 영역이 전부 회색이었고, ⌘U 를 눌러도
// `autoadjust` 로그가 한 줄도 남지 않았다(액션 진입 자체가 없음). 같은 순간 인스펙터의
// 자동 톤 버튼은 `autoTone begin/applied` 를 남기며 정상 동작했다.
//
// 그래서 활성 판정은 화면이 아니라 **실행 시점**에 한다: `performWorkflowShortcutAction` 이
// 맨 앞에서 `canPerformWorkflowShortcutAction` 을 다시 확인하고 조건이 아니면 즉시 반환한다.
// 메뉴는 항상 활성으로 보이지만 눌러도 안전하다.
struct AppMenuCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        AppStandardMenuCommands(model: model)
        AppWorkflowMenuCommands(model: model)
    }
}
