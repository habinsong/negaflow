using System.Buffers.Binary;

namespace Negaflow.Shell;

/// <summary>
/// 시뮬레이터가 내놓는 합성 컬러 네거티브입니다. 압축 없는 little-endian classic TIFF 이며,
/// 실제 스캔이 들어오는 것과 같은 디코더 경로를 지납니다.
/// </summary>
/// <remarks>
/// 그림은 장면을 먼저 만들고 **뒤집어** 오렌지 마스크를 씌운 것입니다. 그래야 현상 파이프라인이
/// 하는 일(마스크 제거 → 반전 → 톤)이 실제 필름과 같은 순서로 걸리고, 결과가 사람이 볼 만한
/// 그림이 됩니다. 이미 양화인 그림을 넣으면 반전 경로가 전혀 시험되지 않습니다.
/// </remarks>
public static class SyntheticNegativeTiff
{
    /// <summary>컬러 네거티브의 오렌지 마스크입니다. 채널별 최대 투과율에 해당합니다.</summary>
    private static readonly double[] Mask = [0.92, 0.58, 0.36];

    public static void Write(
        string path,
        int width,
        int height,
        int bitsPerSample,
        bool gray)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        ArgumentOutOfRangeException.ThrowIfLessThan(width, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(height, 1);
        if (bitsPerSample is not (8 or 16))
        {
            throw new ArgumentOutOfRangeException(nameof(bitsPerSample));
        }

        const int samplesPerPixel = 3;
        int bytesPerSample = bitsPerSample / 8;
        int rowBytes = width * samplesPerPixel * bytesPerSample;
        byte[] pixels = new byte[checked(rowBytes * height)];
        for (int y = 0; y < height; ++y)
        {
            int rowStart = y * rowBytes;
            for (int x = 0; x < width; ++x)
            {
                Scene(x, y, width, height, gray, out double r, out double g, out double b);
                int at = rowStart + (x * samplesPerPixel * bytesPerSample);
                WriteSample(pixels, at, Negative(r, 0), bitsPerSample);
                WriteSample(pixels, at + bytesPerSample, Negative(g, 1), bitsPerSample);
                WriteSample(pixels, at + (2 * bytesPerSample), Negative(b, 2), bitsPerSample);
            }
        }

        WriteTiff(path, width, height, bitsPerSample, samplesPerPixel, pixels, rowBytes);
    }

    /// <summary>
    /// 장면입니다. 하늘 그라디언트에 지평선과 색 패치 몇 개를 둡니다 — 그라디언트는 밴딩과
    /// 디더를, 패치는 색 전달을 눈으로 볼 수 있게 합니다.
    /// </summary>
    private static void Scene(
        int x,
        int y,
        int width,
        int height,
        bool gray,
        out double red,
        out double green,
        out double blue)
    {
        double u = (double)x / width;
        double v = (double)y / height;
        if (v < 0.55)
        {
            double sky = 1.0 - (v / 0.55 * 0.45);
            red = sky * 0.55;
            green = sky * 0.72;
            blue = sky * 0.95;
        }
        else
        {
            double ground = 0.55 - ((v - 0.55) * 0.35);
            red = ground * 0.9;
            green = ground * 0.75;
            blue = ground * 0.45;
        }

        // 아래쪽에 색 패치 여섯 칸.
        if (v > 0.72 && v < 0.9)
        {
            int patch = (int)(u * 6.0);
            (double R, double G, double B)[] swatches =
            [
                (0.85, 0.20, 0.18),
                (0.90, 0.60, 0.15),
                (0.85, 0.82, 0.20),
                (0.20, 0.65, 0.30),
                (0.18, 0.42, 0.80),
                (0.55, 0.25, 0.65),
            ];
            (red, green, blue) = swatches[Math.Clamp(patch, 0, 5)];
        }

        if (gray)
        {
            double luma = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
            red = luma;
            green = luma;
            blue = luma;
        }
    }

    /// <summary>장면을 뒤집어 마스크를 씌웁니다. 결과는 실제 네거티브가 보이는 모양입니다.</summary>
    private static double Negative(double scene, int channel) =>
        Mask[channel] * (1.0 - (Math.Clamp(scene, 0.0, 1.0) * 0.82));

    private static void WriteSample(byte[] destination, int at, double value, int bitsPerSample)
    {
        double bounded = Math.Clamp(value, 0.0, 1.0);
        if (bitsPerSample == 8)
        {
            destination[at] = (byte)Math.Round(bounded * 255.0);
            return;
        }
        BinaryPrimitives.WriteUInt16LittleEndian(
            destination.AsSpan(at),
            (ushort)Math.Round(bounded * 65535.0));
    }

    /// <summary>
    /// 태그 열두 개짜리 최소 TIFF 입니다. 한 strip 에 전부 담아 오프셋 계산을 단순하게 둡니다.
    /// </summary>
    private static void WriteTiff(
        string path,
        int width,
        int height,
        int bitsPerSample,
        int samplesPerPixel,
        byte[] pixels,
        int rowBytes)
    {
        const int entryCount = 12;
        const int headerBytes = 8;
        int directoryBytes = 2 + (entryCount * 12) + 4;
        // BitsPerSample 과 SampleFormat 은 값이 셋이라 short 세 개가 4바이트를 넘어 따로 놓입니다.
        int bitsOffset = headerBytes + directoryBytes;
        int sampleFormatOffset = bitsOffset + (samplesPerPixel * 2);
        int pixelOffset = sampleFormatOffset + (samplesPerPixel * 2);

        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write);
        using var writer = new BinaryWriter(stream);
        writer.Write((byte)'I');
        writer.Write((byte)'I');
        writer.Write((ushort)42);
        writer.Write((uint)headerBytes);

        writer.Write((ushort)entryCount);
        WriteEntry(writer, 256, 3, 1, (uint)width);
        WriteEntry(writer, 257, 3, 1, (uint)height);
        WriteEntry(writer, 258, 3, (uint)samplesPerPixel, (uint)bitsOffset);
        WriteEntry(writer, 259, 3, 1, 1);
        WriteEntry(writer, 262, 3, 1, 2);
        WriteEntry(writer, 273, 4, 1, (uint)pixelOffset);
        WriteEntry(writer, 274, 3, 1, 1);
        WriteEntry(writer, 277, 3, 1, (uint)samplesPerPixel);
        WriteEntry(writer, 278, 4, 1, (uint)height);
        WriteEntry(writer, 279, 4, 1, (uint)(rowBytes * height));
        WriteEntry(writer, 284, 3, 1, 1);
        WriteEntry(writer, 339, 3, (uint)samplesPerPixel, (uint)sampleFormatOffset);
        writer.Write(0U);

        for (int index = 0; index < samplesPerPixel; ++index)
        {
            writer.Write((ushort)bitsPerSample);
        }
        for (int index = 0; index < samplesPerPixel; ++index)
        {
            writer.Write((ushort)1);
        }
        writer.Write(pixels);
    }

    private static void WriteEntry(
        BinaryWriter writer,
        ushort tag,
        ushort type,
        uint count,
        uint value)
    {
        writer.Write(tag);
        writer.Write(type);
        writer.Write(count);
        // short 하나는 4바이트 칸의 앞쪽에 놓입니다.
        if (type == 3 && count == 1)
        {
            writer.Write((ushort)value);
            writer.Write((ushort)0);
            return;
        }
        writer.Write(value);
    }
}
