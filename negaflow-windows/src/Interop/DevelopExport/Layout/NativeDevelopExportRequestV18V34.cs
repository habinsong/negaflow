using System.Runtime.InteropServices;

namespace Negaflow.Interop;

// 결함 recipe 페이로드와 현상 요청 v18–v34 레이아웃.

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectRegionEditV1
{
    internal uint Enabled;
    internal uint RoiX;
    internal uint RoiY;
    internal uint Width;
    internal uint Height;
    internal uint MaskStrideBytes;
    internal uint MaskOffset;
    internal uint MaskByteCount;
    internal double Strength;
    internal uint HasPreferredAngle;
    internal uint Reserved;
    internal double PreferredAngleDegrees;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV18
{
    internal NativeDevelopExportRequestV17 V17;
    internal NativeDefectRegionEditV1* DefectRegionEdits;
    internal uint DefectRegionEditCount;
    internal uint DefectRegionReserved;
    internal byte* DefectMaskBytes;
    internal uint DefectMaskByteCount;
    internal uint DefectMaskReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV19
{
    internal NativeDevelopExportRequestV18 V18;
    internal ulong DefectSourceFileBytes;
    internal byte* DefectSourceSha256;
    internal uint HasDefectSourceIdentity;
    internal uint Reserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectClonePointV1
{
    internal double X;
    internal double Y;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectCloneStrokeV1
{
    internal uint PointOffset;
    internal uint PointCount;
    internal double OffsetX;
    internal double OffsetY;
    internal double DiameterPixels;
    internal double Hardness;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectCloneEditV1
{
    internal uint Enabled;
    internal uint StrokeOffset;
    internal uint StrokeCount;
    internal uint Reserved;
    internal double Strength;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectRecipeEditRefV1
{
    internal uint Kind;
    internal uint Index;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV20
{
    internal NativeDevelopExportRequestV19 V19;
    internal NativeDefectCloneEditV1* DefectCloneEdits;
    internal uint DefectCloneEditCount;
    internal uint DefectCloneEditReserved;
    internal NativeDefectCloneStrokeV1* DefectCloneStrokes;
    internal uint DefectCloneStrokeCount;
    internal uint DefectCloneStrokeReserved;
    internal NativeDefectClonePointV1* DefectClonePoints;
    internal uint DefectClonePointCount;
    internal uint DefectClonePointReserved;
    internal NativeDefectRecipeEditRefV1* DefectEditOrder;
    internal uint DefectEditOrderCount;
    internal uint DefectEditOrderReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectBrushPointV1
{
    internal double X;
    internal double Y;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectBrushStrokeV1
{
    internal uint PointOffset;
    internal uint PointCount;
    internal double Thickness;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectBrushEditV1
{
    internal uint Enabled;
    internal uint StrokeOffset;
    internal uint StrokeCount;
    internal uint Reserved;
    internal double Strength;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV21
{
    internal NativeDevelopExportRequestV20 V20;
    internal NativeDefectBrushEditV1* DefectBrushEdits;
    internal uint DefectBrushEditCount;
    internal uint DefectBrushEditReserved;
    internal NativeDefectBrushStrokeV1* DefectBrushStrokes;
    internal uint DefectBrushStrokeCount;
    internal uint DefectBrushStrokeReserved;
    internal NativeDefectBrushPointV1* DefectBrushPoints;
    internal uint DefectBrushPointCount;
    internal uint DefectBrushPointReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectInfraredEditV1
{
    internal uint RegionEditIndex;
    internal uint HasAttenuation;
    internal uint AttenuationStrideBytes;
    internal uint AttenuationOffset;
    internal uint AttenuationByteCount;
    internal uint Reserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV24
{
    internal NativeDevelopExportRequestV21 V21;
    internal NativeDefectInfraredEditV1* DefectInfraredEdits;
    internal uint DefectInfraredEditCount;
    internal uint DefectInfraredEditReserved;
    internal byte* DefectInfraredAttenuationBytes;
    internal uint DefectInfraredAttenuationByteCount;
    internal uint DefectInfraredAttenuationReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectInfraredItemV1
{
    internal uint ClusterOffset;
    internal uint ClusterCount;
    internal uint Reserved0;
    internal uint Reserved1;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV25
{
    internal NativeDevelopExportRequestV24 V24;
    internal NativeDefectInfraredItemV1* DefectInfraredItems;
    internal uint DefectInfraredItemCount;
    internal uint DefectInfraredItemReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV26
{
    internal NativeDevelopExportRequestV25 V25;
    internal float OutputSharpeningStrength;
    internal uint OutputSharpeningMedium;
    internal int OutputSharpeningDpi;
    internal uint OutputSharpeningReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV27
{
    internal NativeDevelopExportRequestV26 V26;
    internal float PrimaryCalibrationRedHue;
    internal float PrimaryCalibrationRedSaturation;
    internal float PrimaryCalibrationGreenHue;
    internal float PrimaryCalibrationGreenSaturation;
    internal float PrimaryCalibrationBlueHue;
    internal float PrimaryCalibrationBlueSaturation;
    internal uint PrimaryCalibrationReserved0;
    internal uint PrimaryCalibrationReserved1;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV28
{
    internal NativeDevelopExportRequestV27 V27;
    internal float JpegQuality;
    internal uint OutputDpi;
    internal uint OutputOptionsReserved0;
    internal uint OutputOptionsReserved1;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV29
{
    internal NativeDevelopExportRequestV28 V28;
    internal uint OutputLongEdge;
    internal uint OutputGeometryReserved0;
    internal uint OutputGeometryReserved1;
    internal uint OutputGeometryReserved2;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV30
{
    internal NativeDevelopExportRequestV29 V29;
    internal uint TiffCompression;
    internal uint OutputEncodingReserved0;
    internal uint OutputEncodingReserved1;
    internal uint OutputEncodingReserved2;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV31
{
    internal NativeDevelopExportRequestV30 V30;
    internal uint OutputBitDepth;
    internal uint OutputDepthReserved0;
    internal uint OutputDepthReserved1;
    internal uint OutputDepthReserved2;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV32
{
    internal NativeDevelopExportRequestV31 V31;
    internal uint OutputColorSpace;
    internal uint OutputSpaceReserved0;
    internal uint OutputSpaceReserved1;
    internal uint OutputSpaceReserved2;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV33
{
    internal NativeDevelopExportRequestV32 V32;
    internal uint MetadataPolicy;
    internal uint MetadataReserved0;
    internal uint MetadataReserved1;
    internal uint MetadataReserved2;
    internal char* MetadataMake;
    internal char* MetadataModel;
    internal char* MetadataSoftware;
    internal char* MetadataArtist;
    internal char* MetadataCopyright;
    internal char* MetadataFilmType;
    internal char* MetadataFilmStock;
    internal char* MetadataCapturedAt;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV34
{
    internal NativeDevelopExportRequestV33 V33;
    internal uint PreserveAlpha;
    internal uint AlphaReserved0;
    internal uint AlphaReserved1;
    internal uint AlphaReserved2;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV35
{
    internal NativeDevelopExportRequestV34 V34;
    internal byte* DefectRecipeSha256;
    internal uint DefectRecipeSha256Size;
    internal uint DefectRecipeIdentityReserved;
}
