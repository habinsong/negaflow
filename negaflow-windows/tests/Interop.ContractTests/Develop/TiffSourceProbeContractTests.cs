using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class TiffSourceProbeContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        context.Check(sizeof(NativeTiffSourceInfoV1) == 32, "tiff_source_info_size");
        context.Check(
            !NativeTiffSourceProbe.TryRead(
                Path.Combine(Path.GetTempPath(), $"missing-{Guid.NewGuid():N}.tif"), out _),
            "tiff_source_probe_refuses_missing_source");
    }
}
