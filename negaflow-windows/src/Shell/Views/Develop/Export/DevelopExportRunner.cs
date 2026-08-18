using System.IO;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Export;

/// <summary>출력 패널이 고른 설정으로 파일을 씁니다. UI 이벤트와 다른 이유입니다.</summary>
internal sealed class DevelopExportRunner
{
    private readonly DevelopExportPanel view;

    internal DevelopExportRunner(DevelopExportPanel view) => this.view = view;

    /// <summary>어셈블리에 박힌 앱 판입니다. 사이드카가 어느 판이 만든 파일인지 남깁니다.</summary>
    internal static string ShellVersion =>
        typeof(DevelopExportPanel).Assembly.GetName().Version?.ToString() ?? "0.0.0";

    /// <summary>
    /// 산출물 옆에 놓는 것들입니다. macOS 처럼 **산출물 옆에만** 쓰며, 원본 옆의 기존 사이드카를
    /// 병합 없이 덮어쓰지 않습니다. 사진 자체는 이미 게시된 뒤이므로 여기서 실패해도 사진은
    /// 남습니다 — 실패는 상태 줄로만 알립니다.
    /// </summary>
    internal void WriteExportArtifacts(
        LibraryFrameSnapshot frame,
        string outputPath,
        DevelopExportResult? exported = null)
    {
        if (view.libraryHost is null || (!view.exportSettings.WriteSidecar && !view.exportSettings.WriteOriginalRaw))
        {
            return;
        }
        if (view.exportSettings.WriteOriginalRaw)
        {
            try
            {
                string original = ExportArtifactPairing.OriginalPath(outputPath, frame.SourcePath);
                // 이미 있는 파일은 덮지 않습니다. 보관용 사본이 서로를 지우면 뜻이 없습니다.
                if (!File.Exists(original))
                {
                    File.Copy(frame.SourcePath, original);
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or
                PathTooLongException or NotSupportedException)
            {
                view.OutputStatusText.Text = AppResources.Get("developExportFolderFailed", "Text");
            }
        }
        if (!view.exportSettings.WriteSidecar)
        {
            return;
        }
        FilmBaseSampleSidecar? baseSample = null;
        FilmBaseDiagnosticsSidecar? filmBase = null;
        if (exported is { Succeeded: true } result &&
            (result.AppliedDminRed > 0 || result.AppliedDminGreen > 0 ||
             result.AppliedDminBlue > 0))
        {
            string source = FilmBaseDiagnosticsSidecar.SourceName(
                result.BaseSource,
                result.MeasurementMethod);
            baseSample = FilmBaseDiagnosticsSidecar.Sample(
                result.AppliedDminRed,
                result.AppliedDminGreen,
                result.AppliedDminBlue,
                source);
            filmBase = FilmBaseDiagnosticsSidecar.From(
                result.AppliedDminRed,
                result.AppliedDminGreen,
                result.AppliedDminBlue,
                source,
                result.Measurement);
        }
        JsonObject? record = view.libraryHost.FrameRecord(frame.Id);
        ExportSidecarContent content = new()
        {
            OutputPath = outputPath,
            Format = view.exportSettings.Format,
            Encoding = view.exportSettings.ToEncodingOptions(),
            AppVersion = ShellVersion,
            EngineVersion = view.engineVersion,
            FilmType = frame.Route.FilmType.ToString(),
            PickState = frame.PickState.ToString().ToLowerInvariant(),
            Rating = frame.Rating,
            PresetName = frame.LookPresetId,
            Parameters = record?["params"] as JsonObject,
            AppMetadata = frame.AppMetadata,
            BaseSample = baseSample,
            FilmBaseDiagnostics = filmBase,
        };
        if (ExportSidecarWriter.Write(outputPath, content) is { } failure)
        {
            view.OutputStatusText.Text = failure;
        }
    }

    /// <summary>
    /// 출력 패널의 내보내기입니다. 빠른 내보내기와 같은 경로를 쓰되 목적지와 형식을 사용자가
    /// 정한 값으로 씁니다.
    /// </summary>
    internal async Task RunExportAsync()
    {
        if (view.panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        // 편집은 메모리에만 있었으므로, 현상하기 전에 저장해 파일과 catalog 가 어긋나지 않게 합니다.
        if (view.panel.Save() != CatalogStoreError.None)
        {
            view.OutputStatusText.Text = AppResources.Get("developExportSaveFailed", "Text");
            return;
        }

        view.ExportButton.IsEnabled = false;
        view.OutputStatusText.Text = AppResources.Get("developExportRunning", "Text");
        string? completedPath = null;
        try
        {
            IReadOnlyList<LibraryFrameSnapshot> selection = SelectedExportFrames(frame);
            if (selection.Count > 1)
            {
                await RunExportBatchAsync(selection);
                return;
            }
            string exportedPath = view.exportSettings.Destination.PathFor(
                frame.SourcePath,
                view.sync.NamingContextFor(frame));
            _ = await view.panel.ExportAsync(
                exportedPath,
                view.exportSettings.Format,
                outcome =>
                {
                    view.OutputStatusText.Text = DevelopPanelState.Describe(outcome);
                    if (outcome is { Kind: DevelopExportOutcomeKind.Completed, Result.Succeeded: true })
                    {
                        WriteExportArtifacts(frame, exportedPath, outcome.Result);
                        completedPath = exportedPath;
                    }
                },
                view.exportSettings.ToEncodingOptions());
        }
        finally
        {
            view.RefreshPreview();
        }

        // 무보정본은 사진이 나간 뒤에 한 장 더 냅니다. 여기서 실패해도 사진은 남습니다.
        if (completedPath is { } published && view.exportSettings.WriteMainFlatMaster)
        {
            await WriteMainFlatMasterAsync(frame, published);
        }
    }

    /// <summary>
    /// 같은 원본을 조정 없이 MAIN 으로 한 번 더 현상합니다. 인코딩은 본 산출물과 같게 두어
    /// 두 파일이 같은 형식·같은 크기로 나란히 놓이게 합니다.
    /// </summary>
    internal async Task WriteMainFlatMasterAsync(LibraryFrameSnapshot frame, string outputPath)
    {
        if (view.panel is null || view.libraryHost is null)
        {
            return;
        }
        string masterPath = ExportFlatMaster.PathFor(outputPath);
        if (File.Exists(masterPath))
        {
            // 이미 있는 무보정본은 덮지 않습니다. 보관용 사본이 서로를 지우면 뜻이 없습니다.
            return;
        }
        _ = await view.libraryHost.ExportAsync(
            ExportFlatMaster.Neutralize(frame),
            masterPath,
            view.exportSettings.Format,
            outcome => view.OutputStatusText.Text = DevelopPanelState.Describe(outcome),
            view.exportSettings.ToEncodingOptions());
    }

    /// <summary>
    /// 내보낼 대상입니다. 라이브러리에서 여러 장을 골랐으면 그 목록이고, 아니면 지금 보고 있는
    /// 한 장입니다 — macOS 의 <c>exportSelection</c> 과 같은 규칙입니다.
    /// </summary>
    internal IReadOnlyList<LibraryFrameSnapshot> SelectedExportFrames(LibraryFrameSnapshot current)
    {
        IReadOnlyList<LibraryFrameSnapshot> selected = view.libraryHost?.SelectedFrames ?? [];
        return selected.Count > 1 ? selected : [current];
    }

    /// <summary>
    /// 여러 장을 차례로 내보내며 진행을 한 줄로 보여 줍니다. 계획은 먼저 전부 세우므로 같은
    /// 경로가 두 번 나오지 않고, 한 장이 실패해도 나머지는 계속 나갑니다.
    /// </summary>
    internal async Task RunExportBatchAsync(IReadOnlyList<LibraryFrameSnapshot> frames)
    {
        if (view.libraryHost is null)
        {
            return;
        }
        IReadOnlyList<ExportBatchPlan> plans = ExportBatchCoordinator.Plan(
            frames,
            view.exportSettings,
            frame => view.libraryHost.RollFor(frame.Id));
        var coordinator = new ExportBatchCoordinator(view.libraryHost);
        int finished = 0;
        coordinator.ItemChanged += (_, item) =>
        {
            if (item.State is ExportBatchItemState.Running)
            {
                return;
            }
            ++finished;
            view.OutputStatusText.Text = AppResources.FormatIntegers(
                "exportBatchFrameProgress",
                "Text",
                finished,
                plans.Count);
        };
        ExportBatchSummary summary = await coordinator.RunAsync(
            plans,
            view.exportSettings.ToEncodingOptions());
        view.OutputStatusText.Text = AppResources.FormatIntegers(
            "exportBatchFrameProgress",
            "Text",
            summary.Succeeded,
            summary.Total);
    }
}
