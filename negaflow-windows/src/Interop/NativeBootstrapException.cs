namespace Negaflow.Interop;

public enum NativeBootstrapFailure
{
    LoadFailed,
    BinaryFormatMismatch,
    MissingExport,
    AbiIncompatible,
    NativeCallFailed,
    ContractViolation,
}

public sealed class NativeBootstrapException : Exception
{
    internal NativeBootstrapException(
        NativeBootstrapFailure failure,
        string message,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Failure = failure;
    }

    public NativeBootstrapFailure Failure { get; }
}
