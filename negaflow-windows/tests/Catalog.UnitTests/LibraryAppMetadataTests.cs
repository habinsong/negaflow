using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

namespace Negaflow.Catalog.UnitTests;

internal static class LibraryAppMetadataTests
{
    public static void Run() => VerifyAppMetadataPersistence();

    private static void VerifyAppMetadataPersistence()
    {
        JsonObject original = FrameRecord();
        AppMetadataOverlay overlay = new()
        {
            Title = "  Bukhansan  ",
            Caption = "Morning ridge",
            Keywords = ["mountain", "mountain", " temple "],
            Copyright = "(c) 2026 habin song",
            FilmShot = new FilmShotMetadata(
                "Leica",
                "M6",
                "Summicron 35mm",
                "Portra 400",
                400,
                1.0 / 125.0,
                2.8,
                35),
            Revision = 1,
            UpdatedAt = new DateTimeOffset(2026, 8, 14, 1, 2, 3, TimeSpan.Zero),
        };

        LibraryFrameWriteResult write = AppMetadataWriter.Apply(original, overlay);
        Check(write.IsSuccess, "app_metadata_write_success");
        if (write.FrameRecord is not { } updated)
        {
            return;
        }
        Check(
            original["appMetadataOverlay"] is null,
            "app_metadata_write_leaves_input_alone");
        Check(
            updated["params"]!["exposure"] is not null &&
            updated["appMetadataOverlay"] is not null,
            "app_metadata_lives_beside_params");

        LibraryFrameReadResult reread = ReadFrame(updated);
        Check(reread.IsSuccess, "app_metadata_round_trip");
        AppMetadataOverlay? read = reread.Frame?.AppMetadata;
        Check(read?.Title == "Bukhansan", "app_metadata_trims_text");
        Check(
            read is not null && read.Keywords.SequenceEqual(["mountain", "temple"]),
            "app_metadata_drops_duplicate_keywords");
        Check(read?.Revision == 1UL, "app_metadata_keeps_the_revision");
        Check(
            read?.UpdatedAt == new DateTimeOffset(2026, 8, 14, 1, 2, 3, TimeSpan.Zero),
            "app_metadata_round_trips_the_timestamp");
        Check(
            read?.FilmShot?.CameraModel == "M6" && read?.FilmShot?.IsoSpeed == 400,
            "app_metadata_round_trips_the_shot");

        // macOS 만 쓰는 키는 손대지 않습니다.
        updated["appMetadataOverlay"]!["sourceMetadataSHA256"] = new string('a', 64);
        LibraryFrameWriteResult again = AppMetadataWriter.Apply(
            updated,
            overlay with { Title = "Renamed", Revision = 2 });
        Check(
            again.FrameRecord?["appMetadataOverlay"]!["sourceMetadataSHA256"] is not null,
            "app_metadata_preserves_unknown_keys");

        // 다 비우면 키 자체가 사라집니다.
        LibraryFrameWriteResult cleared = AppMetadataWriter.Apply(updated, null);
        Check(
            cleared.FrameRecord?["appMetadataOverlay"] is null,
            "app_metadata_clears_the_node_when_empty");

        // revision 0 은 쓴 적이 없다는 뜻이므로 읽기가 거부합니다.
        JsonObject broken = FrameRecord();
        broken["appMetadataOverlay"] = new JsonObject
        {
            ["version"] = 1,
            ["title"] = "x",
            ["revision"] = 0,
        };
        Check(
            ReadFrame(broken).Error == LibraryFrameError.InvalidAppMetadata,
            "app_metadata_refuses_revision_zero");
    }

}
