using System.Globalization;
using System.Text;
using Negaflow.Catalog;

namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 복구 화면의 "진단 복사" 가 내놓는 글입니다. macOS <c>LibraryRecoveryDiagnostics</c>
/// 이식본이며 줄 이름을 그대로 씁니다 — 두 플랫폼의 지원 요청을 같은 눈으로 읽습니다.
/// </summary>
/// <remarks>
/// <b>경로·파일명·사진 내용은 담지 않습니다.</b> 담는 것은 판정 코드와 개수뿐입니다.
/// macOS 에서 이번 사고의 원인을 찾는 데 오래 걸린 것은 진단이 <c>failure=corrupt</c>
/// 까지밖에 알려 주지 않아서였습니다.
/// </remarks>
public sealed record LibraryRecoveryDiagnostics(
    string AppVersion,
    LibraryHostState Lifecycle,
    CatalogSessionError SessionError,
    CatalogStoreError StoreError,
    DefectSidecarError DefectSidecarError,
    string? PendingRestoreGenerationId,
    IReadOnlyList<CatalogBackupGeneration> Generations,
    CatalogFileInspection? CatalogInspection,
    int UnreadableFrameCount,
    IReadOnlyList<string> FrameIssueCodes,
    IReadOnlyList<string> FrameRepairCodes)
{
    public string Text
    {
        get
        {
            StringBuilder text = new();
            void Line(string value) => text.Append(value).Append('\n');

            Line("negaflow.library-recovery.v1");
            Line($"appVersion={AppVersion}");
            Line($"lifecycle={Lifecycle}");
            Line($"session={SessionError}");
            Line($"store={StoreError}");
            Line($"defectSidecar={DefectSidecarError}");
            Line($"pendingRestore={PendingRestoreGenerationId ?? "none"}");
            Line($"backupCount={Generations.Count}");
            if (CatalogInspection is { } inspection)
            {
                Line($"catalogRead={inspection.Readability}");
                Line($"integrityCheck={(inspection.IntegrityCheckPassed ? "ok" : "failed")}");
                Line($"catalogVersion={Format(inspection.CatalogVersion)}");
                Line($"userVersion={Format(inspection.StorageVersion)}");
                foreach (CatalogTableRowCount rows in inspection.TableRows)
                {
                    Line($"rows.{rows.Table}={(rows.Rows < 0 ? "unknown" : Format(rows.Rows))}");
                }
            }
            // 읽지 못한 사진은 목록에서 조용히 빠집니다. 몇 장이 왜 빠졌는지는 여기에만
            // 남으므로 반드시 담습니다.
            Line($"unreadableFrames={UnreadableFrameCount}");
            if (FrameIssueCodes.Count > 0)
            {
                Line($"frameIssues={string.Join(' ', FrameIssueCodes)}");
            }
            // 되돌려서 **살린** 사진입니다. 위의 unreadableFrames 와 반대쪽 숫자입니다 -
            // 무엇을 잃지 않았는지도 지원 요청에서 알아야 합니다.
            if (FrameRepairCodes.Count > 0)
            {
                Line($"repaired={string.Join(' ', FrameRepairCodes)}");
            }
            for (int index = 0; index < Generations.Count; index++)
            {
                CatalogBackupGeneration generation = Generations[index];
                Line(
                    $"backup[{index}].state={generation.State} " +
                    $"createdAt={Format(generation.CreatedAt)} " +
                    $"frames={Format(generation.FrameCount)} " +
                    $"recipes={Format(generation.DefectRecipeCount)}");
            }
            return text.ToString();
        }
    }

    private static string Format(int? value) =>
        value?.ToString(CultureInfo.InvariantCulture) ?? "unknown";

    private static string Format(long? value) =>
        value?.ToString(CultureInfo.InvariantCulture) ?? "unknown";

    private static string Format(DateTimeOffset? value) =>
        value?.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture) ?? "unknown";
}
