using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

namespace Negaflow.Catalog.UnitTests;

internal static class LibraryFrameOrganizationTests
{
    public static void Run()
    {
        VerifyFrameFlagAndNaming();
        VerifyLocalDodgeBurnPersistence();
    }

    private static void VerifyFrameFlagAndNaming()
    {
        // 깃발 세 상태가 모두 왕복하는지. macOS 가 적는 raw value 와 같은 글자여야 합니다.
        foreach (FramePickState state in new[]
        {
            FramePickState.Picked,
            FramePickState.Rejected,
            FramePickState.Unflagged,
        })
        {
            LibraryFrameWriteResult written = LibraryFrameWriter.Apply(
                FrameRecord(),
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    PickState: state));
            Check(
                written.IsSuccess &&
                    ReadFrame(written.FrameRecord!).Frame?.PickState == state,
                $"library_frame_pick_state_round_trip_{state}");
        }

        // 이름을 떼면 키 자체가 사라져야 합니다. 빈 문자열이 남으면 파일 이름으로 돌아가지
        // 못하고 이름 없는 사진이 됩니다.
        LibraryFrameWriteResult cleared = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(
                ToneAdjustment.Neutral,
                null,
                DisplayName: DisplayNameSelection.Normalized("   ")));
        Check(
            cleared.IsSuccess && !cleared.FrameRecord!.ContainsKey("customDisplayName"),
            "library_frame_display_name_cleared_removes_key");

        // macOS 가 적는 번호 표식을 이름으로 착각하면 카드에 그 문자열이 그대로 나옵니다.
        JsonObject numbered = FrameRecord();
        numbered["customDisplayName"] = "negaflow:photo-number:7";
        LibraryFrameSnapshot? assigned = ReadFrame(numbered).Frame;
        Check(assigned?.AssignedPhotoNumber == 7, "library_frame_assigned_photo_number");
        Check(assigned?.LiteralDisplayName is null, "library_frame_number_is_not_a_name");
        Check(assigned?.PresentationIndex == 7, "library_frame_number_wins_presentation_index");

        // 스캐너 파일은 파일 이름 끝의 _frame_<n> 이 번호입니다.
        JsonObject scanned = FrameRecord();
        scanned.Remove("customDisplayName");
        scanned["rawScanPath"] = @"C:\scans\roll-01\roll_frame_12.tif";
        scanned["scanIndex"] = 3;
        LibraryFrameSnapshot? scannedFrame = ReadFrame(scanned).Frame;
        Check(scannedFrame?.PresentationIndex == 12, "library_frame_scanner_file_index");
        Check(
            scannedFrame?.PreferredBaseDisplayName is null,
            "library_frame_scanner_has_no_base_name");

        // 표식이 없는 파일 이름이면 롤 순번으로 돌아갑니다.
        JsonObject plain = FrameRecord();
        plain.Remove("customDisplayName");
        plain["scanIndex"] = 4;
        Check(ReadFrame(plain).Frame?.PresentationIndex == 4, "library_frame_falls_back_to_scan_index");

        // 가져온 파일은 확장자를 뗀 파일 이름으로 부릅니다.
        JsonObject imported = FrameRecord();
        imported.Remove("customDisplayName");
        imported["sourceKind"] = "imported";
        Check(
            ReadFrame(imported).Frame?.PreferredBaseDisplayName == "IMG_0001",
            "library_frame_imported_uses_file_base_name");
    }

    private static void VerifyLocalDodgeBurnPersistence()
    {
        Guid brushId = Guid.Parse("00000000-0000-0000-0000-000000000101");
        Guid polygonId = Guid.Parse("00000000-0000-0000-0000-000000000102");
        LocalDodgeBurnAdjustment[] recipe =
        [
            new(
                brushId,
                LocalDodgeBurnMode.Dodge,
                0.45,
                true,
                LocalDodgeBurnMask.Brush(
                [
                    new LocalDodgeBurnStroke(
                        [new(-0.1, 0.25), new(0.65, 1.1)],
                        0.06,
                        0.03),
                ])),
            new(
                polygonId,
                LocalDodgeBurnMode.Burn,
                0.7,
                false,
                LocalDodgeBurnMask.Polygon(
                    [new(0.1, 0.1), new(0.9, 0.2), new(0.5, 0.85)],
                    0.2)),
        ];

        LibraryFrameWriteResult written = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(
                ToneAdjustment.Neutral,
                null,
                LocalDodgeBurn: recipe));
        LibraryFrameReadResult reread = written.FrameRecord is { } record
            ? ReadFrame(record)
            : default;
        Check(
            written.IsSuccess && reread.IsSuccess && reread.Frame?.LocalDodgeBurn.Count == 2 &&
            reread.Frame.LocalDodgeBurn[0].Id == brushId &&
            reread.Frame.LocalDodgeBurn[0].Mask.Strokes[0].Points[0] == new LocalDodgeBurnPoint(-0.1, 0.25) &&
            reread.Frame.LocalDodgeBurn[1].Id == polygonId &&
            !reread.Frame.LocalDodgeBurn[1].IsEnabled &&
            reread.Frame.LocalDodgeBurn[1].Mask.Points.Count == 3,
            "library_frame_local_dodge_burn_round_trip");

        LibraryFrameWriteResult ratingWrite = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(ToneAdjustment.Neutral, null, Rating: 4));
        LibraryFrameReadResult ratingRead = ratingWrite.FrameRecord is { } ratingRecord
            ? ReadFrame(ratingRecord)
            : default;
        Check(
            ratingWrite.IsSuccess && ratingRead.IsSuccess && ratingRead.Frame?.Rating == 4,
            "library_frame_rating_round_trip");
        Check(
            ReadFrame(FrameRecord()).Frame?.Rating == 0,
            "library_frame_rating_defaults_to_zero");
        JsonObject outOfRange = FrameRecord();
        outOfRange["rating"] = 7;
        Check(
            ReadFrame(outOfRange).Error == LibraryFrameError.InvalidRating &&
            !LibraryFrameWriter.Apply(
                FrameRecord(),
                new LibraryFrameEdit(ToneAdjustment.Neutral, null, Rating: -1)).IsSuccess,
            "library_frame_rating_rejects_out_of_range");

        JsonObject malformed = FrameRecord();
        malformed["params"]!["localDodgeBurn"] = new JsonArray
        {
            new JsonObject { ["mode"] = "dodge", ["amount"] = 0.5 },
        };
        Check(
            ReadFrame(malformed).Error == LibraryFrameError.InvalidLocalDodgeBurn,
            "library_frame_rejects_local_dodge_burn_without_mask");
    }

}
