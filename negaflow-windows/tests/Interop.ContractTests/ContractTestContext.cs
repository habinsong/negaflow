namespace Negaflow.Interop.ContractTests;

internal sealed class ContractTestContext
{
    internal List<string> Failures { get; } = [];

    internal int AssertionCount { get; private set; }

    internal void Check(bool condition, string name)
    {
        ++AssertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }

    internal void CheckThrows<TException>(Action action, string name)
        where TException : Exception
    {
        ++AssertionCount;
        try
        {
            action();
            Failures.Add(name);
        }
        catch (TException)
        {
        }
    }
}
