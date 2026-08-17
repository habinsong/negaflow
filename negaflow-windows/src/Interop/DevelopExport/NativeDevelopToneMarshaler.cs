namespace Negaflow.Interop;

/// <summary>포인트 커브·컬러 믹서를 네이티브 버퍼에 씁니다.</summary>
internal static unsafe class NativeDevelopToneMarshaler
{
    internal static void CopyPointCurve(
        IReadOnlyList<DevelopPointCurvePoint> source,
        ref NativePointCurveV1 destination)
    {
        destination.PointCount = checked((uint)source.Count);
        destination.Reserved = 0;
        fixed (double* coordinates = destination.Coordinates)
        {
            int index = 0;
            foreach (DevelopPointCurvePoint point in source.OrderBy(point => point.X))
            {
                coordinates[index * 2] = point.X;
                coordinates[(index * 2) + 1] = point.Y;
                index++;
            }
        }
    }

    internal static void ValidateColorMixer(DevelopColorMixer colorMixer)
    {
        ArgumentNullException.ThrowIfNull(colorMixer);
        ValidateColorMixerChannel(colorMixer.Hue, nameof(colorMixer.Hue));
        ValidateColorMixerChannel(colorMixer.Saturation, nameof(colorMixer.Saturation));
        ValidateColorMixerChannel(colorMixer.Luminance, nameof(colorMixer.Luminance));
    }

    internal static void ValidateColorMixerChannel(IReadOnlyList<float> values, string parameterName)
    {
        ArgumentNullException.ThrowIfNull(values);
        if (values.Count != DevelopColorMixer.BandCount ||
            values.Any(value => !float.IsFinite(value) || value is < -1.0F or > 1.0F))
        {
            throw new ArgumentException("A Color Mixer channel must contain eight finite values from -1 to 1.", parameterName);
        }
    }

    internal static void CopyColorMixer(IReadOnlyList<float> source, ref NativeDevelopExportRequestV7 destination, int channel)
    {
        fixed (float* hue = destination.ColorMixerHue)
        fixed (float* saturation = destination.ColorMixerSaturation)
        fixed (float* luminance = destination.ColorMixerLuminance)
        {
            float* target = channel switch { 0 => hue, 1 => saturation, _ => luminance };
            for (int index = 0; index < DevelopColorMixer.BandCount; index++)
            {
                target[index] = source[index];
            }
        }
    }
}
