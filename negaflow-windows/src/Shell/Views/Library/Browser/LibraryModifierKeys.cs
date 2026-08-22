using Microsoft.UI.Input;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views.Library.Browser;

/// <summary>
/// 지금 눌려 있는 글쇠입니다. macOS 는 <c>NSEvent.modifierFlags</c> 를 그 자리에서 읽어
/// <c>selectFrame</c> 에 넘기며, 여기서도 같은 순간에 같은 것을 읽습니다.
/// </summary>
/// <remarks>
/// 맥의 Command 자리는 Windows 에서 Ctrl 입니다.
/// </remarks>
internal static class LibraryModifierKeys
{
    internal static LibrarySelectionModifiers Current()
    {
        LibrarySelectionModifiers modifiers = LibrarySelectionModifiers.None;
        if (IsDown(VirtualKey.Shift))
        {
            modifiers |= LibrarySelectionModifiers.Shift;
        }
        if (IsDown(VirtualKey.Control))
        {
            modifiers |= LibrarySelectionModifiers.Toggle;
        }
        return modifiers;
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key)
            .HasFlag(CoreVirtualKeyStates.Down);
}
