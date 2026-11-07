import AppKit
import Carbon.HIToolbox

/// 한글처럼 라틴 글자가 아닌 입력 소스에서도 ⌘·⌃ 없는 메뉴 단축키(크롭 `R`, 격자 `G`, 별점 `0`–`5` 등)가
/// 동작하게 한다.
///
/// 한글 2벌식 상태에서 R 자리를 누르면 이벤트 글자가 `ㄱ` 이라 메뉴의 `r` 과 맞지 않았다(2026-11-07
/// 화면 시험: 영문 입력에서는 열리고 한글 입력에서는 열리지 않음). ⌘ 조합은 AppKit 이 이미 ASCII 자판으로
/// 맞추므로, 수정자 없는 키가 라틴이 아닌 글자로 들어왔을 때만 같은 키 자리의 ASCII 자판 글자로 바꿔
/// 메뉴 단축키를 한 번 더 찾는다. 입력칸이 포커스를 가진 동안에는 `TextEntryKeyRouter` 가 먼저 받는다.
@MainActor
enum LatinShortcutKeyRouter {
    /// 메뉴 단축키로 처리했으면 `true`.
    static func performLatinEquivalent(_ event: NSEvent) -> Bool {
        guard needsLatinFallback(characters: event.charactersIgnoringModifiers,
                                 modifiers: event.modifierFlags),
              let latin = latinCharacters(keyCode: event.keyCode, shift: event.modifierFlags.contains(.shift)),
              let unshifted = latinCharacters(keyCode: event.keyCode, shift: false),
              let mapped = NSEvent.keyEvent(
                with: .keyDown,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: latin,
                charactersIgnoringModifiers: unshifted,
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
              ) else { return false }
        return NSApp.mainMenu?.performKeyEquivalent(with: mapped) == true
    }

    /// ⌘·⌃·⌥ 가 없고, 이벤트 글자가 ASCII 밖의 출력 가능한 글자일 때만 바꾼다.
    nonisolated static func needsLatinFallback(characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.intersection([.command, .control, .option]).isEmpty,
              let scalar = characters?.unicodeScalars.first else { return false }
        let functionKeys: ClosedRange<UInt32> = 0xF700...0xF8FF
        return scalar.value > 0x7F && !functionKeys.contains(scalar.value)
    }

    /// 지금 고른 ASCII 자판(대개 ABC·미국)에서 이 키 자리가 내는 글자.
    nonisolated static func latinCharacters(keyCode: UInt16, shift: Bool) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let modifierState = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), modifierState, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
        guard let scalar = text.unicodeScalars.first, scalar.isASCII, scalar.value >= 0x20 else { return nil }
        return text
    }
}
