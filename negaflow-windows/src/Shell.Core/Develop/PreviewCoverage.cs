using System.Buffers;
using System.Numerics;
using System.Runtime.InteropServices;

namespace Negaflow.Shell;

/// <summary>
/// 프리뷰 BGRA8 의 알파는 원근 보정이 빈 곳을 남길 때 커버리지를 싣습니다 — 빈 곳은 색이 흰색이고
/// 알파가 0 입니다(네이티브 <c>PreviewTarget.coverage_alpha</c>). 히스토그램·자동 보정·화소 읽기는
/// 알파 0 을 사진으로 세지 않고, 화면에 쓸 때는 불투명으로 올려 지금처럼 흰색으로 보이게 합니다.
/// </summary>
public static class PreviewCoverage
{
    private const uint AlphaMask = 0xFF000000U;

    /// <summary>알파가 0xFF 가 아닌 화소가 하나라도 있는가. 불투명한 그림은 복사 없이 그대로 쓰려고 봅니다.</summary>
    public static bool HasPartialCoverage(ReadOnlySpan<byte> bgra)
    {
        ReadOnlySpan<uint> words = MemoryMarshal.Cast<byte, uint>(bgra[..(bgra.Length & ~3)]);
        int index = 0;
        if (Vector.IsHardwareAccelerated && words.Length >= Vector<uint>.Count)
        {
            Vector<uint> mask = new(AlphaMask);
            ReadOnlySpan<Vector<uint>> vectors = MemoryMarshal.Cast<uint, Vector<uint>>(words);
            foreach (Vector<uint> vector in vectors)
            {
                if (!Vector.EqualsAll(vector & mask, mask))
                {
                    return true;
                }
            }
            index = vectors.Length * Vector<uint>.Count;
        }
        for (; index < words.Length; index++)
        {
            if ((words[index] & AlphaMask) != AlphaMask)
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>
    /// 화면용 비트맵(premultiplied BGRA)에 씁니다. 커버리지가 실린 화소는 알파만 0xFF 로 올립니다 —
    /// 흰색에 알파 0 을 그대로 넘기면 premultiplied 규칙을 어겨 합성 결과가 장치마다 달라집니다.
    /// </summary>
    public static void WriteOpaque(Stream destination, byte[] bgra, int length)
    {
        ArgumentNullException.ThrowIfNull(destination);
        ArgumentNullException.ThrowIfNull(bgra);
        if (!HasPartialCoverage(bgra.AsSpan(0, length)))
        {
            destination.Write(bgra, 0, length);
            return;
        }
        byte[] rented = ArrayPool<byte>.Shared.Rent(length);
        try
        {
            bgra.AsSpan(0, length).CopyTo(rented);
            ForceOpaque(rented.AsSpan(0, length));
            destination.Write(rented, 0, length);
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(rented);
        }
    }

    public static void ForceOpaque(Span<byte> bgra)
    {
        Span<uint> words = MemoryMarshal.Cast<byte, uint>(bgra[..(bgra.Length & ~3)]);
        int index = 0;
        if (Vector.IsHardwareAccelerated && words.Length >= Vector<uint>.Count)
        {
            Vector<uint> mask = new(AlphaMask);
            Span<Vector<uint>> vectors = MemoryMarshal.Cast<uint, Vector<uint>>(words);
            for (int v = 0; v < vectors.Length; v++)
            {
                vectors[v] |= mask;
            }
            index = vectors.Length * Vector<uint>.Count;
        }
        for (; index < words.Length; index++)
        {
            words[index] |= AlphaMask;
        }
    }

    /// <summary>프리뷰 화소 (x, y) 가 원본 위인가. 알파 0 은 원근 보정의 빈 곳입니다.</summary>
    public static bool IsCovered(ReadOnlySpan<byte> bgra, int width, int x, int y)
    {
        long offset = (((long)y * width) + x) * 4L + 3L;
        return offset >= 0 && offset < bgra.Length && bgra[(int)offset] != 0;
    }
}
