namespace Negaflow.Interop;

using static NativeDevelopRequestV7V17;

/// <summary>v18–v34 요청 조립입니다. 초기 버전과 다른 이유입니다.</summary>
internal static unsafe class NativeDevelopRequestV18V34
{
    internal static NativeDevelopExportRequestV18 BuildRequestV18(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        char* scannerProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount,
        NativeDefectRegionEditV1* defectRegionEdits,
        uint defectRegionEditCount,
        byte* defectMaskBytes,
        uint defectMaskByteCount)
    {
        NativeDevelopExportRequestV17 v17 = BuildRequestV17(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            scannerProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV18);
        return new NativeDevelopExportRequestV18
        {
            V17 = v17,
            DefectRegionEdits = defectRegionEdits,
            DefectRegionEditCount = defectRegionEditCount,
            DefectMaskBytes = defectMaskBytes,
            DefectMaskByteCount = defectMaskByteCount,
        };
    }

    internal static NativeDevelopExportRequestV19 BuildRequestV19(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        char* scannerProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount,
        NativeDefectRegionEditV1* defectRegionEdits,
        uint defectRegionEditCount,
        byte* defectMaskBytes,
        uint defectMaskByteCount,
        byte* defectSourceSha256)
    {
        NativeDevelopExportRequestV18 v18 = BuildRequestV18(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            scannerProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount,
            defectRegionEdits,
            defectRegionEditCount,
            defectMaskBytes,
            defectMaskByteCount);
        v18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV19);
        return new NativeDevelopExportRequestV19
        {
            V18 = v18,
            DefectSourceFileBytes = request.DefectSourceIdentity?.ByteCount ?? 0,
            DefectSourceSha256 = defectSourceSha256,
            HasDefectSourceIdentity = request.DefectSourceIdentity is null ? 0U : 1U,
        };
    }

    internal static NativeDevelopExportRequestV20 BuildRequestV20(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        char* scannerProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount,
        NativeDefectRegionEditV1* defectRegionEdits,
        uint defectRegionEditCount,
        byte* defectMaskBytes,
        uint defectMaskByteCount,
        byte* defectSourceSha256,
        NativeDefectCloneEditV1* defectCloneEdits,
        uint defectCloneEditCount,
        NativeDefectCloneStrokeV1* defectCloneStrokes,
        uint defectCloneStrokeCount,
        NativeDefectClonePointV1* defectClonePoints,
        uint defectClonePointCount,
        NativeDefectRecipeEditRefV1* defectEditOrder,
        uint defectEditOrderCount)
    {
        NativeDevelopExportRequestV19 v19 = BuildRequestV19(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            scannerProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount,
            defectRegionEdits,
            defectRegionEditCount,
            defectMaskBytes,
            defectMaskByteCount,
            defectSourceSha256);
        v19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV20);
        return new NativeDevelopExportRequestV20
        {
            V19 = v19,
            DefectCloneEdits = defectCloneEdits,
            DefectCloneEditCount = defectCloneEditCount,
            DefectCloneStrokes = defectCloneStrokes,
            DefectCloneStrokeCount = defectCloneStrokeCount,
            DefectClonePoints = defectClonePoints,
            DefectClonePointCount = defectClonePointCount,
            DefectEditOrder = defectEditOrder,
            DefectEditOrderCount = defectEditOrderCount,
        };
    }

    internal static NativeDevelopExportRequestV21 BuildRequestV21(
        NativeDevelopExportRequestV20 v20,
        NativeDefectBrushEditV1* defectBrushEdits,
        uint defectBrushEditCount,
        NativeDefectBrushStrokeV1* defectBrushStrokes,
        uint defectBrushStrokeCount,
        NativeDefectBrushPointV1* defectBrushPoints,
        uint defectBrushPointCount)
    {
        v20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV21);
        return new NativeDevelopExportRequestV21
        {
            V20 = v20,
            DefectBrushEdits = defectBrushEdits,
            DefectBrushEditCount = defectBrushEditCount,
            DefectBrushStrokes = defectBrushStrokes,
            DefectBrushStrokeCount = defectBrushStrokeCount,
            DefectBrushPoints = defectBrushPoints,
            DefectBrushPointCount = defectBrushPointCount,
        };
    }

    internal static NativeDevelopExportRequestV24 BuildRequestV24(
        NativeDevelopExportRequestV21 v21,
        NativeDefectInfraredEditV1* defectInfraredEdits,
        uint defectInfraredEditCount,
        byte* defectInfraredAttenuationBytes,
        uint defectInfraredAttenuationByteCount)
    {
        v21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV24);
        return new NativeDevelopExportRequestV24
        {
            V21 = v21,
            DefectInfraredEdits = defectInfraredEdits,
            DefectInfraredEditCount = defectInfraredEditCount,
            DefectInfraredAttenuationBytes = defectInfraredAttenuationBytes,
            DefectInfraredAttenuationByteCount = defectInfraredAttenuationByteCount,
        };
    }

    internal static NativeDevelopExportRequestV25 BuildRequestV25(
        NativeDevelopExportRequestV24 v24,
        NativeDefectInfraredItemV1* defectInfraredItems,
        uint defectInfraredItemCount)
    {
        v24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV25);
        return new NativeDevelopExportRequestV25
        {
            V24 = v24,
            DefectInfraredItems = defectInfraredItems,
            DefectInfraredItemCount = defectInfraredItemCount,
        };
    }

    internal static NativeDevelopExportRequestV26 BuildRequestV26(
        NativeDevelopExportRequestV25 v25,
        DevelopExportRequest request)
    {
        v25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV26);
        return new NativeDevelopExportRequestV26
        {
            V25 = v25,
            OutputSharpeningStrength = request.OutputSharpening,
            OutputSharpeningMedium = (uint)request.OutputSharpeningMedium,
            OutputSharpeningDpi = request.OutputSharpeningDpi,
        };
    }

    internal static NativeDevelopExportRequestV27 BuildRequestV27(
        NativeDevelopExportRequestV26 v26,
        DevelopExportRequest request)
    {
        v26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV27);
        return new NativeDevelopExportRequestV27
        {
            V26 = v26,
            PrimaryCalibrationRedHue = request.PrimaryCalibration.RedHue,
            PrimaryCalibrationRedSaturation = request.PrimaryCalibration.RedSaturation,
            PrimaryCalibrationGreenHue = request.PrimaryCalibration.GreenHue,
            PrimaryCalibrationGreenSaturation = request.PrimaryCalibration.GreenSaturation,
            PrimaryCalibrationBlueHue = request.PrimaryCalibration.BlueHue,
            PrimaryCalibrationBlueSaturation = request.PrimaryCalibration.BlueSaturation,
        };
    }

    internal static NativeDevelopExportRequestV28 BuildRequestV28(
        NativeDevelopExportRequestV27 v27,
        DevelopExportRequest request)
    {
        v27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV28);
        return new NativeDevelopExportRequestV28
        {
            V27 = v27,
            JpegQuality = request.JpegQuality,
            OutputDpi = request.OutputDpi,
        };
    }

    internal static NativeDevelopExportRequestV29 BuildRequestV29(
        NativeDevelopExportRequestV28 v28,
        DevelopExportRequest request)
    {
        v28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV29);
        return new NativeDevelopExportRequestV29
        {
            V28 = v28,
            OutputLongEdge = request.OutputLongEdge,
        };
    }

    internal static NativeDevelopExportRequestV30 BuildRequestV30(
        NativeDevelopExportRequestV29 v29,
        DevelopExportRequest request)
    {
        v29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV30);
        return new NativeDevelopExportRequestV30
        {
            V29 = v29,
            TiffCompression = (uint)request.TiffCompression,
        };
    }

    internal static NativeDevelopExportRequestV31 BuildRequestV31(
        NativeDevelopExportRequestV30 v30,
        DevelopExportRequest request)
    {
        v30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7
            .StructSize = (uint)sizeof(NativeDevelopExportRequestV31);
        return new NativeDevelopExportRequestV31
        {
            V30 = v30,
            OutputBitDepth = request.OutputBitDepth,
        };
    }

    internal static NativeDevelopExportRequestV32 BuildRequestV32(
        NativeDevelopExportRequestV31 v31,
        DevelopExportRequest request)
    {
        v31.V30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8
            .V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV32);
        return new NativeDevelopExportRequestV32
        {
            V31 = v31,
            OutputColorSpace = (uint)request.OutputColorSpace,
        };
    }

    /// <summary>
    /// 문자열은 네이티브가 호출 동안만 읽습니다. 고정한 포인터의 수명이 호출을 덮도록
    /// 호출부가 <c>fixed</c> 안에서 이 메서드를 부르고 그 안에서 네이티브를 부릅니다.
    /// </summary>
    internal static NativeDevelopExportRequestV33 BuildRequestV33(
        NativeDevelopExportRequestV32 v32,
        DevelopExportRequest request,
        char* make,
        char* model,
        char* software,
        char* artist,
        char* copyright,
        char* filmType,
        char* filmStock,
        char* capturedAt)
    {
        v32.V31.V30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9
            .V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV33);
        return new NativeDevelopExportRequestV33
        {
            V32 = v32,
            MetadataPolicy = (uint)request.MetadataPolicy,
            MetadataMake = make,
            MetadataModel = model,
            MetadataSoftware = software,
            MetadataArtist = artist,
            MetadataCopyright = copyright,
            MetadataFilmType = filmType,
            MetadataFilmStock = filmStock,
            MetadataCapturedAt = capturedAt,
        };
    }

    internal static NativeDevelopExportRequestV34 BuildRequestV34(
        NativeDevelopExportRequestV33 v33,
        DevelopExportRequest request)
    {
        v33.V32.V31.V30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11
            .V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV34);
        return new NativeDevelopExportRequestV34
        {
            V33 = v33,
            PreserveAlpha = request.PreserveAlpha ? 1U : 0U,
        };
    }

    internal static NativeDevelopExportRequestV35 BuildRequestV35(
        NativeDevelopExportRequestV34 v34,
        byte* defectRecipeSha256,
        uint defectRecipeSha256Size)
    {
        v34.V33.V32.V31.V30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14.V13
            .V12.V11.V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV35);
        return new NativeDevelopExportRequestV35
        {
            V34 = v34,
            DefectRecipeSha256 = defectRecipeSha256,
            DefectRecipeSha256Size = defectRecipeSha256Size,
        };
    }

    internal static NativeDevelopExportRequestV36 BuildRequestV36(
        NativeDevelopExportRequestV35 v35,
        byte* defectRecipeAppendPrefixSha256,
        uint defectRecipeAppendPrefixSha256Size,
        uint defectRecipeAppendPrefixEditCount)
    {
        v35.V34.V33.V32.V31.V30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15.V14
            .V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV36);
        return new NativeDevelopExportRequestV36
        {
            V35 = v35,
            DefectRecipeAppendPrefixSha256 = defectRecipeAppendPrefixSha256,
            DefectRecipeAppendPrefixSha256Size = defectRecipeAppendPrefixSha256Size,
            DefectRecipeAppendPrefixEditCount = defectRecipeAppendPrefixEditCount,
        };
    }

    internal static NativeDevelopExportRequestV37 BuildRequestV37(
        NativeDevelopExportRequestV36 v36,
        byte* outputIccProfile,
        uint outputIccProfileSize)
    {
        v36.V35.V34.V33.V32.V31.V30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16.V15
            .V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV37);
        return new NativeDevelopExportRequestV37
        {
            V36 = v36,
            OutputIccProfile = outputIccProfile,
            OutputIccProfileSize = outputIccProfileSize,
        };
    }

    internal static NativeDevelopExportRequestV38 BuildRequestV38(
        NativeDevelopExportRequestV37 v37,
        uint proxyInputLongEdge)
    {
        v37.V36.V35.V34.V33.V32.V31.V30.V29.V28.V27.V26.V25.V24.V21.V20.V19.V18.V17.V16
            .V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV38);
        return new NativeDevelopExportRequestV38
        {
            V37 = v37,
            ProxyInputLongEdge = proxyInputLongEdge,
        };
    }

    internal static byte[] BuildDefectSourceSha256(DevelopExportRequest request) =>
        request.DefectSourceIdentity is { } identity
            ? Convert.FromHexString(identity.Sha256)
            : [];

    internal static byte[] BuildDefectRecipeSha256(DevelopExportRequest request) =>
        request.DefectRecipeSha256 is { } sha256
            ? Convert.FromHexString(sha256)
            : [];

    internal static byte[] BuildDefectRecipeAppendPrefixSha256(
        DevelopExportRequest request) =>
        request.DefectRecipeAppendPrefixSha256 is { } sha256
            ? Convert.FromHexString(sha256)
            : [];
}
