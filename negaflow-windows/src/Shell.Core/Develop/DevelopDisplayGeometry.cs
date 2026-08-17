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

    /// <summary>
    /// 변형 단계마다의 크기입니다. 표시→원본과 원본→표시가 <b>같은 수</b>를 써야 서로의 역이
    /// 됩니다 — 두 벌로 두면 언젠가 한쪽만 고쳐지고, 두 방향이 어긋나면 복제 도장이 커서와 다른
    /// 자리의 화소를 보여 줍니다.
    /// </summary>
    private readonly record struct TransformStages(
        double Width,
        double Height,
        double OrientedWidth,
        double OrientedHeight,
        bool Straightened,
        double StraightenedWidth,
        double StraightenedHeight,
        double CropLeft,
        double CropTop,
        double CroppedWidth,
        double CroppedHeight);

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
        if (!double.IsFinite(displayX) || !double.IsFinite(displayY) ||
            !TryStages(transform, sourceWidth, sourceHeight, out TransformStages stages))
        {
            return false;
        }

        // 표시 정규 좌표 → 잘린 이미지의 화소 좌표.
        double x = Math.Clamp(displayX, 0.0, 1.0) * (stages.CroppedWidth - 1.0);
        double y = Math.Clamp(displayY, 0.0, 1.0) * (stages.CroppedHeight - 1.0);

        // crop 되돌리기: 잘라낸 왼쪽·위를 더하면 수평보정된 이미지의 좌표입니다.
        x += stages.CropLeft;
        y += stages.CropTop;

        if (stages.Straightened)
        {
            double theta = transform.StraightenAngle * Math.PI / 180.0;
            double cos = Math.Cos(theta);
            double sin = Math.Sin(theta);
            double dx = x - ((stages.StraightenedWidth - 1.0) * 0.5);
            double dy = y - ((stages.StraightenedHeight - 1.0) * 0.5);
            x = ((stages.OrientedWidth - 1.0) * 0.5) + (dx * cos) + (dy * sin);
            y = ((stages.OrientedHeight - 1.0) * 0.5) - (dx * sin) + (dy * cos);
        }

        // orient 되돌리기. 네이티브와 같이 회전을 먼저 풀고 반전을 나중에 적용합니다.
        (double sourceX, double sourceY) = transform.Rotation switch
        {
            ImageRotation.Degrees90 => (y, stages.Height - 1.0 - x),
            ImageRotation.Degrees180 => (stages.Width - 1.0 - x, stages.Height - 1.0 - y),
            ImageRotation.Degrees270 => (stages.Width - 1.0 - y, x),
            _ => (x, y),
        };
        if (transform.FlipHorizontal)
        {
            sourceX = stages.Width - 1.0 - sourceX;
        }
        if (transform.FlipVertical)
        {
            sourceY = stages.Height - 1.0 - sourceY;
        }

        rawX = Math.Clamp(sourceX / (stages.Width - 1.0), 0.0, 1.0);
        rawY = Math.Clamp(sourceY / (stages.Height - 1.0), 0.0, 1.0);
        return true;
    }

    /// <summary>
    /// 원본 파일 위의 한 점을 화면에 보이는 사진 위의 한 점으로 옮깁니다. macOS
    /// <c>ImageTransform.baseUnitToDisplay</c> 와 같은 방향이며,
    /// <see cref="TryMapDisplayToRaw"/> 의 정확한 역입니다.
    /// </summary>
    /// <remarks>
    /// macOS 는 두 방향을 모두 들고 있습니다 — 복제 도장이 <c>displayOffset(forCursorAt:)</c> 에서
    /// <c>cursorBase + offset</c> 을 다시 표시 좌표로 돌려놓아야 원 안에 보여 줄 소스 화소의
    /// 자리를 알 수 있기 때문입니다. 잘려 나간 자리는 0~1 <b>밖</b>의 값이 됩니다. macOS 도 자르지
    /// 않고 내며 호출부가 <c>imageFrame.contains</c> 로 거릅니다.
    /// </remarks>
    public static bool TryMapRawToDisplay(
        ImageTransformRecipe transform,
        uint sourceWidth,
        uint sourceHeight,
        double rawX,
        double rawY,
        out double displayX,
        out double displayY)
    {
        ArgumentNullException.ThrowIfNull(transform);
        displayX = 0.0;
        displayY = 0.0;
        if (!double.IsFinite(rawX) || !double.IsFinite(rawY) ||
            !TryStages(transform, sourceWidth, sourceHeight, out TransformStages stages))
        {
            return false;
        }

        double sourceX = Math.Clamp(rawX, 0.0, 1.0) * (stages.Width - 1.0);
        double sourceY = Math.Clamp(rawY, 0.0, 1.0) * (stages.Height - 1.0);
        // 역방향이 회전 → 수평반전 → 수직반전 순이므로 정방향은 그 반대입니다.
        if (transform.FlipVertical)
        {
            sourceY = stages.Height - 1.0 - sourceY;
        }
        if (transform.FlipHorizontal)
        {
            sourceX = stages.Width - 1.0 - sourceX;
        }

        (double x, double y) = transform.Rotation switch
        {
            ImageRotation.Degrees90 => (stages.Height - 1.0 - sourceY, sourceX),
            ImageRotation.Degrees180 =>
                (stages.Width - 1.0 - sourceX, stages.Height - 1.0 - sourceY),
            ImageRotation.Degrees270 => (sourceY, stages.Width - 1.0 - sourceX),
            _ => (sourceX, sourceY),
        };

        if (stages.Straightened)
        {
            // 역방향 행렬 [[cos, sin], [−sin, cos]] 의 역은 [[cos, −sin], [sin, cos]] 입니다.
            double theta = transform.StraightenAngle * Math.PI / 180.0;
            double cos = Math.Cos(theta);
            double sin = Math.Sin(theta);
            double dx = x - ((stages.OrientedWidth - 1.0) * 0.5);
            double dy = y - ((stages.OrientedHeight - 1.0) * 0.5);
            x = ((stages.StraightenedWidth - 1.0) * 0.5) + (dx * cos) - (dy * sin);
            y = ((stages.StraightenedHeight - 1.0) * 0.5) + (dx * sin) + (dy * cos);
        }

        displayX = (x - stages.CropLeft) / (stages.CroppedWidth - 1.0);
        displayY = (y - stages.CropTop) / (stages.CroppedHeight - 1.0);
        return true;
    }

    /// <summary>
    /// orient → straighten → crop 각 단계의 크기입니다. 두 방향이 같은 것을 씁니다.
    /// </summary>
    private static bool TryStages(
        ImageTransformRecipe transform,
        uint sourceWidth,
        uint sourceHeight,
        out TransformStages stages)
    {
        stages = default;
        // 한 줄짜리 이미지는 정규 좌표를 만들 수 없고, 브러시로 칠할 것도 없습니다.
        if (sourceWidth < 2U || sourceHeight < 2U || !transform.IsValid)
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

        stages = new TransformStages(
            width,
            height,
            orientedWidth,
            orientedHeight,
            straightened,
            straightenedWidth,
            straightenedHeight,
            cropLeft,
            cropTop,
            croppedWidth,
            croppedHeight);
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
