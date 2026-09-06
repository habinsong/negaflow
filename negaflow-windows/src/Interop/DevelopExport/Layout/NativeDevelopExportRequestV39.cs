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
