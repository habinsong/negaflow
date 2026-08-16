using System.Globalization;
using System.Text.Json;
using static Negaflow.Catalog.LibraryJsonValueReader;
using static Negaflow.Catalog.LibraryFrameReader;

namespace Negaflow.Catalog;

internal static class ImageEffectRecipeJsonReader
{
    internal static bool TryReadTexture(JsonElement parameters, out TextureRecipe texture)
    {
        texture = TextureRecipe.Identity;
        if (!TryReadOptionalFiniteDouble(parameters, GrainName, 0.0, out double grain) ||
            !TryReadOptionalFiniteDouble(parameters, SharpnessName, 0.0, out double sharpness) ||
            !TryReadOptionalFiniteDouble(parameters, HalationName, 0.0, out double halation) ||
            !TryReadOptionalFiniteDouble(parameters, ClarityName, 0.0, out double clarity) ||
            !TryReadOptionalFiniteDouble(parameters, VignetteName, 0.0, out double vignette))
        {
            return false;
        }
        texture = new TextureRecipe(grain, sharpness, halation, clarity, vignette);
        return texture.IsValid;
    }

    internal static bool TryReadNoiseReduction(
        JsonElement parameters,
        out NoiseReductionRecipe noiseReduction)
    {
        noiseReduction = NoiseReductionRecipe.Identity;
        if (!TryReadOptionalFiniteDouble(parameters, NoiseReductionName, 0.0, out double strength) ||
            !TryReadOptionalFiniteDouble(parameters, NoiseReductionLumaName, 0.5, out double luma) ||
            !TryReadOptionalFiniteDouble(parameters, NoiseReductionChromaName, 0.5, out double chroma) ||
            !TryReadOptionalFiniteDouble(parameters, NoiseReductionDarkToneName, 0.5, out double darkTone) ||
            !TryReadOptionalFiniteDouble(parameters, NoiseReductionDetailName, 0.5, out double detail) ||
            !TryReadOptionalFiniteDouble(
                parameters,
                NoiseReductionGrainProtectName,
                0.0,
                out double grainProtect))
        {
            return false;
        }
        noiseReduction = new NoiseReductionRecipe(
            strength, luma, chroma, darkTone, detail, grainProtect);
        return noiseReduction.IsValid;
    }

    internal static bool TryReadImageTransform(
        JsonElement parameters,
        out ImageTransformRecipe imageTransform)
    {
        imageTransform = ImageTransformRecipe.Identity;
        if (!parameters.TryGetProperty(ImageTransformName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadOptionalRotation(element, out ImageRotation rotation) ||
            !TryReadOptionalBoolean(
                element,
                ImageTransformFlipHorizontalName,
                false,
                out bool flipHorizontal) ||
            !TryReadOptionalBoolean(
                element,
                ImageTransformFlipVerticalName,
                false,
                out bool flipVertical) ||
            !TryReadOptionalFiniteDouble(
                element,
                ImageTransformStraightenAngleName,
                0.0,
                out double straightenAngle) ||
            !TryReadOptionalCrop(element, out ImageCropRect? crop) ||
            !TryReadOptionalPositiveDouble(
                element,
                ImageTransformCropAspectName,
                out double? cropAspect))
        {
            return false;
        }

        imageTransform = new ImageTransformRecipe(
            rotation,
            flipHorizontal,
            flipVertical,
            crop,
            straightenAngle,
            cropAspect);
        return imageTransform.IsValid;
    }

    internal static bool TryReadOptionalRotation(JsonElement owner, out ImageRotation rotation)
    {
        rotation = ImageRotation.Degrees0;
        if (!owner.TryGetProperty(ImageTransformRotationName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number || !element.TryGetInt32(out int raw))
        {
            return false;
        }
        rotation = (ImageRotation)raw;
        return Enum.IsDefined(rotation);
    }

    internal static bool TryReadOptionalCrop(JsonElement owner, out ImageCropRect? crop)
    {
        crop = null;
        if (!owner.TryGetProperty(ImageTransformCropRectName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array || element.GetArrayLength() != 4)
        {
            return false;
        }
        JsonElement.ArrayEnumerator values = element.EnumerateArray();
        double[] coordinates = new double[4];
        for (int index = 0; index < coordinates.Length; index++)
        {
            if (!values.MoveNext() || values.Current.ValueKind != JsonValueKind.Number ||
                !values.Current.TryGetDouble(out coordinates[index]) ||
                !double.IsFinite(coordinates[index]))
            {
                return false;
            }
        }
        ImageCropRect parsed = new(
            coordinates[0], coordinates[1], coordinates[2], coordinates[3]);
        if (!parsed.IsValid)
        {
            return false;
        }
        crop = parsed;
        return true;
    }

    internal static bool TryReadOptionalPositiveDouble(
        JsonElement owner,
        string name,
        out double? value)
    {
        value = null;
        if (!owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number || !element.TryGetDouble(out double parsed) ||
            !double.IsFinite(parsed) || parsed <= 0.0)
        {
            return false;
        }
        value = parsed;
        return true;
    }

    /// <summary>
    /// 적어 둔 메타데이터입니다. 키가 없으면 적은 적이 없다는 뜻이고, 있는데 모양이 틀리면
    /// 카탈로그가 손상됐다는 뜻이므로 조용히 버리지 않고 거부합니다.
    /// </summary>

    internal static bool TryReadBwToning(JsonElement parameters, out BwToningRecipe bwToning)
    {
        bwToning = BwToningRecipe.None;
        if (!parameters.TryGetProperty(BwToningName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        BwToningMode mode = BwToningMode.None;
        if (element.TryGetProperty(BwToningModeName, out JsonElement modeElement) &&
            modeElement.ValueKind != JsonValueKind.Null)
        {
            switch (modeElement.ValueKind == JsonValueKind.String ? modeElement.GetString() : null)
            {
                case "none":
                    mode = BwToningMode.None;
                    break;
                case "selenium":
                    mode = BwToningMode.Selenium;
                    break;
                case "sepia":
                    mode = BwToningMode.Sepia;
                    break;
                default:
                    return false;
            }
        }

        if (!TryReadOptionalFiniteDouble(
                element,
                BwToningShadowHueName,
                BwToningRecipe.DefaultShadowHue(mode),
                out double shadowHue) ||
            !TryReadOptionalFiniteDouble(
                element,
                BwToningHighlightHueName,
                BwToningRecipe.DefaultHighlightHue(mode),
                out double highlightHue) ||
            !TryReadOptionalFiniteDouble(
                element,
                BwToningStrengthName,
                0.0,
                out double strength))
        {
            return false;
        }

        BwToningRecipe read = new(mode, shadowHue, highlightHue, strength);
        if (!read.IsValid)
        {
            return false;
        }
        bwToning = read;
        return true;
    }

}
