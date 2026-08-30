using System.Globalization;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 종횡비를 고를 때 실제로 쓰인 값을 남깁니다.
/// </summary>
/// <remarks>
/// 고른 비율과 화면에 그려진 사각형이 다르다는 신고는 화면을 재는 것만으로는 어디가
/// 어긋났는지 가릴 수 없습니다. 계산에 들어간 원본 크기와 회전, 나온 crop, 세션이 든
/// 선택, 그리고 그 선택을 화소로 환산한 비율을 한 줄에 적어 두면 한눈에 갈립니다.
///
/// 늘 켜 둡니다. 이 줄은 사용자가 비율을 누를 때만 나오므로 파일이 불어나지 않습니다.
/// </remarks>
public static class CropTrace
{
    private const string FileName = "crop-trace.txt";

    public static void Write(string message)
    {
        try
        {
            string folder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Negaflow",
                "Logs");
            Directory.CreateDirectory(folder);
            File.AppendAllText(
                Path.Combine(folder, FileName),
                DateTime.Now.ToString("HH:mm:ss.fff", CultureInfo.InvariantCulture) +
                    "  " + message + Environment.NewLine);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 진단을 남기지 못하는 것이 작업을 멈출 이유는 아닙니다.
        }
    }
}
