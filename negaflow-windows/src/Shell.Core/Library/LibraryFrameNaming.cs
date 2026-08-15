using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 카드와 목록에 보이는 사진 이름입니다.
/// </summary>
/// <remarks>
/// 이름 짓는 **규칙**은 catalog 가 압니다(<see cref="LibraryFrameSnapshot.PreferredBaseDisplayName"/>,
/// <see cref="LibraryFrameSnapshot.PresentationIndex"/>). 여기서 하는 일은 규칙이 "번호로 부르라"고
/// 할 때 그 문구를 언어에 맞춰 만드는 것뿐입니다. 문구는 셸의 <c>Resources.resw</c> 에 살고
/// (macOS <c>frameDisplayFormat</c>), 셸이 시작할 때 <see cref="NumberFormat"/> 에 꽂습니다 —
/// Shell.Core 는 WinUI 리소스를 참조하지 않으므로 이 자리가 유일한 연결점입니다.
/// </remarks>
public static class LibraryFrameNaming
{
    /// <summary>
    /// 번호로 부르는 이름의 문구입니다. <c>{0}</c> 이 번호입니다. 셸이 꽂기 전까지는 영어
    /// 기본값이며, 이는 시험과 CLI 가 셸 없이 돌기 때문입니다.
    /// </summary>
    public static Func<int, string> NumberFormat { get; set; } =
        number => $"Frame {number}";

    /// <summary>
    /// 이름이 없는 사진의 사본 문구입니다. 첫 수가 사진 번호, 둘째가 사본 번호입니다 — macOS
    /// <c>frameCopyDisplayFormat</c> 과 같습니다.
    /// </summary>
    public static Func<int, int, string> CopyFormat { get; set; } =
        (number, copy) => $"Frame {number} Copy {copy}";

    /// <summary>
    /// 이름이 있는 사진의 사본 문구입니다 — macOS <c>namedFrameCopyDisplayFormat</c> 입니다.
    /// </summary>
    public static Func<string, int, string> NamedCopyFormat { get; set; } =
        (name, copy) => $"{name} Copy {copy}";

    /// <summary>이 사진을 화면에 부를 이름입니다.</summary>
    public static string DisplayName(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        // 사본은 본 이름 뒤에 사본 번호를 답니다. **가름은 이름이 있느냐**이고, 붙이는 값은
        // 그 사진을 부르는 이름입니다 — 번호를 직접 지정한 사본은 지정한 번호로 불립니다.
        // macOS displayName(language:) 과 같은 두 갈래입니다.
        if (frame.VirtualCopyNumber is { } copyNumber)
        {
            return frame.PreferredBaseDisplayName is not null
                ? NamedCopyFormat(BaseName(frame), copyNumber)
                : CopyFormat(frame.PresentationIndex, copyNumber);
        }
        return BaseName(frame);
    }

    private static string BaseName(LibraryFrameSnapshot frame)
    {
        // 번호를 직접 지정했으면 파일 이름이 무엇이든 그 번호로 부릅니다 — 사용자가 그렇게
        // 정했기 때문입니다.
        if (frame.AssignedPhotoNumber is { } assigned)
        {
            return NumberFormat(assigned);
        }
        if (frame.PreferredBaseDisplayName is { } baseName)
        {
            return baseName;
        }
        // 순번을 모르는 record 는 "Frame 0" 이 됩니다. 그 자리에는 파일 이름이 낫습니다 —
        // 번호가 없다는 것이 이름이 없다는 뜻은 아닙니다.
        return frame.PresentationIndex > 0
            ? NumberFormat(frame.PresentationIndex)
            : frame.SourceFileBaseName ?? Path.GetFileName(frame.SourcePath);
    }

    /// <summary>
    /// 이름 변경 상자에 처음 넣을 값입니다. macOS <c>editableDisplayName</c> 과 같이, 번호로
    /// 불리는 사진은 번호를, 그 밖에는 지금 이름을 보여 줍니다.
    /// </summary>
    public static string EditableNumberText(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        return frame.PresentationIndex.ToString(System.Globalization.CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// 이 번호를 이 사진에 붙일 수 있는지. macOS 와 같이 **같은 폴더 안에서만** 겹치는지 봅니다 —
    /// 폴더가 다르면 같은 번호가 있어도 헷갈리지 않습니다.
    /// </summary>
    public static bool IsNumberAvailable(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        LibraryFrameSnapshot frame,
        int number)
    {
        ArgumentNullException.ThrowIfNull(frames);
        ArgumentNullException.ThrowIfNull(frame);
        if (number <= 0)
        {
            return false;
        }
        string folder = FolderOf(frame);
        foreach (LibraryFrameSnapshot candidate in frames)
        {
            // 같은 원본을 가리키는 사진(가상 사본)은 함께 번호가 바뀌므로 충돌이 아닙니다.
            if (string.Equals(candidate.SourcePath, frame.SourcePath, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (string.Equals(FolderOf(candidate), folder, StringComparison.OrdinalIgnoreCase) &&
                candidate.PresentationIndex == number)
            {
                return false;
            }
        }
        return true;
    }

    /// <summary>번호를 붙일 때 catalog 에 적을 값입니다.</summary>
    public static DisplayNameSelection NumberSelection(int number) =>
        new(LibraryFrameSnapshot.AssignedPhotoNumberPrefixValue + number.ToString(
            System.Globalization.CultureInfo.InvariantCulture));

    private static string FolderOf(LibraryFrameSnapshot frame) =>
        Path.GetDirectoryName(frame.SourcePath) ?? string.Empty;
}
