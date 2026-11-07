using Negaflow.Shell.Update;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>업데이트 확인의 순수한 부분입니다(macOS AppUpdateCheckTests 와 같은 경우들).</summary>
internal static class AppUpdateCheckTests
{
    private static string Payload(string tag, bool prerelease = false, params string[] assets) =>
        "{\"tag_name\":\"" + tag + "\",\"html_url\":\"https://github.com/habinsong/negaflow/releases/tag/" + tag +
        "\",\"draft\":false,\"prerelease\":" + (prerelease ? "true" : "false") + ",\"assets\":[" +
        string.Join(',', assets.Select(name =>
            "{\"name\":\"" + name + "\",\"browser_download_url\":\"https://example.invalid/" + name + "\"}")) + "]}";

    internal static void Run()
    {
        string[] assets = ["negaflow-1.10.0-mac-arm64.pkg", "negaflow-1.10.0-win-x64.exe",
            "negaflow-1.10.0-win-x64-setup.zip", "SHA256SUMS.txt"];
        // 글자로 비교하면 "1.10.0" < "1.9.9" 입니다.
        AppUpdateCheckResult? newer = AppUpdateCheck.Parse(Payload("v1.10.0", false, assets), "1.9.9");
        Check(newer?.Release is { Version: "1.10.0" } release &&
              release.Installer?.Name == "negaflow-1.10.0-win-x64.exe" &&
              release.Checksums?.Name == "SHA256SUMS.txt",
            "update_newer_release_is_compared_numerically");
        Check(AppUpdateCheck.Parse(Payload("v1.2.6", false, assets), "1.2.6") is { IsUpdateAvailable: false } &&
              AppUpdateCheck.Parse(Payload("v1.2", false, assets), "1.2.0") is { IsUpdateAvailable: false } &&
              AppUpdateCheck.Parse(Payload("v1.2.5", false, assets), "1.2.6") is { IsUpdateAvailable: false },
            "update_same_or_older_is_up_to_date");
        Check(AppUpdateCheck.Parse("{}", "1.2.6") is null &&
              AppUpdateCheck.Parse("not json", "1.2.6") is null &&
              AppUpdateCheck.Parse(Payload("nightly", false, assets), "1.2.6") is null &&
              AppUpdateCheck.Parse(Payload("v9.0.0", true, assets), "1.2.6") is null &&
              AppUpdateCheck.Parse(Payload("v9.0.0", false, assets), "unknown") is null,
            "update_unreadable_or_unstable_releases_are_ignored");
        Check(AppUpdateCheck.Parse(Payload("v2.0.0", false, "negaflow-2.0.0-mac-arm64.pkg"), "1.2.6")
                  is { Release: { Installer: null } },
            "update_missing_windows_installer_still_offers_the_page");

        string hash = string.Concat(Enumerable.Repeat("ab", 32));
        string sums = new string('0', 64) + "  negaflow-1.2.7-mac-arm64.pkg\n" +
            hash.ToUpperInvariant() + " *negaflow-1.2.7-win-x64.exe\r\nbad  negaflow-1.2.7-win-x64-setup.zip\n";
        Check(AppUpdateCheck.ExpectedSha256(sums, "negaflow-1.2.7-win-x64.exe") == hash &&
              AppUpdateCheck.ExpectedSha256(sums, "negaflow-1.2.7-win-x64-setup.zip") is null,
            "update_checksum_line_formats");

        string folder = Path.Combine(Path.GetTempPath(), "negaflow-update-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            const string name = "negaflow-1.2.7-win-x64.exe";
            bool first = Path.GetFileName(AppUpdateCheck.AvailableDestination(folder, name)) == name;
            File.WriteAllText(Path.Combine(folder, name), "a");
            File.WriteAllText(Path.Combine(folder, "negaflow-1.2.7-win-x64 (2).exe"), "b");
            Check(first && Path.GetFileName(AppUpdateCheck.AvailableDestination(folder, name)) ==
                  "negaflow-1.2.7-win-x64 (3).exe",
                "update_download_never_overwrites_a_file");
            string sample = Path.Combine(folder, "abc.txt");
            File.WriteAllText(sample, "abc");
            Check(AppUpdateCheck.Sha256Hex(sample) ==
                  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                "update_sha256_of_a_file");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }
}
