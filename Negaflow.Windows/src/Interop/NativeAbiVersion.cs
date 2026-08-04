namespace Negaflow.Interop;

public readonly record struct NativeAbiVersion(ushort Major, ushort Minor)
{
    public uint Packed => ((uint)Major << 16) | Minor;

    internal static NativeAbiVersion FromPacked(uint value) =>
        new((ushort)(value >> 16), (ushort)(value & ushort.MaxValue));

    public override string ToString() => $"{Major}.{Minor}";
}
