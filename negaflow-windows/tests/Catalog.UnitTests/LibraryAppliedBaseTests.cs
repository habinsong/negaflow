using System.Text.Json.Nodes;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

namespace Negaflow.Catalog.UnitTests;

internal static class LibraryAppliedBaseTests
{
    public static void Run() => VerifyAppliedBasePersistence();

    private static void VerifyAppliedBasePersistence()
    {
        JsonObject original = FrameRecord();
        Check(original["baseRGB"] is null, "applied_base_starts_absent");

        LibraryFrameWriteResult write = AppliedBaseWriter.Apply(
            original,
            new ManualBaseRgb(0.22128, 0.13298, 0.071016));
        Check(write.IsSuccess, "applied_base_write_success");
        if (write.FrameRecord is not { } updated)
        {
            return;
        }
        Check(original["baseRGB"] is null, "applied_base_write_leaves_input_alone");
        Check(
            updated["params"]!["exposure"] is not null && updated["baseRGB"] is JsonArray,
            "applied_base_lives_beside_params");

        LibraryFrameReadResult reread = ReadFrame(updated);
        Check(reread.IsSuccess, "applied_base_round_trip");
        Check(
            reread.Frame?.AppliedBase == new ManualBaseRgb(0.22128, 0.13298, 0.071016),
            "applied_base_reads_three_channels");

        LibraryFrameWriteResult cleared = AppliedBaseWriter.Apply(updated, null);
        Check(cleared.FrameRecord?["baseRGB"] is null, "applied_base_clears_the_key");
        Check(
            ReadFrame(cleared.FrameRecord!).Frame?.AppliedBase is null,
            "applied_base_missing_is_legacy_null");

        JsonObject broken = FrameRecord();
        broken["baseRGB"] = new JsonArray(0.8, 0.6);
        Check(
            ReadFrame(broken).Error == LibraryFrameError.InvalidAppliedBase,
            "applied_base_rejects_wrong_arity");

        Check(
            !AppliedBaseWriter.Apply(
                FrameRecord(),
                new ManualBaseRgb(double.NaN, 0.5, 0.4)).IsSuccess,
            "applied_base_rejects_nonfinite");
    }
}
