using System.Diagnostics;
using System.Net.Http;
using System.Runtime.InteropServices;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Update;

namespace Negaflow.Shell.Services;

/// <summary>
/// 실행할 때 한 번만 GitHub 최신 릴리스를 묻고, 더보기 메뉴의 업데이트 항목을 맡습니다. 새 버전이면
/// 릴리스 페이지를 열고 설치 파일을 받아 SHA-256 을 확인한 뒤 다운로드 폴더에 둡니다. 설치는
/// 사용자가 합니다 — 강제하지 않습니다.
/// </summary>
internal sealed class AppUpdateService
{
    private static readonly HttpClient Http = CreateClient();
    private int started;
    private int downloading;

    public static AppUpdateService Shared { get; } = new();

    /// <summary>null = 아직 모르거나 확인에 실패했습니다. 실패를 "최신"으로 보이지 않습니다.</summary>
    public AppUpdateCheckResult? Result { get; private set; }

    public bool IsDownloading => Volatile.Read(ref downloading) == 1;

    /// <summary>결과가 바뀌었습니다. 백그라운드 스레드에서 올 수 있습니다.</summary>
    public event EventHandler? Changed;

    private static HttpClient CreateClient()
    {
        HttpClient client = new() { Timeout = TimeSpan.FromSeconds(60) };
        // GitHub API 는 User-Agent 없는 요청을 거절합니다.
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"negaflow/{NegaflowProductVersion.Current}");
        return client;
    }

    public void CheckOnce()
    {
        if (Interlocked.Exchange(ref started, 1) == 1)
        {
            return;
        }
        _ = Task.Run(async () =>
        {
            try
            {
                using HttpRequestMessage request = new(HttpMethod.Get, AppUpdateCheck.LatestReleaseApi);
                request.Headers.Accept.ParseAdd("application/vnd.github+json");
                using CancellationTokenSource timeout = new(TimeSpan.FromSeconds(15));
                using HttpResponseMessage response = await Http.SendAsync(request, timeout.Token).ConfigureAwait(false);
                if (!response.IsSuccessStatusCode)
                {
                    return;
                }
                string json = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
                Result = AppUpdateCheck.Parse(json, NegaflowProductVersion.Current);
                Changed?.Invoke(this, EventArgs.Empty);
            }
            catch (Exception error) when (error is HttpRequestException or TaskCanceledException or OperationCanceledException)
            {
                // 오프라인이면 아무것도 보이지 않습니다.
            }
        });
    }

    /// <summary>더보기 메뉴의 업데이트 항목을 눌렀습니다.</summary>
    public void PerformMenuAction()
    {
        switch (Result)
        {
            case { Release: { } release }:
                Open(release.PageUrl);
                _ = DownloadAsync(release);
                break;
            case { Release: null }:
                Open(AppUpdateCheck.RepositoryUrl);
                break;
            default:
                break;
        }
    }

    private static void Open(Uri url)
    {
        try
        {
            using Process? _ = Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true });
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            AppStatusMessage.Shared.Post(url.AbsoluteUri);
        }
    }

    private async Task DownloadAsync(AppUpdateRelease release)
    {
        if (release.Installer is not { } installer || release.Checksums is not { } checksums ||
            Interlocked.Exchange(ref downloading, 1) == 1)
        {
            return;
        }
        Changed?.Invoke(this, EventArgs.Empty);
        AppStatusMessage.Shared.Post(AppResources.FormatText("updateDownloadingFormat", "Text", installer.Name));
        string? temporary = null;
        try
        {
            string sums = await Http.GetStringAsync(checksums.DownloadUrl).ConfigureAwait(false);
            string? expected = AppUpdateCheck.ExpectedSha256(sums, installer.Name);
            string? folder = DownloadsFolder();
            if (expected is null || folder is null)
            {
                Fail();
                return;
            }
            temporary = Path.Combine(Path.GetTempPath(), $"negaflow-update-{Guid.NewGuid():N}.part");
            using (HttpResponseMessage response = await Http.GetAsync(
                       installer.DownloadUrl, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false))
            {
                response.EnsureSuccessStatusCode();
                await using FileStream output = File.Create(temporary);
                await response.Content.CopyToAsync(output).ConfigureAwait(false);
            }
            if (!string.Equals(AppUpdateCheck.Sha256Hex(temporary), expected, StringComparison.Ordinal))
            {
                Fail();
                return;
            }
            // 다운로드 폴더가 지워졌거나 옮겨져 없으면 옮기기가 실패합니다 — 만들어 두고 옮깁니다.
            Directory.CreateDirectory(folder);
            string destination = AppUpdateCheck.AvailableDestination(folder, installer.Name);
            File.Move(temporary, destination);
            temporary = null;
            AppStatusMessage.Shared.Post(AppResources.FormatText(
                "updateDownloadedFormat", "Text", Path.GetFileName(destination)));
            using Process? _ = Process.Start(new ProcessStartInfo("explorer.exe")
            {
                UseShellExecute = false,
                Arguments = $"/select,\"{destination}\"",
            });
        }
        catch (Exception error) when (error is HttpRequestException or IOException or
                                          UnauthorizedAccessException or TaskCanceledException or
                                          System.ComponentModel.Win32Exception)
        {
            Fail();
        }
        finally
        {
            if (temporary is not null)
            {
                try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
            Volatile.Write(ref downloading, 0);
            Changed?.Invoke(this, EventArgs.Empty);
        }
    }

    private static void Fail()
    {
        string message = AppResources.Get("updateDownloadFailed", "Text");
        AppStatusMessage.Shared.Post(message);
        AppErrorLog.Shared.Record(message);
    }

    /// <summary>사용자가 옮겨 둔 다운로드 폴더까지 따릅니다(알려진 폴더 Downloads).</summary>
    private static string? DownloadsFolder()
    {
        Guid downloads = new("374DE290-123F-4565-9164-39C4925E467B");
        if (SHGetKnownFolderPath(downloads, 0, 0, out nint path) == 0 && path != 0)
        {
            try
            {
                return Marshal.PtrToStringUni(path);
            }
            finally
            {
                Marshal.FreeCoTaskMem(path);
            }
        }
        string fallback = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        return Directory.Exists(fallback) ? fallback : null;
    }

    [DllImport("shell32.dll")]
    private static extern int SHGetKnownFolderPath(
        [MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, nint token, out nint path);
}
