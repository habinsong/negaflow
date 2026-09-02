using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>Export 몫입니다.</summary>
public sealed partial class DevelopPanelState
{
    public CatalogStoreError Save() => exports.Save();

    public Task<bool> ExportAsync(
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted,
        ExportEncodingOptions? encoding = null,
        Action<double>? onProgress = null)
    {
        return exports.ExportAsync(
            SelectedFrame,
            destinationPath,
            format,
            onCompleted,
            encoding,
            onProgress);
    }

    /// <summary>
    /// 결과를 <b>기록용</b> 한 줄로 만듭니다. 실패는 어느 단계에서 왜 멈췄는지를 남깁니다 —
    /// "Export failed" 만 남기면 스캔을 다시 하는 것 말고 할 수 있는 일이 없습니다.
    /// </summary>
    /// <remarks>
    /// 번역하지 않습니다. 화면에 적는 문구는
    /// <c>Shell/Localization/DevelopExportOutcomeText.cs</c> 가 만듭니다.
    /// </remarks>
    public static string Describe(DevelopExportOutcome outcome)
    {
        return DevelopExportOutcomePresenter.Describe(outcome);
    }
}
