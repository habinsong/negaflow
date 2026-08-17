namespace Negaflow.Interop;

using static NativeDevelopToneMarshaler;

/// <summary>v7–v17 요청 조립입니다. 결함 버전과 다른 이유입니다.</summary>
internal static unsafe class NativeDevelopRequestV7V17
{
    internal static NativeDevelopExportRequestV7 BuildRequestV7(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId)
    {
        NativeDevelopExportRequestV7 native = new()
        {
            StructSize = (uint)sizeof(NativeDevelopExportRequestV7),
            SourcePath = sourcePath,
            DestinationPath = destinationPath,
            OutputFormat = (uint)request.Format,
            FilmType = (uint)request.FilmType,
            BaseEstimationMode = (uint)request.BaseEstimationMode,
            DminRed = request.DminRed,
            DminGreen = request.DminGreen,
            DminBlue = request.DminBlue,
            ExposureStops = request.ExposureStops,
            Contrast = request.Contrast,
            Highlights = request.Highlights,
            Lights = request.Lights,
            Darks = request.Darks,
            Shadows = request.Shadows,
            FilmLookSourceKind = (uint)request.FilmLookSourceKind,
            FilmEmulation = (uint)request.FilmEmulation,
            FilmEmulationIntensity = request.FilmEmulationIntensity,
            RowsPerCopy = request.RowsPerCopy,
            Density = request.Density,
            Highlight = request.Highlight,
            Shadow = request.Shadow,
            Whites = request.Whites,
            Blacks = request.Blacks,
            FilmStockDminId = filmStockDminId,
            LightSourceProfileId = lightSourceProfileId,
            ColorGradingShadowsHue = request.ColorGrading.Shadows.Hue,
            ColorGradingShadowsSaturation = request.ColorGrading.Shadows.Saturation,
            ColorGradingShadowsLuminance = request.ColorGrading.Shadows.Luminance,
            ColorGradingMidtonesHue = request.ColorGrading.Midtones.Hue,
            ColorGradingMidtonesSaturation = request.ColorGrading.Midtones.Saturation,
            ColorGradingMidtonesLuminance = request.ColorGrading.Midtones.Luminance,
            ColorGradingHighlightsHue = request.ColorGrading.Highlights.Hue,
            ColorGradingHighlightsSaturation = request.ColorGrading.Highlights.Saturation,
            ColorGradingHighlightsLuminance = request.ColorGrading.Highlights.Luminance,
            ColorGradingBlending = request.ColorGrading.Blending,
            ColorGradingBalance = request.ColorGrading.Balance,
        };
        CopyPointCurve(request.PointCurves.Rgb, ref native.PointCurveRgb);
        CopyPointCurve(request.PointCurves.Red, ref native.PointCurveRed);
        CopyPointCurve(request.PointCurves.Green, ref native.PointCurveGreen);
        CopyPointCurve(request.PointCurves.Blue, ref native.PointCurveBlue);
        CopyColorMixer(request.ColorMixer.Hue, ref native, 0);
        CopyColorMixer(request.ColorMixer.Saturation, ref native, 1);
        CopyColorMixer(request.ColorMixer.Luminance, ref native, 2);
        return native;
    }

