using Negaflow.Catalog;
using Negaflow.Shell.Develop.Perspective;

namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>ImageTransform</c>의 수동 결함 도구용 연속 정규 좌표 변환입니다.</summary>
internal static class DevelopDefectCoordinateMapper
{
    private const double StraightenThreshold = 1.0e-4;

    /// <summary>
    /// 브러시도 복제 도장처럼 수평 보정·원근을 풉니다(macOS 가 원본 크기를 넘기도록 함께 고침). 예전에는
    /// 둘을 건너뛰어 각도가 걸린 사진에서 획이 화면 중심에서 멀수록 어긋났습니다.
    /// </summary>
    internal static bool TryMapBrushDisplayToRaw(
        LibraryFrameSnapshot frame,
        DefectPoint display,
        out DefectPoint raw) =>
        TryMapDisplayToRaw(frame, display, includeStraighten: true, out raw);

    internal static bool TryMapCloneDisplayToRaw(
        LibraryFrameSnapshot frame,
        DefectPoint display,
        out DefectPoint raw) =>
        TryMapDisplayToRaw(frame, display, includeStraighten: true, out raw);

    internal static bool TryMapCloneRawToDisplay(
        LibraryFrameSnapshot frame,
        DefectPoint raw,
        out DefectPoint display)
    {
        display = default;
        if (frame.SourceMetadata is not { PixelWidth: > 0U, PixelHeight: > 0U } metadata ||
            !frame.ImageTransform.IsValid || !Finite(raw))
        {
            return false;
        }

        ImageTransformRecipe transform = frame.ImageTransform;
        double x = raw.X;
        double y = raw.Y;
        if (transform.FlipHorizontal)
        {
            x = 1.0 - x;
        }
        if (transform.FlipVertical)
        {
            y = 1.0 - y;
        }
        (x, y) = transform.Rotation switch
        {
            ImageRotation.Degrees90 => (1.0 - y, x),
            ImageRotation.Degrees180 => (1.0 - x, 1.0 - y),
            ImageRotation.Degrees270 => (y, 1.0 - x),
            _ => (x, y),
        };

        ApplyPerspectiveForward(transform, metadata.PixelWidth, metadata.PixelHeight, ref x, ref y);
        ApplyStraightenForward(
            transform,
            metadata.PixelWidth,
            metadata.PixelHeight,
            ref x,
            ref y);
        if (transform.Crop is { } crop)
        {
            x = (x - crop.X) / crop.Width;
            double up = ((1.0 - y) - crop.Y) / crop.Height;
            y = 1.0 - up;
        }
        if (!double.IsFinite(x) || !double.IsFinite(y))
        {
            return false;
        }
        display = new DefectPoint(x, y);
        return true;
    }

    private static bool TryMapDisplayToRaw(
        LibraryFrameSnapshot frame,
        DefectPoint display,
        bool includeStraighten,
        out DefectPoint raw)
    {
        raw = default;
        if (frame.SourceMetadata is not { PixelWidth: > 0U, PixelHeight: > 0U } metadata ||
            !frame.ImageTransform.IsValid || !Finite(display))
        {
            return false;
        }

        ImageTransformRecipe transform = frame.ImageTransform;
        double x = display.X;
        double y = display.Y;
        if (transform.Crop is { } crop)
        {
            x = crop.X + (x * crop.Width);
            y = 1.0 - (crop.Y + ((1.0 - y) * crop.Height));
        }
        if (includeStraighten)
        {
            ApplyStraightenInverse(
                transform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                ref x,
                ref y);
            ApplyPerspectiveInverse(transform, metadata.PixelWidth, metadata.PixelHeight, ref x, ref y);
        }
        (x, y) = transform.Rotation switch
        {
            ImageRotation.Degrees90 => (y, 1.0 - x),
            ImageRotation.Degrees180 => (1.0 - x, 1.0 - y),
            ImageRotation.Degrees270 => (1.0 - y, x),
            _ => (x, y),
        };
        if (transform.FlipVertical)
        {
            y = 1.0 - y;
        }
        if (transform.FlipHorizontal)
        {
            x = 1.0 - x;
        }
        if (!double.IsFinite(x) || !double.IsFinite(y))
        {
            return false;
        }
        raw = new DefectPoint(x, y);
        return true;
    }

