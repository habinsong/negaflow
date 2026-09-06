using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>출력 시작 때의 recipe와 옵션입니다. 렌더 완료 후 바뀐 화면 값을 읽지 않습니다.</summary>
public sealed record ExportArtifactSnapshot(string SourcePath, ExportSettings Settings, ExportSidecarContent Content)
{
    public static ExportArtifactSnapshot Capture(LibraryFrameSnapshot frame, string outputPath,
        ExportSettings settings, ExportEncodingOptions encoding, JsonObject? parameters,
        string appVersion, string engineVersion) => new(frame.SourcePath, settings, new ExportSidecarContent
        {
            OutputPath = outputPath, Format = settings.Format, Encoding = encoding,
            AppVersion = appVersion, EngineVersion = engineVersion,
            FilmType = frame.Route.FilmType.ToString(), PickState = frame.PickState.ToString().ToLowerInvariant(),
            Rating = frame.Rating, PresetName = frame.LookPresetId, AppMetadata = frame.AppMetadata,
            Parameters = parameters?.DeepClone().AsObject(),
        });
}

/// <summary>내보내기 부속 파일의 IO만 담당합니다. 호출자는 워커에서 실행합니다.</summary>
public static class ExportArtifactWriter
{
    public static string? Write(ExportArtifactSnapshot snapshot, DevelopExportResult? result = null)
    {
        string outputPath = snapshot.Content.OutputPath;
        if (snapshot.Settings.WriteOriginalRaw)
        {
            try
            {
                File.Copy(snapshot.SourcePath, ExportArtifactPairing.OriginalPath(outputPath, snapshot.SourcePath), overwrite: false);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
            { return "original_copy_failed"; }
        }
        if (!snapshot.Settings.WriteSidecar) { return null; }
        ExportSidecarContent content = snapshot.Content;
        if (result is { Succeeded: true } developed &&
            (developed.AppliedDminRed > 0 || developed.AppliedDminGreen > 0 || developed.AppliedDminBlue > 0))
        {
            string source = FilmBaseDiagnosticsSidecar.SourceName(developed.BaseSource, developed.MeasurementMethod);
            content = content with
            {
                BaseSample = FilmBaseDiagnosticsSidecar.Sample(developed.AppliedDminRed,
                    developed.AppliedDminGreen, developed.AppliedDminBlue, source),
                FilmBaseDiagnostics = FilmBaseDiagnosticsSidecar.From(developed.AppliedDminRed,
                    developed.AppliedDminGreen, developed.AppliedDminBlue, source, developed.Measurement),
            };
        }
        return ExportSidecarWriter.Write(outputPath, content);
    }
}
