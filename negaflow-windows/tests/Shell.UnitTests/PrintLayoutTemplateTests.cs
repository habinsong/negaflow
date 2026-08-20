using Negaflow.Shell.Print;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// macOS <c>PrintLayoutTemplateStore</c> — 같은 이름을 두 번 담지 않고, 100개까지이며,
/// 파일이 깨져 있으면 **덧쓰지 않습니다**(반쯤 남은 것까지 잃지 않으려고).
/// </summary>
internal static class PrintLayoutTemplateTests
{
    public static void Run()
    {
        string root = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-print-templates-{Environment.ProcessId}-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            VerifyRoundTrip(Path.Combine(root, "templates.json"));
            VerifyBrokenFileLocksWriting(Path.Combine(root, "broken.json"));
        }
        finally
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (IOException)
            {
                // 시험 뒤처리 실패는 시험 결과가 아닙니다.
            }
        }
    }

    private static void VerifyRoundTrip(string path)
    {
        PrintLayoutTemplateSettings settings =
            PrintLayoutTemplateSettings.From(new PrintPreferences());
        Check(settings.IsValid, "template_settings_from_defaults_are_valid");

        PrintLayoutTemplateStore store = new(path);
        Check(store.CanModify && store.Templates.Count == 0, "template_store_starts_empty");

        PrintLayoutTemplate? added = store.Add("  4x6 인화  ", settings);
        Check(added is not null && added.Name == "4x6 인화", "template_add_trims_the_name");
        Check(store.Templates.Count == 1, "template_add_keeps_one");

        // macOS 는 대소문자를 무시하고 같은 이름을 거부합니다.
        Check(store.Add("4X6 인화", settings) is null, "template_add_rejects_duplicate_name");
        Check(store.Add("   ", settings) is null, "template_add_rejects_blank_name");

        // 다시 읽어도 그대로 있어야 합니다.
        PrintLayoutTemplateStore reopened = new(path);
        Check(
            reopened.CanModify && reopened.Templates.Count == 1 &&
            reopened.Templates[0].Name == "4x6 인화",
            "template_survives_a_reopen");

        Guid id = reopened.Templates[0].Id;
        Check(reopened.Rename(id, "5x7 인화"), "template_rename_succeeds");
        Check(reopened.Templates[0].Name == "5x7 인화", "template_rename_applies");
        Check(reopened.Delete(id), "template_delete_succeeds");
        Check(reopened.Templates.Count == 0, "template_delete_empties");
        Check(!reopened.Delete(id), "template_delete_is_idempotent");

        // 담은 값이 설정에 그대로 되돌아가야 합니다.
        PrintPreferences source = new() { MarginMm = 7, ContactRows = 3, ContactColumns = 2 };
        PrintPreferences applied = PrintLayoutTemplateSettings.From(source)
            .ApplyTo(new PrintPreferences());
        Check(
            applied.MarginMm == 7 && applied.ContactRows == 3 && applied.ContactColumns == 2,
            "template_apply_restores_the_layout");
    }

    private static void VerifyBrokenFileLocksWriting(string path)
    {
        File.WriteAllText(path, "{ this is not a template file");
        PrintLayoutTemplateStore store = new(path);
        Check(!store.CanModify, "broken_template_file_locks_writing");
        Check(store.Templates.Count == 0, "broken_template_file_reads_as_empty");
        Check(
            store.Add("anything", PrintLayoutTemplateSettings.From(new PrintPreferences())) is null,
            "locked_store_refuses_to_add");
        Check(
            File.ReadAllText(path).StartsWith("{ this is not", StringComparison.Ordinal),
            "locked_store_leaves_the_file_alone");
    }
}
