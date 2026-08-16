using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

namespace Negaflow.Catalog.UnitTests;

internal static class LibraryFrameValidationTests
{
    public static void Run() => VerifyLibraryFrameRefusals();

    private static void VerifyLibraryFrameRefusals()
    {
        JsonObject missingId = FrameRecord();
        missingId.Remove("id");
        Check(
            ReadFrame(missingId).Error == LibraryFrameError.MissingId,
            "library_frame_rejects_missing_id");

        JsonObject blankId = FrameRecord();
        blankId["id"] = "   ";
        Check(
            ReadFrame(blankId).Error == LibraryFrameError.InvalidId,
            "library_frame_rejects_blank_id");

        JsonObject missingPath = FrameRecord();
        missingPath.Remove("rawScanPath");
        Check(
            ReadFrame(missingPath).Error == LibraryFrameError.MissingSourcePath,
            "library_frame_rejects_missing_source_path");

        // 상대 경로는 무엇을 기준으로 푸는지가 catalog 에 없습니다.
        JsonObject relativePath = FrameRecord();
        relativePath["rawScanPath"] = @"scans\IMG_0001.tif";
        Check(
            ReadFrame(relativePath).Error == LibraryFrameError.InvalidSourcePath,
            "library_frame_rejects_relative_source_path");

        JsonObject relativeInfraredPath = FrameRecord();
        relativeInfraredPath["infraredScanPath"] = @"scans\IMG_0001.ir.tif";
        Check(
            ReadFrame(relativeInfraredPath).Error == LibraryFrameError.InvalidInfraredPath,
            "library_frame_rejects_relative_infrared_path");

        JsonObject malformedMetadata = FrameRecord();
        malformedMetadata["sourceMetadata"]!.AsObject()["pixelWidth"] = 0;
        Check(
            ReadFrame(malformedMetadata).Error == LibraryFrameError.InvalidSourceMetadata,
            "library_frame_rejects_invalid_source_metadata");

        JsonObject sameInfraredPath = FrameRecord();
        sameInfraredPath["infraredScanPath"] = sameInfraredPath["rawScanPath"]!.GetValue<string>();
        Check(
            ReadFrame(sameInfraredPath).Error == LibraryFrameError.InvalidInfraredPath,
            "library_frame_rejects_ir_path_equal_to_rgb_path");

        JsonObject shortBase = FrameRecord();
        shortBase["params"]!["manualBaseRGB"] = new JsonArray(0.2, 0.2);
        Check(
            ReadFrame(shortBase).Error == LibraryFrameError.InvalidManualBase,
            "library_frame_rejects_two_channel_base");

        JsonObject textBase = FrameRecord();
        textBase["params"]!["manualBaseRGB"] = new JsonArray(0.2, "0.2", 0.2);
        Check(
            ReadFrame(textBase).Error == LibraryFrameError.InvalidManualBase,
            "library_frame_rejects_non_numeric_base");

        JsonObject invalidBaseMode = FrameRecord();
        invalidBaseMode["params"]!["baseEstimationMode"] = "guessed";
        Check(
            ReadFrame(invalidBaseMode).Error == LibraryFrameError.InvalidBaseRecipe,
            "library_frame_rejects_unknown_base_mode");

        JsonObject invalidBaseIdentifier = FrameRecord();
        invalidBaseIdentifier["params"]!["filmStockDminID"] = " ";
        Check(
            ReadFrame(invalidBaseIdentifier).Error == LibraryFrameError.InvalidBaseRecipe,
            "library_frame_rejects_blank_base_identifier");

        JsonObject invalidImageTransform = FrameRecord();
        invalidImageTransform["params"]!["imageTransform"]!["cropRect"] =
            new JsonArray(0.7, 0.2, 0.4, 0.6);
        Check(
            ReadFrame(invalidImageTransform).Error == LibraryFrameError.InvalidImageTransform,
            "library_frame_rejects_out_of_bounds_crop");

        JsonObject invalidNoiseReduction = FrameRecord();
        invalidNoiseReduction["params"]!["noiseReductionDetail"] = 1.1;
        Check(
            ReadFrame(invalidNoiseReduction).Error == LibraryFrameError.InvalidNoiseReduction,
            "library_frame_rejects_out_of_range_noise_reduction");

        JsonObject invalidPointCurveShape = FrameRecord();
        invalidPointCurveShape["params"]!["pointCurves"]!["rgb"] = new JsonObject();
        Check(
            ReadFrame(invalidPointCurveShape).Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_rejects_point_curve_non_array");

        JsonObject invalidPointCurveCoordinate = FrameRecord();
        invalidPointCurveCoordinate["params"]!["pointCurves"]!["red"] = new JsonArray
        {
            new JsonObject { ["x"] = 0.25, ["y"] = "0.25" },
        };
        Check(
            ReadFrame(invalidPointCurveCoordinate).Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_rejects_point_curve_non_numeric_coordinate");

        JsonObject duplicatePointCurveCoordinate = FrameRecord();
        duplicatePointCurveCoordinate["params"]!["pointCurves"]!["blue"] = new JsonArray
        {
            new JsonObject { ["x"] = 0.5, ["y"] = 0.4 },
            new JsonObject { ["x"] = 0.5, ["y"] = 0.6 },
        };
        Check(
            ReadFrame(duplicatePointCurveCoordinate).Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_rejects_point_curve_duplicate_x");

        // 있는데 수가 아니면 조용히 0 으로 만들지 않습니다.
        JsonObject textTone = FrameRecord();
        textTone["params"]!["exposure"] = "0.5";
        Check(
            ReadFrame(textTone).Error == LibraryFrameError.InvalidToneValue,
            "library_frame_rejects_non_numeric_tone");

        JsonObject missingParameters = FrameRecord();
        missingParameters.Remove("params");
        Check(
            ReadFrame(missingParameters).Error == LibraryFrameError.MissingParameters,
            "library_frame_rejects_missing_parameters");

        // route 거부는 그대로 전달되고 어느 쪽이 문제인지 구별됩니다.
        JsonObject brokenRoute = FrameRecord();
        brokenRoute["params"]!["filmType"] = "colorPositive";
        LibraryFrameReadResult routeFailure = ReadFrame(brokenRoute);
        Check(
            routeFailure.Error == LibraryFrameError.InvalidDevelopRoute,
            "library_frame_reports_route_failure");
        Check(
            routeFailure.RouteError == DevelopRouteError.MismatchedFilmType,
            "library_frame_preserves_route_error");
        Check(routeFailure.Frame is null, "library_frame_no_partial_snapshot");
    }

    /// <summary>
    /// 적어 둔 메타데이터의 왕복입니다. 레시피가 아니므로 params 바깥에 있어야 하고, 이 writer 가
    /// 모르는 키(macOS 의 원본 해시)는 그대로 남아야 합니다.
    /// </summary>
}
