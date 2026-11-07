using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class ImageEffectRecipeJsonCodec
{
    internal static void Write(JsonObject parameters, LibraryFrameEdit edit)
    {
        if (edit.ImageTransform is { } transform)
        {
            parameters[LibraryFrameReader.ImageTransformName] = WriteImageTransform(transform);
        }
        if (edit.Texture is { } texture)
        {
            parameters[LibraryFrameReader.GrainName] = texture.Grain;
            parameters[LibraryFrameReader.SharpnessName] = texture.Sharpness;
            parameters[LibraryFrameReader.HalationName] = texture.Halation;
            parameters[LibraryFrameReader.ClarityName] = texture.Clarity;
            parameters[LibraryFrameReader.VignetteName] = texture.Vignette;
        }
        if (edit.NoiseReduction is { } noiseReduction)
        {
            parameters[LibraryFrameReader.NoiseReductionName] = noiseReduction.Strength;
            parameters[LibraryFrameReader.NoiseReductionLumaName] = noiseReduction.Luma;
            parameters[LibraryFrameReader.NoiseReductionChromaName] = noiseReduction.Chroma;
            parameters[LibraryFrameReader.NoiseReductionDarkToneName] = noiseReduction.DarkTone;
            parameters[LibraryFrameReader.NoiseReductionDetailName] = noiseReduction.Detail;
            parameters[LibraryFrameReader.NoiseReductionGrainProtectName] =
                noiseReduction.GrainProtect;
        }
        if (edit.DefectRemovalStrength is { } defectRemoval)
        {
            parameters[LibraryFrameReader.DefectRemovalName] = defectRemoval;
        }
        if (edit.BwToning is { } bwToning)
        {
            WriteBwToning(parameters, bwToning);
        }
    }

    private static JsonObject WriteImageTransform(ImageTransformRecipe transform)
    {
        JsonObject result = new()
        {
            [LibraryFrameReader.ImageTransformRotationName] = (int)transform.Rotation,
            [LibraryFrameReader.ImageTransformFlipHorizontalName] = transform.FlipHorizontal,
            [LibraryFrameReader.ImageTransformFlipVerticalName] = transform.FlipVertical,
            [LibraryFrameReader.ImageTransformStraightenAngleName] = transform.StraightenAngle,
        };
        if (transform.Crop is { } crop)
        {
            result[LibraryFrameReader.ImageTransformCropRectName] = new JsonArray(
                crop.X, crop.Y, crop.Width, crop.Height);
        }
        if (transform.CropAspect is { } cropAspect)
        {
            result[LibraryFrameReader.ImageTransformCropAspectName] = cropAspect;
        }
        // 원근 보정이 없으면 쓰지 않습니다 — 기존 카탈로그와 바이트가 같게 남습니다(macOS 와 같음).
        if (!transform.Perspective.IsIdentity)
        {
            result[LibraryFrameReader.ImageTransformPerspectiveName] = WritePerspective(transform.Perspective);
        }
        return result;
    }

    /// <summary>macOS <c>PerspectiveCorrection</c> 의 Codable 모양과 같은 이름·값입니다.</summary>
    private static JsonObject WritePerspective(PerspectiveRecipe perspective)
    {
        JsonArray guides = [];
        foreach (PerspectiveGuideRecipe guide in perspective.Guides)
        {
            guides.Add(new JsonObject
            {
                ["start"] = new JsonArray(guide.StartX, guide.StartY),
                ["end"] = new JsonArray(guide.EndX, guide.EndY),
            });
        }
        return new JsonObject
        {
            ["mode"] = perspective.Mode.ToString().ToLowerInvariant(),
            ["solvedVertical"] = perspective.SolvedVertical,
            ["solvedHorizontal"] = perspective.SolvedHorizontal,
            ["solvedRotate"] = perspective.SolvedRotate,
            ["vertical"] = perspective.Vertical,
            ["horizontal"] = perspective.Horizontal,
            ["rotate"] = perspective.Rotate,
            ["aspect"] = perspective.Aspect,
            ["scale"] = perspective.Scale,
            ["offsetX"] = perspective.OffsetX,
            ["offsetY"] = perspective.OffsetY,
            ["constrainCrop"] = perspective.ConstrainCrop,
            ["guides"] = guides,
        };
    }

    private static void WriteBwToning(JsonObject parameters, BwToningRecipe bwToning)
    {
        if (bwToning.Mode == BwToningMode.None)
        {
            parameters.Remove(LibraryFrameReader.BwToningName);
            return;
        }
        parameters[LibraryFrameReader.BwToningName] = new JsonObject
        {
            [LibraryFrameReader.BwToningModeName] = bwToning.Mode switch
            {
                BwToningMode.Selenium => "selenium",
                BwToningMode.Sepia => "sepia",
                _ => "none",
            },
            [LibraryFrameReader.BwToningShadowHueName] = bwToning.ShadowHue,
            [LibraryFrameReader.BwToningHighlightHueName] = bwToning.HighlightHue,
            [LibraryFrameReader.BwToningStrengthName] = bwToning.Strength,
        };
    }
}