    internal static NativeDevelopExportRequestV11 BuildRequest(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId)
    {
        NativeDevelopExportRequestV7 prefix = BuildRequestV7(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId);
        prefix.StructSize = (uint)sizeof(NativeDevelopExportRequestV11);
        NativeDevelopExportRequestV8 v8 = new()
        {
            V7 = prefix,
            DefectRemovalStrength = request.DefectRemovalStrength,
        };
        NativeDevelopExportRequestV9 v9 = new()
        {
            V8 = v8,
            NoiseReductionStrength = request.NoiseReductionStrength,
            NoiseReductionLuma = request.NoiseReductionLuma,
            NoiseReductionChroma = request.NoiseReductionChroma,
            NoiseReductionDarkTone = request.NoiseReductionDarkTone,
            NoiseReductionDetail = request.NoiseReductionDetail,
            NoiseReductionGrainProtect = request.NoiseReductionGrainProtect,
            NoiseReductionFilmProfile = (uint)request.NoiseReductionFilmProfile,
        };
        NativeDevelopExportRequestV10 v10 = new()
        {
            V9 = v9,
            TextureGrain = request.Grain,
            TextureSharpness = request.Sharpness,
            TextureHalation = request.Halation,
            TextureClarity = request.Clarity,
            TextureVignette = request.Vignette,
        };
        DevelopCropRect crop = request.ImageTransform.Crop ??
            new DevelopCropRect(0.0, 0.0, 1.0, 1.0);
        double defaultShadowHue = request.BwToningMode == BwToningMode.Sepia
            ? 32.0
            : 285.0;
        double defaultHighlightHue = request.BwToningMode == BwToningMode.Sepia
            ? 48.0
            : 34.0;
        return new NativeDevelopExportRequestV11
        {
            V10 = v10,
            BwToningMode = (uint)request.BwToningMode,
            BwToningShadowHue = request.BwToningShadowHue ?? defaultShadowHue,
            BwToningHighlightHue = request.BwToningHighlightHue ?? defaultHighlightHue,
            BwToningStrength = request.BwToningStrength,
            ImageRotation = (uint)request.ImageTransform.Rotation,
            FlipHorizontal = request.ImageTransform.FlipHorizontal ? 1U : 0U,
            FlipVertical = request.ImageTransform.FlipVertical ? 1U : 0U,
            HasCrop = request.ImageTransform.Crop.HasValue ? 1U : 0U,
            CropX = crop.X,
            CropY = crop.Y,
            CropWidth = crop.Width,
            CropHeight = crop.Height,
            StraightenAngle = request.ImageTransform.StraightenAngle,
        };
    }

    internal static NativeDevelopExportRequestV12 BuildRequest(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV11 v11 = BuildRequest(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId);
        v11.V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV12);
        return new NativeDevelopExportRequestV12
        {
            V11 = v11,
            LocalAdjustments = localAdjustments,
            LocalAdjustmentCount = localAdjustmentCount,
            LocalStrokes = localStrokes,
            LocalStrokeCount = localStrokeCount,
            LocalPoints = localPoints,
            LocalPointCount = localPointCount,
        };
    }

    internal static NativeDevelopExportRequestV13 BuildRequestV13(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV12 v12 = BuildRequest(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v12.V11.V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV13);
        return new NativeDevelopExportRequestV13
        {
            V12 = v12,
            Warmth = request.Warmth,
            Tint = request.Tint,
            ColorDepth = request.ColorDepth,
            Vibrance = request.Vibrance,
            Saturation = request.Saturation,
            RedPrimary = request.RedPrimary,
            GreenPrimary = request.GreenPrimary,
            BluePrimary = request.BluePrimary,
        };
    }

    internal static NativeDevelopExportRequestV14 BuildRequestV14(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV13 v13 = BuildRequestV13(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v13.V12.V11.V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV14);
        return new NativeDevelopExportRequestV14
        {
            V13 = v13,
            AutoLevels = request.AutoLevels ? 1U : 0U,
            AutoNeutralBalance = request.AutoNeutralBalance ? 1U : 0U,
        };
    }

    internal static NativeDevelopExportRequestV15 BuildRequestV15(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV14 v14 = BuildRequestV14(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV15);
        return new NativeDevelopExportRequestV15
        {
            V14 = v14,
            DevelopTarget = (uint)request.DevelopTarget,
        };
    }

    internal static NativeDevelopExportRequestV16 BuildRequestV16(
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
        uint localPointCount)
    {
        NativeDevelopExportRequestV15 v15 = BuildRequestV15(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV16);
        return new NativeDevelopExportRequestV16
        {
            V15 = v15,
            ScannerProfileId = scannerProfileId,
        };
    }

    internal static NativeDevelopExportRequestV17 BuildRequestV17(
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
        uint localPointCount)
    {
        NativeDevelopExportRequestV16 v16 = BuildRequestV16(
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
        v16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV17);
        return new NativeDevelopExportRequestV17
        {
            V16 = v16,
            // Rendered-digital was already a positive-only route before v17.
            // Preserve that managed-call contract while the new field makes
            // positive film scans explicit.
            FilmPolarity = (uint)(
                request.FilmLookSourceKind == DevelopSourceKind.RenderedDigital
                    ? FilmPolarity.Positive
                    : request.FilmPolarity),
        };
    }
}
