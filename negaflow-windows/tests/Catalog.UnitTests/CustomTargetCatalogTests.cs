using System.Text.Json.Nodes;
using Negaflow.Catalog;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

namespace Negaflow.Catalog.UnitTests;

internal static class CustomTargetCatalogTests
{
    private static readonly string[] Ids = ["emulsion", "reversal", "dye-transfer", "skip-bleach", "plate-glass",
        "amber-glass", "ultramarine", "terracotta", "celadon", "nacre", "dichroic", "wetzlar", "classic",
        "studio", "rochester", "slide-show", "cinema", "point-and-shoot"];

    internal static void Run()
    {
        JsonObject input = FrameRecord();
        input[LibraryFrameReader.SourcePathName] = Path.Combine(Path.GetTempPath(), "custom-source.tif");
        input["infraredScanPath"] = Path.Combine(Path.GetTempPath(), "custom-source.ir.tif");
        Check(ReadFrame(input).Frame is not null, "custom_target_fixture_is_readable");
        string unchanged = input.ToJsonString();
        List<CatalogEntityRow> persisted = [];
        for (int i = 0; i < Ids.Length; ++i)
        {
            DevelopTarget target = (DevelopTarget)(i + 7);
            LibraryFrameWriteResult written = LibraryFrameWriter.Apply(input,
                new LibraryFrameEdit(ToneAdjustment.Neutral, null, DevelopTarget: target));
            Check(written.IsSuccess && written.FrameRecord is not null, "custom_target_write_" + Ids[i]);
            if (written.FrameRecord is not { } record) { continue; }
            Check(record["params"]?["developTarget"]?.GetValue<string>() == Ids[i], "custom_target_canonical_id_" + Ids[i]);
            LibraryFrameSnapshot? frame = ReadFrame(record).Frame;
            Check(frame?.DevelopTarget == target, "custom_target_read_" + Ids[i]);
            Check(record[LibraryFrameReader.SourcePathName]?.ToJsonString() == input[LibraryFrameReader.SourcePathName]?.ToJsonString(),
                "custom_target_preserves_source_" + Ids[i]);
            JsonObject stored = record.DeepClone().AsObject();
            stored["id"] = "custom-" + Ids[i];
            persisted.Add(new CatalogEntityRow("custom-" + Ids[i], stored));
            LibraryFrameWriteResult retained = LibraryFrameWriter.Apply(record, new LibraryFrameEdit(ToneAdjustment.Neutral, null));
            Check(retained.FrameRecord is { } kept && ReadFrame(kept).Frame?.DevelopTarget == target,
                "custom_target_unrelated_edit_keeps_target_" + Ids[i]);
        }
        Check(input.ToJsonString() == unchanged, "custom_target_does_not_mutate_input");
        foreach (string invalid in new[] { "cs", "custom", "fujifilm", "leica", "kodachrome", "unknown" })
        {
            JsonObject record = input.DeepClone().AsObject();
            record["params"]!["developTarget"] = invalid;
            Check(ReadFrame(record).Frame is null, "custom_target_rejects_alias_" + invalid);
        }
        Check(!LibraryFrameWriter.Apply(input, new LibraryFrameEdit(ToneAdjustment.Neutral, null,
            DevelopTarget: (DevelopTarget)25)).IsSuccess, "custom_target_rejects_out_of_range");
        VerifyReopen(persisted);
    }

    private static void VerifyReopen(IReadOnlyList<CatalogEntityRow> rows)
    {
        if (!OperatingSystem.IsWindows())
        {
            Console.WriteLine("SKIP custom_sqlite_reopen: catalog storage requires Windows extended paths and MoveFileExW");
            return;
        }
        string directory = Path.Combine(Path.GetTempPath(), "negaflow-custom-catalog-" + Guid.NewGuid().ToString("N"));
        try
        {
            StorageRootSet roots = StorageRootResolver.ResolveForTests(directory).Roots!;
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                var written = session.Write(new CatalogSnapshot(null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    { [CatalogEntityTable.Frames] = rows }));
                Check(written.IsSuccess, "custom_sqlite_write_" + written.Error);
            }
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                CatalogReadResult read = session.Read();
                Check(read.IsSuccess && read.Snapshot?.Rows(CatalogEntityTable.Frames).Count == 18, "custom_sqlite_reopen");
                if (read.Snapshot is not { } snapshot) { return; }
                for (int i = 0; i < rows.Count; ++i)
                {
                    Check(ReadFrame(snapshot.Rows(CatalogEntityTable.Frames)[i].Payload).Frame?.DevelopTarget == (DevelopTarget)(i + 7),
                        "custom_sqlite_keeps_target_" + Ids[i]);
                }
            }
        }
        finally { if (Directory.Exists(directory)) { Directory.Delete(directory, recursive: true); } }
    }
}
