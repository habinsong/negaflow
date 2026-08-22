namespace Negaflow.Interop;

using static NativeDevelopRequestValidator;
using static NativeDevelopLocalPayload;
using static NativeDevelopDefectRegionPayloadBuilder;
using static NativeDevelopDefectStrokePayload;
using static NativeDevelopRequestV18V34;
using static NativeDevelopPreviewRender;
using static NativeDevelopResultTranslator;

/// <summary>파일로 굽는 실행입니다. 미리보기·검출과 다른 이유입니다.</summary>
internal static unsafe class NativeDevelopExportCommand
{
    /// <param name="run">
    /// 실행 중 취소하고 진행도를 읽는 손잡이입니다. null 이면 예전처럼 끝까지 블로킹합니다.
    /// </param>
    public static DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null)
    {
        ArgumentNullException.ThrowIfNull(request);
        ValidateLayoutAndEnums(request);
        NativeLocalDodgeBurnPayload local = BuildLocalDodgeBurnPayload(
            request.LocalDodgeBurn);
        NativeDefectRegionPayload defects = BuildDefectRegionPayload(
            request.DefectRegions, request.DefectInfrared, request.DefectRecipeSha256);
        NativeDefectClonePayload clones = BuildDefectClonePayload(
            request.DefectClones);
        NativeDefectBrushPayload brushes = BuildDefectBrushPayload(
            request.DefectBrushes);
        NativeDefectRecipeEditRefV1[] defectEditOrder = BuildDefectEditOrder(request);
        byte[] defectSourceSha256 = BuildDefectSourceSha256(request);
        byte[] defectRecipeSha256 = BuildDefectRecipeSha256(request);

        NativeDevelopExportResultV4 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV4);
        uint status;

        // A null run state is the pre-v22 behaviour: the call simply runs to the end.
        NativeDevelopRunStateV1* runState = run is null ? null : run.StatePointer;

        // The native side copies both paths before returning, so pinning them for the
        // duration of the call is enough; no unmanaged allocation is needed.
        fixed (char* sourcePath = request.SourcePath)
        fixed (char* destinationPath = request.DestinationPath)
        fixed (char* filmStockDminId = request.FilmStockDminId)
        fixed (char* lightSourceProfileId = request.LightSourceProfileId)
        fixed (char* scannerProfileId = request.ScannerProfileId)
        fixed (NativeLocalDodgeBurnAdjustmentV1* localAdjustments = local.Adjustments)
        fixed (NativeLocalDodgeBurnStrokeV1* localStrokes = local.Strokes)
        fixed (NativeLocalDodgeBurnPointV1* localPoints = local.Points)
        fixed (NativeDefectRegionEditV1* defectRegionEdits = defects.Edits)
        fixed (byte* defectMaskBytes = defects.MaskBytes)
        fixed (byte* defectSourceDigest = defectSourceSha256)
        fixed (byte* defectRecipeDigest = defectRecipeSha256)
        fixed (NativeDefectCloneEditV1* defectCloneEdits = clones.Edits)
        fixed (NativeDefectCloneStrokeV1* defectCloneStrokes = clones.Strokes)
        fixed (NativeDefectClonePointV1* defectClonePoints = clones.Points)
        fixed (NativeDefectRecipeEditRefV1* nativeDefectEditOrder = defectEditOrder)
        fixed (NativeDefectBrushEditV1* defectBrushEdits = brushes.Edits)
        fixed (NativeDefectBrushStrokeV1* defectBrushStrokes = brushes.Strokes)
        fixed (NativeDefectBrushPointV1* defectBrushPoints = brushes.Points)
        fixed (NativeDefectInfraredEditV1* defectInfraredEdits =
            defects.InfraredEdits)
        fixed (byte* defectInfraredAttenuationBytes =
            defects.InfraredAttenuationBytes)
        fixed (NativeDefectInfraredItemV1* defectInfraredItems =
            defects.InfraredItems)
        {
            NativeDevelopExportRequestV20 v20 = BuildRequestV20(
                request,
                sourcePath,
                destinationPath,
                filmStockDminId,
                lightSourceProfileId,
                scannerProfileId,
                localAdjustments,
                checked((uint)local.Adjustments.Length),
                localStrokes,
                checked((uint)local.Strokes.Length),
                localPoints,
                checked((uint)local.Points.Length),
                defectRegionEdits,
                checked((uint)defects.Edits.Length),
                defectMaskBytes,
                checked((uint)defects.MaskBytes.Length),
                defectSourceDigest,
                defectCloneEdits,
                checked((uint)clones.Edits.Length),
                defectCloneStrokes,
                checked((uint)clones.Strokes.Length),
                defectClonePoints,
                checked((uint)clones.Points.Length),
                nativeDefectEditOrder,
                checked((uint)defectEditOrder.Length));
            NativeDevelopExportRequestV21 v21 = BuildRequestV21(
                v20,
                defectBrushEdits,
                checked((uint)brushes.Edits.Length),
                defectBrushStrokes,
                checked((uint)brushes.Strokes.Length),
                defectBrushPoints,
                checked((uint)brushes.Points.Length));
            NativeDevelopExportRequestV24 v24 = BuildRequestV24(
                v21,
                defectInfraredEdits,
                checked((uint)defects.InfraredEdits.Length),
                defectInfraredAttenuationBytes,
                checked((uint)defects.InfraredAttenuationBytes.Length));
            NativeDevelopExportRequestV25 v25 = BuildRequestV25(
                v24,
                defectInfraredItems,
                checked((uint)defects.InfraredItems.Length));
            NativeDevelopExportRequestV26 v26 = BuildRequestV26(v25, request);
            NativeDevelopExportRequestV27 v27 = BuildRequestV27(v26, request);
            NativeDevelopExportRequestV28 v28 = BuildRequestV28(v27, request);
            NativeDevelopExportRequestV29 v29 = BuildRequestV29(v28, request);
            NativeDevelopExportRequestV32 v32 = BuildRequestV32(
                BuildRequestV31(BuildRequestV30(v29, request), request),
                request);
            ExportMetadataValues values = request.Metadata;
            fixed (char* make = values.Make)
            fixed (char* model = values.Model)
            fixed (char* software = values.Software)
            fixed (char* artist = values.Artist)
            fixed (char* copyright = values.Copyright)
            fixed (char* filmType = values.FilmType)
            fixed (char* filmStock = values.FilmStock)
            fixed (char* capturedAt = values.CapturedAt)
            {
                NativeDevelopExportRequestV34 v34 = BuildRequestV34(
                    BuildRequestV33(
                        v32, request, make, model, software, artist, copyright, filmType,
                        filmStock, capturedAt),
                    request);
                if (defectRecipeSha256.Length == 0)
                {
                    status = NativeDevelopRun.nf_develop_export_v34(
                        &v34, runState, (NativeDevelopExportResultV3*)&raw);
                }
                else
                {
                    NativeDevelopExportRequestV35 v35 = BuildRequestV35(
                        v34, defectRecipeDigest, checked((uint)defectRecipeSha256.Length));
                    status = NativeDevelopRun.nf_develop_export_v35(
                        &v35, runState, (NativeDevelopExportResultV3*)&raw);
                }
            }
        }

        return Translate(
            status,
            raw,
            defectRecipeSha256.Length == 0
                ? "nf_develop_export_v34"
                : "nf_develop_export_v35");
    }

    /// <summary>
    /// 같은 파이프라인을 돌리되 파일을 쓰지 않고 <paramref name="pixels"/> 에 BGRA8 표시용
    /// 비트맵을 채웁니다. 실제로 쓰인 크기는 결과의 <c>ImageWidth</c>/<c>ImageHeight</c> 입니다.
    /// </summary>
    /// <remarks>
    /// <see cref="Run"/> 과 마찬가지로 블로킹입니다. UI 스레드에서 부르지 마십시오.
    /// </remarks>
    /// <param name="softProof">
    /// 보기용 시뮬레이션입니다. null 이면 프루프 없는 미리보기이고, 그 결과는 프루프 인자를
    /// 도입하기 전과 바이트 단위로 같습니다. <see cref="Run"/> 에는 대응하는 인자가 없습니다 —
    /// 인화물은 시뮬레이션을 담지 않습니다.
    /// </param>
    public static DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels,
        DevelopRun? run = null,
        SoftProofSettings? softProof = null,
        bool clippingOverlay = false)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentOutOfRangeException.ThrowIfZero(maximumWidth);
        ArgumentOutOfRangeException.ThrowIfZero(maximumHeight);
        if (pixels.IsEmpty)
        {
            throw new ArgumentException("The preview buffer is empty.", nameof(pixels));
        }
        return Render(
            request,
            maximumWidth,
            maximumHeight,
            pixels,
            run,
            softProof,
            null,
            clippingOverlay: clippingOverlay)
            .Result;
    }

    /// <summary>
    /// Persistent developed-cache background 채움용입니다. 표시 화소는 일반 preview와 같지만
    /// 재생성 가능한 native Rgba32F raw proxy를 카탈로그 전체에 남기지 않습니다.
    /// </summary>
    public static DevelopExportResult PreviewBackground(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels,
        DevelopRun? run = null)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentOutOfRangeException.ThrowIfZero(maximumWidth);
        ArgumentOutOfRangeException.ThrowIfZero(maximumHeight);
        if (pixels.IsEmpty)
        {
            throw new ArgumentException("The preview buffer is empty.", nameof(pixels));
        }
        return Render(
            request,
            maximumWidth,
            maximumHeight,
            pixels,
            run,
            softProof: null,
            detection: null,
            retainPreviewRaw: false)
            .Result;
    }
}
