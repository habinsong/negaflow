using System.Text.Json;

namespace Negaflow.Interop.ContractTests;

internal static class ContractTestRunner
{
    internal static int Run(string[] args)
    {
        if (args.Length != 1)
        {
            Console.Error.WriteLine("Usage: Negaflow.Interop.ContractTests <absolute-native-dll-path>");
            return 2;
        }

        ContractTestContext context = new();
        ManagedLayoutContractTests.Verify(context);
        PathPolicyContractTests.Verify(context);

        NativeBuildInfo? buildInfo = null;
        try
        {
            buildInfo = NativeEngineBootstrap.LoadAndQuery(args[0]);
            NativeBuildInfoContractTests.Verify(context, buildInfo);
            context.Check(
                NativeEngineBootstrap.LoadAndQuery(args[0]) == buildInfo,
                "same_path_reload_is_idempotent");
            DevelopExportContractTests.Verify(context);
            RunStateContractTests.Verify(context);
            AutoAdjustContractTests.Verify(context);
            InfraredDetectorContractTests.Verify(context);
            FlatbedFrameGridContractTests.Verify(context);
            TiffSourceProbeContractTests.Verify(context);
            SoftProofContractTests.Verify(context);
            ToneLimitsContractTests.Verify(context);
            NegativeLimitsContractTests.Verify(context);
        }
        catch (Exception exception)
        {
            context.Failures.Add($"bootstrap:{exception.GetType().Name}");
        }

        var report = new
        {
            status = context.Failures.Count == 0 ? "ok" : "failed",
            operation = "interop_contract",
            assertions = context.AssertionCount,
            failures = context.Failures,
            abi_version = buildInfo?.AbiVersion.ToString(),
            architecture = buildInfo?.Architecture.ToString().ToLowerInvariant(),
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return context.Failures.Count == 0 ? 0 : 1;
    }
}
