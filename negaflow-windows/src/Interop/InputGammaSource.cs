using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

public static partial class InputGammaSource
{
    public enum CurveKind : uint { Unknown, EmbeddedPower, EmbeddedProfile, AssumedLinear, AssumedSRGB, EstimatedPower }
    public readonly record struct Info(bool Supported, CurveKind Curve, double Gamma, double Evidence = 0, uint EdgeCount = 0)
    {
        // 수동 전환용 기본값을 파일에서 확인한 자동 감마로 표시하지 않습니다.
        public double? AutomaticValue => Curve switch
        {
            CurveKind.EmbeddedPower or CurveKind.EstimatedPower when double.IsFinite(Gamma) && Gamma > 0 => Gamma,
            CurveKind.AssumedLinear => 1.0,
            CurveKind.AssumedSRGB => 2.2,
            _ => null,
        };

        public double ManualSeed => Curve is CurveKind.EmbeddedPower or CurveKind.EstimatedPower && Gamma >= 0.1 && Gamma <= 4
            ? Gamma : Curve == CurveKind.AssumedLinear ? 1.0 : 2.2;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeInfo
    {
        public uint Size, Supported, Curve, Reserved;
        public double Gamma;
        public double Evidence;
        public uint EdgeCount, ReservedTail;
    }

    public static unsafe Info Inspect(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        NativeInfo result = new() { Size = (uint)sizeof(NativeInfo) };
        fixed (char* source = path)
        {
            uint status = InspectNative(source, &result);
            if (status != 0 || result.Size != sizeof(NativeInfo) || result.Reserved != 0 || result.ReservedTail != 0 || result.Supported > 1 ||
                result.Curve > (uint)CurveKind.EstimatedPower || !double.IsFinite(result.Gamma) ||
                !double.IsFinite(result.Evidence) || result.Evidence < 0 || result.Evidence > 1 ||
                (result.Curve is (uint)CurveKind.EmbeddedPower or (uint)CurveKind.EstimatedPower ? result.Gamma <= 0 : result.Gamma != 0))
            { throw new InvalidOperationException("Invalid input gamma source result."); }
        }
        return new(result.Supported == 1, (CurveKind)result.Curve, result.Gamma, result.Evidence, result.EdgeCount);
    }

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_inspect_input_gamma_source_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe partial uint InspectNative(char* path, NativeInfo* info);

    public static unsafe bool IsSupported(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        fixed (char* source = path)
        {
            uint supported = 0;
            uint status = Validate(source, &supported);
            if (status != 0 || supported > 1) { throw new InvalidOperationException("Invalid input gamma support result."); }
            return supported == 1;
        }
    }

    [LibraryImport(NativeMethods.LibraryName, EntryPoint = "nf_validate_input_gamma_source_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe partial uint Validate(char* path, uint* supported);
}
