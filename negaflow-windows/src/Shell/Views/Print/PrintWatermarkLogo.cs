using System.Runtime.InteropServices.WindowsRuntime;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;
using Windows.Storage.Streams;

namespace Negaflow.Shell.Views;

/// <summary>
/// 워터마크 로고를 경로에서 읽습니다. 설정·템플릿은 경로만 들고, 그릴 때마다 여기서 그림을 채웁니다.
/// macOS <c>PrintWatermarkLogoLoader</c> 와 같은 규칙입니다.
/// </summary>
/// <remarks>
/// <list type="bullet">
/// <item>로고를 켜고 경로를 비워 두면 negaflow 로고(앱 아이콘)를 씁니다.</item>
/// <item>경로의 파일이 지워졌거나 그림이 아니면 null 을 돌려줘 <b>로고만 빠지게</b> 합니다. 검사기에는
/// 띄우지 않고 하단 상태 점과 진단의 오류 기록(<see cref="AppErrorLog"/>)에만 남깁니다 — 같은 경로는
/// 다시 찾을 때까지 한 번만 남깁니다.</item>
/// <item>같은 파일(크기·수정 시각이 같음)은 다시 읽지 않습니다. UI 스레드에서만 부릅니다.</item>
/// </list>
/// </remarks>
internal static class PrintWatermarkLogo
{
    private static readonly Dictionary<string, (long Size, DateTime Modified, byte[]? Png)> Cache = [];
    private static readonly HashSet<string> ReportedMissing = [];
    private static Task<byte[]?>? builtIn;

    /// <summary>설정이 쓰는 로고입니다. 꺼져 있거나 읽을 수 없으면 null 입니다.</summary>
    internal static async Task<byte[]?> LoadAsync(PrintWatermarkSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (!settings.ShowsLogo)
        {
            return null;
        }
        return string.IsNullOrEmpty(settings.LogoSourcePath)
            ? await BuiltInAsync()
            : await FromPathAsync(settings.LogoSourcePath);
    }

    /// <summary>경로의 로고입니다. 읽을 수 없으면 오류 기록에 한 번 남기고 null 입니다.</summary>
    internal static async Task<byte[]?> FromPathAsync(string path)
    {
        FileInfo file;
        try
        {
            file = new FileInfo(path);
            if (!file.Exists)
            {
                Cache.Remove(path);
                NoteMissing(path);
                return null;
            }
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or
            UnauthorizedAccessException or NotSupportedException or System.Security.SecurityException)
        {
            NoteMissing(path);
            return null;
        }
        if (Cache.TryGetValue(path, out var entry) &&
            entry.Size == file.Length && entry.Modified == file.LastWriteTimeUtc)
        {
            return entry.Png;
        }
        byte[]? png = null;
        try
        {
            byte[] bytes = await File.ReadAllBytesAsync(path);
            png = await NormalizeAsync(bytes);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            png = null;
        }
        Cache[path] = (file.Length, file.LastWriteTimeUtc, png);
        if (png is null)
        {
            NoteMissing(path);
        }
        else
        {
            ReportedMissing.Remove(path);
        }
        return png;
    }

    /// <summary>
    /// negaflow 로고(앱 아이콘 <c>Assets\AppIcon-1024.png</c>)입니다. 어셈블리에 넣어 둔 것을 읽습니다 —
    /// 실행 위치(패키지·느슨한 레이아웃)와 상관없이 같은 그림이 나옵니다.
    /// </summary>
    /// <remarks>
    /// 읽는 작업 자체를 담아 둡니다. "읽었는가" 깃발만 두면, 설정 카드와 미리보기가 처음에 거의 동시에
    /// 부를 때 늦게 온 쪽이 아직 비어 있는 값(null)을 받아 갑니다. 미리보기는 그 null 을 같은 경로의
    /// 결과로 기억해, 다른 그림을 골랐다가 되돌려야만 로고가 나타났습니다.
    /// </remarks>
    private static async Task<byte[]?> BuiltInAsync()
    {
        Task<byte[]?> task = builtIn ??= ReadBuiltInAsync();
        try
        {
            return await task;
        }
        catch
        {
            // 실패한 작업을 남기지 않아 다음 요청이 다시 읽습니다.
            if (ReferenceEquals(builtIn, task))
            {
                builtIn = null;
            }
            throw;
        }
    }

    private static async Task<byte[]?> ReadBuiltInAsync()
    {
        using Stream? resource = typeof(PrintWatermarkLogo).Assembly
            .GetManifestResourceStream("Negaflow.Shell.WatermarkLogo.png");
        if (resource is null)
        {
            return null;
        }
        using MemoryStream bytes = new();
        await resource.CopyToAsync(bytes);
        return await NormalizeAsync(bytes.ToArray());
    }

    private static async Task<byte[]?> NormalizeAsync(byte[] bytes)
    {
        using InMemoryRandomAccessStream stream = new();
        await stream.WriteAsync(bytes.AsBuffer());
        stream.Seek(0);
        return await PrintWatermarkRaster.NormalizeLogoAsync(stream);
    }

    private static void NoteMissing(string path)
    {
        if (ReportedMissing.Add(path))
        {
            AppErrorLog.Shared.Record(
                AppResources.Get("printWatermarkLogoMissing", "Text") + " " + Path.GetFileName(path));
        }
    }
}
