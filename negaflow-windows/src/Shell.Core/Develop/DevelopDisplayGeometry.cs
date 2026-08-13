using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 화면에 보이는 사진 위의 한 점을 원본 파일 위의 한 점으로 되돌립니다.
/// </summary>
/// <remarks>
/// <para>
/// 결함 편집(치유 브러시·복제 도장)은 <b>원본 이미지의 정규 좌표, 좌상단 원점</b>으로 저장되고
/// 그대로 엔진에 갑니다(<c>defect_heal_brush.h</c>). 그런데 캔버스가 주는 점은 회전·반전·
/// 수평보정·크롭이 모두 적용된 <b>표시 좌표</b>입니다. 이 둘을 그냥 이으면 변형이 걸린 프레임에서
/// 엉뚱한 자리를 지웁니다.
/// </para>
/// <para>
/// 엔진이 적용하는 순서는 <c>imaging/image_transform.cpp</c> 기준으로
/// orient(90° 회전 + 반전) → straighten → crop 입니다. 세 단계 모두 구현이 이미
/// "출력 좌표 → 입력 좌표" 형태라서, 여기서는 그 식을 같은 방향으로 이어 붙이기만 하면 됩니다.
/// 뒤집어 푸는 것이 아니라 같은 식을 다시 쓰는 것이므로 두 쪽이 어긋날 여지가 적습니다.
/// </para>
/// <para>
/// 정규 좌표 0 과 1 은 첫 화소와 마지막 화소의 <b>중심</b>입니다. 네이티브 straighten 이
/// <c>(n-1)/2</c> 를 중심으로 쓰므로 같은 규약을 따릅니다.
/// </para>
/// </remarks>
public static class DevelopDisplayGeometry
{
    /// <summary>네이티브와 같은 판정입니다. 이보다 작은 각도는 수평보정을 걸지 않습니다.</summary>
    private const double StraightenThreshold = 1.0e-4;

    public static bool TryMapDisplayToRaw(
        ImageTransformRecipe transform,
        uint sourceWidth,
        uint sourceHeight,
        double displayX,
        double displayY,
        out double rawX,
        out double rawY)
    {
        ArgumentNullException.ThrowIfNull(transform);
        rawX = 0.0;
        rawY = 0.0;
        // 한 줄짜리 이미지는 정규 좌표를 만들 수 없고, 브러시로 칠할 것도 없습니다.
        if (sourceWidth < 2U || sourceHeight < 2U ||
            !double.IsFinite(displayX) || !double.IsFinite(displayY) ||
            !transform.IsValid)
        {
            return false;
        }

        double width = sourceWidth;
        double height = sourceHeight;
        bool swaps = transform.Rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270;
        double orientedWidth = swaps ? height : width;
        double orientedHeight = swaps ? width : height;

        double straightenedWidth = orientedWidth;
        double straightenedHeight = orientedHeight;
        bool straightened = Math.Abs(transform.StraightenAngle) > StraightenThreshold &&
            orientedWidth > 1.0 && orientedHeight > 1.0;
        if (straightened)
        {
            (straightenedWidth, straightenedHeight) =
                StraightenedExtent(orientedWidth, orientedHeight, transform.StraightenAngle);
        }

        double cropLeft = 0.0;
        double cropTop = 0.0;
        double croppedWidth = straightenedWidth;
        double croppedHeight = straightenedHeight;
        if (transform.Crop is { } crop)
        {
            // 저장된 crop 은 Core Image 의 y-up 이고 화소 행은 y-down 입니다. 네이티브
            // crop_image 와 같은 floor/ceil 과 clamp 를 그대로 씁니다.
            double left = Math.Floor(crop.X * straightenedWidth);
            double right = Math.Ceiling((crop.X + crop.Width) * straightenedWidth);
            double top = Math.Floor((1.0 - crop.Y - crop.Height) * straightenedHeight);
            double bottom = Math.Ceiling((1.0 - crop.Y) * straightenedHeight);
            cropLeft = Math.Min(left, straightenedWidth - 1.0);
            cropTop = Math.Min(top, straightenedHeight - 1.0);
            double clampedRight = Math.Clamp(right, cropLeft + 1.0, straightenedWidth);
            double clampedBottom = Math.Clamp(bottom, cropTop + 1.0, straightenedHeight);
            croppedWidth = clampedRight - cropLeft;
            croppedHeight = clampedBottom - cropTop;
        }
        if (croppedWidth < 2.0 || croppedHeight < 2.0)
        {
            return false;
        }

        // 표시 정규 좌표 → 잘린 이미지의 화소 좌표.
        double x = Math.Clamp(displayX, 0.0, 1.0) * (croppedWidth - 1.0);
        double y = Math.Clamp(displayY, 0.0, 1.0) * (croppedHeight - 1.0);

        // crop 되돌리기: 잘라낸 왼쪽·위를 더하면 수평보정된 이미지의 좌표입니다.
        x += cropLeft;
        y += cropTop;

        if (straightened)
        {
            double theta = transform.StraightenAngle * Math.PI / 180.0;
            double cos = Math.Cos(theta);
            double sin = Math.Sin(theta);
            double dx = x - ((straightenedWidth - 1.0) * 0.5);
            double dy = y - ((straightenedHeight - 1.0) * 0.5);
            x = ((orientedWidth - 1.0) * 0.5) + (dx * cos) + (dy * sin);
            y = ((orientedHeight - 1.0) * 0.5) - (dx * sin) + (dy * cos);
        }

        // orient 되돌리기. 네이티브와 같이 회전을 먼저 풀고 반전을 나중에 적용합니다.
        (double sourceX, double sourceY) = transform.Rotation switch
        {
            ImageRotation.Degrees90 => (y, height - 1.0 - x),
            ImageRotation.Degrees180 => (width - 1.0 - x, height - 1.0 - y),
            ImageRotation.Degrees270 => (width - 1.0 - y, x),
            _ => (x, y),
        };
        if (transform.FlipHorizontal)
        {
            sourceX = width - 1.0 - sourceX;
        }
        if (transform.FlipVertical)
        {
            sourceY = height - 1.0 - sourceY;
        }

        rawX = Math.Clamp(sourceX / (width - 1.0), 0.0, 1.0);
        rawY = Math.Clamp(sourceY / (height - 1.0), 0.0, 1.0);
        return true;
    }

    /// <summary>
    /// 수평보정 결과의 크기입니다. 네이티브 <c>straighten</c> 과 같은 식이며, 회전 뒤에도 원래
    /// 종횡비를 유지하는 가장 큰 사각형입니다.
    /// </summary>
    private static (double Width, double Height) StraightenedExtent(
        double width,
        double height,
        double degrees)
    {
        double theta = degrees * Math.PI / 180.0;
        double cosine = Math.Abs(Math.Cos(theta));
        double sine = Math.Abs(Math.Sin(theta));
        double outputHeight = Math.Min(
            width * height / ((width * cosine) + (height * sine)),
            height * height / ((width * sine) + (height * cosine)));
        double outputWidth = width / height * outputHeight;
        return (
            Math.Max(1.0, Math.Floor(outputWidth)),
            Math.Max(1.0, Math.Floor(outputHeight)));
    }
}
