using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV39
{
    internal NativeDevelopExportRequestV38 V38;
    internal double BaseScale;
    internal uint InputGammaMode;
    internal uint Reserved;
    internal double InputGammaValue;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV40
{
    internal NativeDevelopExportRequestV39 V39;
    internal uint AutoBalance;
    internal uint AutoBalanceReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV41
{
    internal NativeDevelopExportRequestV40 V40;
    internal uint ChannelRangePresent;
    internal uint MeasureRangeShape;
    internal float ChannelRangeRed;
    internal float ChannelRangeGreen;
    internal float ChannelRangeBlue;
    internal uint ChannelRangeReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportResultV6
{
    internal NativeDevelopExportResultV4 V5;
    internal uint ReferenceBasePresent;
    internal uint AppliedInputGammaMode;
    internal float ReferenceBaseRed;
    internal float ReferenceBaseGreen;
    internal float ReferenceBaseBlue;
    internal uint InputInterpretationRevision;
    internal double AppliedInputGammaValue;
    internal uint StructSize { get => V5.StructSize; set => V5.StructSize = value; }
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportResultV7
{
    internal NativeDevelopExportResultV6 V6;
    internal uint RangeShapePresent;
    internal uint RangeShapeReserved;
    internal float RangeShapeRed;
    internal float RangeShapeGreen;
    internal float RangeShapeBlue;
    internal uint RangeShapePad;
    internal uint StructSize { get => V6.StructSize; set => V6.StructSize = value; }
}
