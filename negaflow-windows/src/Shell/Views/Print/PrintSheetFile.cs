using Windows.Storage.Streams;

namespace Negaflow.Shell.Views;

/// <summary>
/// 인화 판이 읽고 쓰는 파일 스트림입니다. 그리기와 인코딩이 같은 방법으로 파일을 열도록
/// 한 자리에 둡니다.
/// </summary>
internal static class PrintSheetFile
{
    public static async Task<IRandomAccessStream> OpenAsync(string path, FileAccess access)
    {
        FileStream file = new(
            path,
            access == FileAccess.Read ? FileMode.Open : FileMode.OpenOrCreate,
            access,
            FileShare.Read);
        return await Task.FromResult(file.AsRandomAccessStream());
    }
}
