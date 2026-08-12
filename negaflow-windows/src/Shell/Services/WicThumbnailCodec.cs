using Negaflow.Shell.Library;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Negaflow.Shell.Services;

/// <summary>
/// 썸네일 JPEG 인코딩입니다. Windows 의 이미지 스택(WIC)을 그대로 쓰고, 품질은 macOS 의
/// <c>kCGImageDestinationLossyCompressionQuality 0.85</c> 와 같게 둡니다.
/// </summary>
/// <remarks>
/// 인코딩은 블로킹입니다. UI 스레드에서 부르지 마십시오 — <see cref="ThumbnailService"/> 가
/// 워커에서만 부릅니다.
/// </remarks>
public sealed class WicThumbnailCodec : IThumbnailCodec
{
    private const double JpegQuality = 0.85;

    public byte[]? EncodeJpeg(byte[] bgra, int width, int height)
    {
        ArgumentNullException.ThrowIfNull(bgra);
        if (width <= 0 || height <= 0)
        {
            return null;
        }
        long required = (long)width * height * 4;
        if (bgra.LongLength < required)
        {
            return null;
        }

        // 버퍼는 상한 크기로 잡혀 있어 실제 이미지보다 클 수 있습니다. 인코더에는 정확히
        // 이미지가 차지하는 만큼만 넘깁니다.
        byte[] exact = bgra.LongLength == required ? bgra : bgra[..(int)required];

        try
        {
            return EncodeAsync(exact, (uint)width, (uint)height).GetAwaiter().GetResult();
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            // 한 장을 못 만들어도 그리드는 자리표시자로 남습니다.
            return null;
        }
    }

    private static async Task<byte[]?> EncodeAsync(byte[] bgra, uint width, uint height)
    {
        using var stream = new InMemoryRandomAccessStream();
        var options = new BitmapPropertySet
        {
            ["ImageQuality"] = new BitmapTypedValue(JpegQuality, Windows.Foundation.PropertyType.Single),
        };
        BitmapEncoder encoder = await BitmapEncoder
            .CreateAsync(BitmapEncoder.JpegEncoderId, stream, options)
            .AsTask()
            .ConfigureAwait(false);
        // 썸네일에 알파는 없습니다. Ignore 로 넘겨야 JPEG 인코더가 프리멀티플라이를 되돌리려
        // 하지 않습니다.
        encoder.SetPixelData(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Ignore,
            width,
            height,
            96.0,
            96.0,
            bgra);
        await encoder.FlushAsync().AsTask().ConfigureAwait(false);

        var jpeg = new byte[stream.Size];
        if (jpeg.Length == 0)
        {
            return null;
        }
        stream.Seek(0UL);
        using var reader = new DataReader(stream.GetInputStreamAt(0UL));
        _ = await reader.LoadAsync((uint)jpeg.Length).AsTask().ConfigureAwait(false);
        reader.ReadBytes(jpeg);
        return jpeg;
    }
}
