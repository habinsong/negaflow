import AppKit

/// 텍스트를 입력하는 동안 ⌘·⌃ 없는 키를 메뉴보다 먼저 입력칸에 준다.
///
/// 메뉴에는 수정자 없는 단축키(별점 `0`–`5`, 사진 삭제 `delete`, 거부 `x` 등)가 걸려 있고,
/// 메뉴 단축키는 입력칸보다 먼저 키를 가져간다. 그래서 입력칸에서 숫자가 빠지거나 다른
/// 숫자가 들어간 것처럼 보이고, 지우기 키가 사진 삭제로 새어 나갔다. 편집 가능한 텍스트
/// 뷰가 포커스를 가진 동안에는 그 키를 곧바로 텍스트 뷰로 보낸다. ⌘·⌃ 조합(복사·붙여넣기·
/// 실행 취소 등)은 원래대로 메뉴를 거친다.
@MainActor
enum TextEntryKeyRouter {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let delivered = MainActor.assumeIsolated { deliverToTextEntry(event) }
            return delivered ? nil : event
        }
    }

    /// 입력칸이 받을 키면 직접 넘기고 `true`(더 전달하지 않음)를 돌려준다.
    static func deliverToTextEntry(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty,
              isTextOrDeletion(event),
              let textView = event.window?.firstResponder as? NSTextView,
              textView.isEditable else { return false }
        textView.keyDown(with: event)
        return true
    }

    /// 글자와 지우기 키만 가로챈다. Return·Esc·Tab·화살표·기능 키는 대화상자의 기본 단추나
    /// 포커스 이동이 쓰므로 원래 경로로 둔다.
    private static func isTextOrDeletion(_ event: NSEvent) -> Bool {
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else {
            return false
        }
        let functionKeys: ClosedRange<UInt32> = 0xF700...0xF8FF
        let forwardDelete = UInt32(NSDeleteFunctionKey)
        return scalar.value == forwardDelete
            || (scalar.value >= 0x20 && !functionKeys.contains(scalar.value))
    }
}
