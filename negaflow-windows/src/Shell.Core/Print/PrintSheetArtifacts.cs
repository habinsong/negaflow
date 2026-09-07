using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.Print;

/// <summary>
/// 인화 내보내기가 부속 파일을 낼지 말지입니다.
/// </summary>
/// <remarks>
/// macOS <c>AppModel+PrintExport</c> 의 규칙 그대로입니다 — <b>낱장 본 내보내기만</b> 사용자의
/// 사이드카·원본 사본·MAIN 무보정본 선택을 그대로 넘기고(<c>startExportBatch(writeSidecar:
/// exportWriteSidecar, …)</c>), <b>낱장 빠른 내보내기와 패키지 합성은 셋 다 끕니다</b>
/// (<c>writeSidecar: false, writeMainFlatMaster: false, writeOriginalRaw: false</c>).
/// 패키지는 여러 사진을 한 판에 얹으므로 어느 한 사진의 레시피도 그 판을 대표하지 못합니다.
/// </remarks>
public static class PrintSheetArtifactPolicy
{
    public static ExportSettings For(ExportSettings settings, bool quick, bool package)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return quick || package
            ? settings with
            {
                WriteSidecar = false,
                WriteOriginalRaw = false,
                WriteMainFlatMaster = false,
            }
            : settings;
    }

    /// <summary>이 설정이 실제로 부속 파일을 하나라도 내는가.</summary>
    public static bool WritesAnything(ExportSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return settings.WriteSidecar || settings.WriteOriginalRaw ||
            settings.WriteMainFlatMaster;
    }
}

/// <summary>
/// 낱장 인화 판 옆에 사이드카·원본 사본·MAIN 무보정본을 놓습니다.
/// </summary>
/// <remarks>
/// 현상뷰가 쓰는 <see cref="ExportArtifactSnapshot"/> · <see cref="ExportArtifactWriter"/> 를
/// 그대로 씁니다 — 인화만 다른 사이드카를 쓰면 같은 사진의 두 파일이 다른 내용을 답니다.
/// 레시피는 <b>시작 시점</b>에 붙잡습니다. 판을 굽는 동안 사용자가 감마나 배율을 바꿔도
/// 부속 파일은 나간 그림과 같은 값을 답니다.
/// </remarks>
public static class PrintSheetArtifacts
{
    /// <summary>판 하나가 나가기 전에 붙잡은 레시피와 옵션입니다.</summary>
    public static ExportArtifactSnapshot Capture(
        LibraryFrameSnapshot frame,
        string sheetPath,
        ExportSettings settings,
        ExportEncodingOptions encoding,
        JsonObject? parameters,
        string appVersion,
        string engineVersion) =>
        ExportArtifactSnapshot.Capture(
            frame,
            sheetPath,
            settings,
            encoding,
            settings.WriteSidecar ? parameters : null,
            appVersion,
            engineVersion);

    /// <summary>
    /// 붙잡아 둔 판마다 부속 파일을 냅니다. 실패한 것은 이름을 돌려주므로 부르는 쪽이
    /// 성공으로 표시하지 않습니다.
    /// </summary>
    public static async Task<IReadOnlyList<string>> WriteAsync(
        IReadOnlyList<ExportArtifactSnapshot> snapshots)
    {
        ArgumentNullException.ThrowIfNull(snapshots);
        List<string> failures = [];
        foreach (ExportArtifactSnapshot snapshot in snapshots)
        {
            // 큰 원본을 UI 스레드에서 복사하지 않습니다.
            string? failure = await Task.Run(() => ExportArtifactWriter.Write(snapshot))
                .ConfigureAwait(true);
            if (failure is not null)
            {
                failures.Add(failure);
            }
        }
        return failures;
    }

    /// <summary>
    /// 같은 원본을 조정 없이 MAIN 으로 한 번 더 현상해 판 옆에 둡니다.
    /// </summary>
    /// <remarks>
    /// macOS <c>ExportFrameWriter</c> 는 무보정본에 <b>판 합성을 얹지 않습니다</b>
    /// (<c>printComposition</c> 은 <c>developed</c> 에만 걸립니다) — 무보정본은 그 사진의
    /// 기준값이지 인화 배치의 결과가 아니기 때문입니다. 여기서도 판이 아니라 사진을 냅니다.
    /// </remarks>
    public static async Task<bool> WriteMainFlatMasterAsync(
        LibraryFrameSnapshot frame,
        string sheetPath,
        ExportSettings settings,
        byte[]? outputIccProfile)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentException.ThrowIfNullOrEmpty(sheetPath);
        ArgumentNullException.ThrowIfNull(settings);
        string masterPath = ExportFlatMaster.PathFor(sheetPath);
        ExportEncodingOptions encoding = settings.ToEncodingOptions() with
        {
            OutputIccProfile = outputIccProfile,
        };
        DevelopRequestResult built = DevelopRequestFactory.Create(
            ExportFlatMaster.Neutralize(frame),
            masterPath,
            settings.Format,
            encoding);
        if (built.Request is not { } request)
        {
            ExportTrace.Write(
                $"    print flat master refused frame={frame.Id} reason={built.Refusal}");
            return false;
        }
        DevelopExportResult result = await Task
            .Run(() => new NativeDevelopExporterAdapter().Run(request))
            .ConfigureAwait(true);
        if (!result.Succeeded)
        {
            ExportTrace.Write(
                $"    print flat master failed frame={frame.Id} stage={result.FailedStage} " +
                $"name={result.FailureName} native=0x{result.NativeErrorCode:X}");
        }
        return result.Succeeded;
    }
}