    /// <summary>원근 출력 사각형 기준 정규좌표 → 원근 보정 전(회전 뒤) 정규좌표. macOS <c>inverseUnit</c>.</summary>
    private static void ApplyPerspectiveInverse(
        ImageTransformRecipe transform, uint width, uint height, ref double x, ref double y)
    {
        Dimensions(transform.Rotation, width, height, out double sw, out double sh);
        if (PerspectiveGeometry.Mapping(transform.Perspective, sw, sh) is not { } mapping ||
            PerspectiveGeometry.Apply(
                mapping.Inverse,
                mapping.OutputLeft + (x * mapping.OutputWidth),
                mapping.OutputTop + (y * mapping.OutputHeight)) is not { } oriented)
        {
            return;
        }
        x = oriented.X / sw;
        y = oriented.Y / sh;
    }

    /// <summary>회전 뒤 정규좌표 → 원근 출력 사각형 기준 정규좌표. macOS <c>forwardUnit</c>.</summary>
    private static void ApplyPerspectiveForward(
        ImageTransformRecipe transform, uint width, uint height, ref double x, ref double y)
    {
        Dimensions(transform.Rotation, width, height, out double sw, out double sh);
        if (PerspectiveGeometry.Mapping(transform.Perspective, sw, sh) is not { } mapping ||
            PerspectiveGeometry.Apply(mapping.Forward, x * sw, y * sh) is not { } corrected)
        {
            return;
        }
        x = (corrected.X - mapping.OutputLeft) / mapping.OutputWidth;
        y = (corrected.Y - mapping.OutputTop) / mapping.OutputHeight;
    }

    /// <summary>수평 보정의 입력 크기 = 원근 보정의 출력 크기(없으면 회전 뒤 크기).</summary>
    private static void StraightenInput(
        ImageTransformRecipe transform, uint width, uint height, out double sw, out double sh)
    {
        Dimensions(transform.Rotation, width, height, out sw, out sh);
        if (PerspectiveGeometry.Mapping(transform.Perspective, sw, sh) is { } mapping)
        {
            sw = mapping.OutputWidth;
            sh = mapping.OutputHeight;
        }
    }

    private static void ApplyStraightenInverse(
        ImageTransformRecipe transform,
        uint width,
        uint height,
        ref double x,
        ref double y)
    {
        if (Math.Abs(transform.StraightenAngle) <= StraightenThreshold)
        {
            return;
        }
        StraightenInput(transform, width, height, out double sw, out double sh);
        StraightenedExtent(sw, sh, transform.StraightenAngle, out double wp, out double hp);
        double cx = sw / 2.0;
        double cy = sh / 2.0;
        double px = (x * wp) + (cx - (wp / 2.0));
        double py = ((1.0 - y) * hp) + (cy - (hp / 2.0));
        double theta = transform.StraightenAngle * Math.PI / 180.0;
        double cosine = Math.Cos(theta);
        double sine = Math.Sin(theta);
        double dx = px - cx;
        double dy = py - cy;
        x = (cx + (dx * cosine) - (dy * sine)) / sw;
        y = 1.0 - ((cy + (dx * sine) + (dy * cosine)) / sh);
    }

    private static void ApplyStraightenForward(
        ImageTransformRecipe transform,
        uint width,
        uint height,
        ref double x,
        ref double y)
    {
        if (Math.Abs(transform.StraightenAngle) <= StraightenThreshold)
        {
            return;
        }
        StraightenInput(transform, width, height, out double sw, out double sh);
        StraightenedExtent(sw, sh, transform.StraightenAngle, out double wp, out double hp);
        double cx = sw / 2.0;
        double cy = sh / 2.0;
        double dx = (x * sw) - cx;
        double dy = ((1.0 - y) * sh) - cy;
        double theta = transform.StraightenAngle * Math.PI / 180.0;
        double cosine = Math.Cos(theta);
        double sine = Math.Sin(theta);
        double px = cx + (dx * cosine) + (dy * sine);
        double py = cy - (dx * sine) + (dy * cosine);
        x = (px - (cx - (wp / 2.0))) / wp;
        y = 1.0 - ((py - (cy - (hp / 2.0))) / hp);
    }

    private static void StraightenedExtent(
        double width,
        double height,
        double angle,
        out double resultWidth,
        out double resultHeight)
    {
        double theta = angle * Math.PI / 180.0;
        double cosine = Math.Abs(Math.Cos(theta));
        double sine = Math.Abs(Math.Sin(theta));
        resultHeight = Math.Min(
            width * height / ((width * cosine) + (height * sine)),
            height * height / ((width * sine) + (height * cosine)));
        resultWidth = (width / height) * resultHeight;
    }

    private static void Dimensions(
        ImageRotation rotation,
        uint width,
        uint height,
        out double transformedWidth,
        out double transformedHeight)
    {
        bool swaps = rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270;
        transformedWidth = swaps ? height : width;
        transformedHeight = swaps ? width : height;
    }

    private static bool Finite(DefectPoint point) =>
        double.IsFinite(point.X) && double.IsFinite(point.Y);
}
