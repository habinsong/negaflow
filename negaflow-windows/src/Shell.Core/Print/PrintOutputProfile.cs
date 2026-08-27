using System.IO;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Print;

/// <summary>어느 프로파일로 게시할지 정한 결과입니다.</summary>
/// <param name="Profile">쓸 ICC 바이트입니다. 없으면 이름 있는 색공간으로 나갑니다.</param>
/// <param name="Missing">
/// 프로파일이 <b>있어야 하는데</b> 없습니다. 그대로 내보내면 인화 결과가 달라지므로 부르는
/// 쪽이 멈추고 사용자에게 알려야 합니다.
/// </param>
public readonly record struct PrintOutputProfileChoice(byte[]? Profile, bool Missing)
{
    public static PrintOutputProfileChoice None { get; } = new(null, false);
}

/// <summary>
/// 게시에 쓸 인화소 ICC 를 고릅니다. macOS <c>selectedPrintWorkspaceOutputProfile</c> 과 같습니다.
/// </summary>
/// <remarks>
/// <para>
/// 규칙은 macOS <c>AppModel+PrintExport.swift</c> 그대로입니다:
/// </para>
/// <list type="number">
/// <item>출력 공정이 C-print 이고 그 프로파일이 있으면 그것.</item>
/// <item>아니면, 내보낼 사진 중 <b>현상 대상이 PRINT 인 것이 하나라도 있으면</b> 프린터
/// 출력 프로파일. 없으면 내보내지 않고 알립니다.</item>
/// <item>둘 다 아니면 프로파일 없이 — 이름 있는 색공간으로 나갑니다.</item>
/// </list>
/// <para>
/// 인화 미리보기(프루프)와 용지 시뮬레이션은 <b>화면 전용</b>이라 여기에 들어오지 않습니다.
/// macOS 도 그 둘을 파일에 굽지 않습니다 — 굽는 것은 이 출력 프로파일뿐입니다.
/// </para>
/// </remarks>
public static class PrintOutputProfile
{
    /// <summary>ICC 는 머리말만 128 바이트입니다. 그보다 짧으면 프로파일이 아닙니다.</summary>
    private const int MinimumProfileBytes = 128;

    public static PrintOutputProfileChoice For(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        PrintPreferences print,
        SoftProofPreferences softProof)
    {
        ArgumentNullException.ThrowIfNull(frames);
        ArgumentNullException.ThrowIfNull(print);
        ArgumentNullException.ThrowIfNull(softProof);

        if (print.OutputProcess == PrintOutputProcess.CPrint)
        {
            if (Read(print.CPrintProofProfilePath) is { } cPrint)
            {
                return new PrintOutputProfileChoice(cPrint, false);
            }
            // C-print 를 골라 놓고 프로파일이 없으면 랩이 못 씁니다.
            return new PrintOutputProfileChoice(null, true);
        }

        bool wantsPrintTarget = false;
        foreach (LibraryFrameSnapshot frame in frames)
        {
            if (frame.DevelopTarget == DevelopTarget.Print)
            {
                wantsPrintTarget = true;
                break;
            }
        }
        if (!wantsPrintTarget)
        {
            return PrintOutputProfileChoice.None;
        }
        return Read(softProof.PrinterProfilePath) is { } printer
            ? new PrintOutputProfileChoice(printer, false)
            : new PrintOutputProfileChoice(null, true);
    }

    /// <summary>
    /// 파일을 읽습니다. 없거나 못 읽으면 <see langword="null"/> 입니다 — 읽기 실패를 "프로파일
    /// 없음" 과 같이 다뤄야 부르는 쪽이 조용히 sRGB 로 내지 않습니다.
    /// </summary>
    private static byte[]? Read(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }
        try
        {
            byte[] bytes = File.ReadAllBytes(path);
            return bytes.Length >= MinimumProfileBytes ? bytes : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }
}
