using System.Text.Json.Nodes;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 채널 범위 롤 교정의 규칙(합치기·정규화)과 저장(레시피 안의 교정값, params 형제인 측정 모양),
/// 낡음 처리를 확인합니다. macOS <c>ChannelRangeCalibrationTests</c> 와 같은 규칙입니다.
/// </summary>
internal static class LibraryChannelRangeTests
{
    public static void Run()
    {
        VerifyNormalizationAndCombine();
        VerifyPersistence();
        VerifyInvalidation();
    }

    private static void VerifyNormalizationAndCombine()
    {
        ChannelRangeRgb? unit = ChannelRangeCalibration.Sanitized(new(2.0, 2.0, 2.0));
        Check(unit is { } u && Math.Abs(u.Red - 1.0) < 1.0e-12 && Math.Abs(u.Blue - 1.0) < 1.0e-12,
            "channel_range_normalizes_to_unit_geometric_mean");
        Check(ChannelRangeCalibration.Sanitized(new(0.2, 1.0, 1.0)) is null, "channel_range_rejects_out_of_range");
        Check(ChannelRangeCalibration.Sanitized(new(1.0, 1.0, 0.0)) is null, "channel_range_rejects_zero");
        Check(ChannelRangeCalibration.Sanitized(new(double.NaN, 1.0, 1.0)) is null, "channel_range_rejects_nan");

        ChannelRangeRgb shape = new(0.85, 0.97, 1.21);
        Check(ChannelRangeCalibration.Combine([shape, shape]) is null, "combine_needs_three_frames");
        ChannelRangeRgb outlier = new(1.3, 1.0, 0.77);
        ChannelRangeRgb? combined = ChannelRangeCalibration.Combine([shape, shape, outlier, shape, shape]);
        ChannelRangeRgb expected = ChannelRangeCalibration.Sanitized(shape)!.Value;
        Check(combined is { } c && Math.Abs(c.Red - expected.Red) < 1.0e-9 && Math.Abs(c.Blue - expected.Blue) < 1.0e-9,
            "combine_takes_the_channel_median_not_the_outlier");
        Check(combined is { } g && Math.Abs(g.Red * g.Green * g.Blue - 1.0) < 1.0e-9,
            "combine_keeps_unit_geometric_mean");

        ChannelRangeRgb a = new(0.80, 0.98, 1.28), b = new(1.05, 1.0, 0.95);
        Check(ChannelRangeCalibration.Combine([a, b, a, b, a, b]) is null, "combine_refuses_mixed_stocks");
        Check(ChannelRangeCalibration.Combine(
            [new(-1, 1, 1), new(double.NaN, 1, 1), new(0.1, 1, 9), new(0.9, 1, 1.1), new(0.9, 1, 1.1)]) is null,
            "combine_ignores_invalid_measurements");
    }

    private static void VerifyPersistence()
    {
        JsonObject original = FrameRecord();
        Check(original["rangeShapeRGB"] is null && original["params"]!["channelRange"] is null,
            "channel_range_starts_absent");
        ChannelRangeRgb range = new(0.9, 1.0, 1.0 / 0.9);

        LibraryFrameWriteResult stamped = ChannelRangeWriter.Apply(original, range);
        Check(stamped.IsSuccess && stamped.FrameRecord is not null, "channel_range_write_success");
        Check(original["params"]!["channelRange"] is null, "channel_range_write_leaves_input_alone");
        Check(stamped.FrameRecord!["params"]!["channelRange"] is JsonArray, "channel_range_lives_in_the_recipe");
        LibraryFrameReadResult reread = ReadFrame(stamped.FrameRecord!);
        Check(reread.IsSuccess && reread.Frame?.ChannelRange is { } read &&
            Math.Abs(read.Red - 0.9) < 1.0e-12 && Math.Abs(read.Blue - 1.0 / 0.9) < 1.0e-12,
            "channel_range_round_trip");
        Check(ChannelRangeWriter.Apply(stamped.FrameRecord!, null).FrameRecord!["params"]!["channelRange"] is null,
            "channel_range_clears_the_key");
        Check(!ChannelRangeWriter.Apply(FrameRecord(), new ChannelRangeRgb(9.0, 1.0, 0.1)).IsSuccess,
            "channel_range_writer_rejects_out_of_range");

        LibraryFrameWriteResult shaped = RangeShapeWriter.Apply(original, range);
        Check(shaped.IsSuccess && shaped.FrameRecord!["rangeShapeRGB"] is JsonArray &&
            shaped.FrameRecord!["params"]!["rangeShapeRGB"] is null, "range_shape_lives_beside_params");
        Check(ReadFrame(shaped.FrameRecord!).Frame?.RangeShape is not null, "range_shape_round_trip");
        Check(ReadFrame(RangeShapeWriter.Apply(shaped.FrameRecord!, null).FrameRecord!).Frame?.RangeShape is null,
            "range_shape_clear");

        // 모르는 형식이나 범위 밖이면 프레임을 거부하지 않고 "아직 없음" 으로 읽는다.
        JsonObject broken = FrameRecord();
        broken["rangeShapeRGB"] = new JsonArray(9.0, 1.0, 0.1);
        broken["params"]!.AsObject()["channelRange"] = new JsonArray(1.0, 1.0);
        LibraryFrameReadResult tolerated = ReadFrame(broken);
        Check(tolerated.IsSuccess && tolerated.Frame?.RangeShape is null && tolerated.Frame?.ChannelRange is null,
            "channel_range_tolerates_bad_stored_values");
    }

    private static void VerifyInvalidation()
    {
        ChannelRangeRgb shape = new(0.9, 1.0, 1.0 / 0.9);
        JsonObject withShape = RangeShapeWriter.Apply(FrameRecord(), shape).FrameRecord!;

        // 베이스 값이 바뀌어도 롤 교정의 재료로는 같은 사실이라 남는다.
        JsonObject baseChanged = withShape.DeepClone().AsObject();
        baseChanged["params"]!.AsObject()["baseScale"] = 1.1;
        AppliedBaseInvalidation.Apply(withShape, baseChanged);
        Check(baseChanged["rangeShapeRGB"] is not null, "range_shape_survives_a_base_change");

        // 입력 감마가 바뀌면 입력 해석이 달라지므로 버린다.
        JsonObject gammaChanged = withShape.DeepClone().AsObject();
        gammaChanged["params"]!.AsObject()["inputGamma"] = 1.8;
        AppliedBaseInvalidation.Apply(withShape, gammaChanged);
        Check(gammaChanged["rangeShapeRGB"] is null, "range_shape_dropped_on_input_gamma_change");

        JsonObject filmChanged = withShape.DeepClone().AsObject();
        filmChanged["filmType"] = "bwNegative";
        AppliedBaseInvalidation.Apply(withShape, filmChanged);
        Check(filmChanged["rangeShapeRGB"] is null, "range_shape_dropped_on_film_type_change");
    }
}
