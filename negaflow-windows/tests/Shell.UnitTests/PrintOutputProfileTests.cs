using System.IO;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Print;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 게시에 쓸 인화소 ICC 를 고르는 규칙입니다. macOS
/// <c>selectedPrintWorkspaceOutputProfile</c> 과 같아야 합니다.
/// </summary>
/// <remarks>
/// **없는데 있는 척 내보내면 안 됩니다.** 프로파일이 필요한데 없을 때 그대로 sRGB 로 내면
/// 랩은 자기 종이 프로파일이 걸린 줄 알고 받아 가며, 색이 달라진 뒤에야 드러납니다.
/// 그래서 그 경우는 <c>Missing</c> 이고 부르는 쪽이 멈춥니다.
/// </remarks>
internal static class PrintOutputProfileTests
{
    public static void Run()
    {
        string root = Path.Combine(
            Path.GetTempPath(), "negaflow-print-profile-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            string valid = Path.Combine(root, "lab.icc");
            File.WriteAllBytes(valid, new byte[200]);
            string tooShort = Path.Combine(root, "short.icc");
            File.WriteAllBytes(tooShort, new byte[64]);

            LibraryFrameSnapshot main = Frame(null) with { DevelopTarget = DevelopTarget.Main };
            LibraryFrameSnapshot print = Frame(null) with { DevelopTarget = DevelopTarget.Print };

            // 프린터 출력 프로파일이 없고 대상이 PRINT 가 아니면 전달 색공간으로 나갑니다.
            Check(
                PrintOutputProfile.For([main], new PrintPreferences(), Proof(string.Empty))
                    is { Profile: null, Missing: false },
                "a MAIN frame publishes into the named colour space");

            // 대상이 PRINT 면 프린터 프로파일이 걸립니다.
            Check(
                PrintOutputProfile.For([main, print], new PrintPreferences(), Proof(valid))
                    is { Profile.Length: 200, Missing: false },
                "one PRINT frame pulls in the printer profile");

            // PRINT 인데 프로파일이 없으면 내보내지 않습니다.
            Check(
                PrintOutputProfile.For([print], new PrintPreferences(), Proof(string.Empty))
                    is { Profile: null, Missing: true },
                "a PRINT frame without a printer profile refuses");

            // 파일이 있어도 ICC 머리말보다 짧으면 프로파일이 아닙니다.
            Check(
                PrintOutputProfile.For([print], new PrintPreferences(), Proof(tooShort))
                    is { Profile: null, Missing: true },
                "a file too short to be an ICC profile refuses");

            // C-print 프루프 ICC 는 화면 프루프 전용입니다 — 파일에 굽지 않습니다(C_PRINT 문서).
            PrintPreferences cPrint = new()
            {
                OutputProcess = PrintOutputProcess.CPrint,
                CPrintProofProfilePath = valid,
            };
            Check(
                PrintOutputProfile.For([main], cPrint, Proof(string.Empty))
                    is { Profile: null, Missing: false },
                "the C-print proof profile is never baked into the export");

            // 프린터 출력 프로파일을 골랐으면 인화 판은 대상과 무관하게 그것으로 나갑니다.
            Check(
                PrintOutputProfile.For([main], cPrint, Proof(valid))
                    is { Profile.Length: 200, Missing: false },
                "a chosen printer output profile is the print sheet's published space");

            // 인화 미리보기와 용지 시뮬레이션은 화면 전용입니다 — 고르는 데 끼지 않습니다.
            PrintPreferences proofing = new()
            {
                CPrintPreviewEnabled = true,
                CPrintPaperSimulationEnabled = true,
            };
            Check(
                PrintOutputProfile.For([main], proofing, Proof(string.Empty))
                    is { Profile: null, Missing: false },
                "screen proofing does not change what the file is published in");

            // 현상 탭 내보내기는 인화 탭의 C-print 공정을 보지 않습니다 — macOS
            // `selectedPrinterOutputProfile` 은 PRINT 사진에만 프린터 프로파일을 겁니다.
            Check(
                PrintOutputProfile.ForDevelop([main], Proof(valid))
                    is { Profile: null, Missing: false },
                "a develop export of a MAIN frame ignores the printer profile");
            Check(
                PrintOutputProfile.ForDevelop([main, print], Proof(valid))
                    is { Profile.Length: 200, Missing: false },
                "a develop export with a PRINT frame reads the printer profile");
            Check(
                PrintOutputProfile.ForDevelop([print], Proof(string.Empty))
                    is { Profile: null, Missing: true },
                "a develop export of a PRINT frame without a printer profile refuses");
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch (IOException) { }
        }
    }

    private static SoftProofPreferences Proof(string printerProfilePath) =>
        new() { PrinterProfilePath = printerProfilePath };
}
