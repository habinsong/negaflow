namespace Negaflow.Interop.ContractTests;

internal static class DevelopExportContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        DevelopExportRoutingContractTests.Verify(context);
        DevelopExportDefectContractTests.Verify(context);
        DevelopExportValidationContractTests.Verify(context);
    }
}
