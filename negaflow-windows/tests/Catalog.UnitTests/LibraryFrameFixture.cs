using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

internal static class LibraryFrameFixture
{
    internal static JsonObject FrameRecord()
    {
        return new JsonObject
        {
            ["id"] = "frame-1",
            ["rawScanPath"] = @"C:\scans\roll-01\IMG_0001.tif",
            ["infraredScanPath"] = @"C:\scans\roll-01\IMG_0001.ir.tif",
            ["customDisplayName"] = "Roll 01 / 1",
            ["sourceKind"] = "scanner",
            ["filmType"] = "colorNegative",
            ["sourceMetadata"] = new JsonObject
            {
                ["fileBytes"] = 123456UL,
                ["pixelWidth"] = 6400U,
                ["pixelHeight"] = 4200U,
                ["samplesPerPixel"] = 3,
                ["bitsPerSample"] = 16,
                ["sampleFormat"] = 1,
                ["orientation"] = 1,
            },
            ["futureFrameValue"] = "preserve-me",
            ["params"] = new JsonObject
            {
                ["filmType"] = "colorNegative",
                ["baseEstimationMode"] = "preset",
                ["manualBaseRGB"] = new JsonArray(0.21, 0.22, 0.23),
                ["filmStockDminID"] = "kodak-portra-400",
                ["lightSourceProfileID"] = "v850-led",
                ["scannerProfileID"] = "noritsu__color-nega__kodak-portra-400",
                ["exposure"] = 0.5,
                ["curveShadows"] = -0.25,
                ["pointCurves"] = new JsonObject
                {
                    ["rgb"] = new JsonArray
                    {
                        new JsonObject { ["x"] = 1.0, ["y"] = 1.0 },
                        new JsonObject { ["x"] = 0.0, ["y"] = 0.0 },
                        new JsonObject { ["x"] = 0.45, ["y"] = 0.52 },
                    },
                    ["red"] = new JsonArray
                    {
                        new JsonObject { ["x"] = 0.0, ["y"] = 0.03 },
                        new JsonObject { ["x"] = 1.0, ["y"] = 0.97 },
                    },
                    ["green"] = new JsonArray(),
                    ["blue"] = new JsonArray(),
                },
                ["colorMixer"] = new JsonObject
                {
                    ["hue"] = new JsonArray(0.1, -0.2),
                    ["saturation"] = new JsonArray(0.3),
                    ["luminance"] = new JsonArray(-0.4),
                },
                ["imageTransform"] = new JsonObject
                {
                    ["rotation"] = 1,
                    ["flipHorizontal"] = true,
                    ["flipVertical"] = false,
                    ["cropRect"] = new JsonArray(0.1, 0.2, 0.7, 0.6),
                    ["straightenAngle"] = 1.5,
                    ["cropAspect"] = 1.5,
                },
                ["grain"] = 0.35,
                ["sharpness"] = 0.45,
                ["halation"] = 0.20,
                ["clarity"] = -0.15,
                ["vignette"] = 0.25,
                ["noiseReduction"] = 0.60,
                ["noiseReductionLuma"] = 0.70,
                ["noiseReductionChroma"] = 0.40,
                ["noiseReductionDarkTone"] = 0.55,
                ["noiseReductionDetail"] = 0.65,
                ["noiseReductionGrainProtect"] = 0.30,
                ["unknownAdjustment"] = new JsonObject { ["value"] = 7 },
            },
        };
    }

    internal static LibraryFrameReadResult ReadFrame(JsonObject frameRecord)
    {
        using JsonDocument document = JsonDocument.Parse(
            CatalogJson.SerializeCanonical(frameRecord));
        return LibraryFrameReader.Read(document.RootElement);
    }

}
