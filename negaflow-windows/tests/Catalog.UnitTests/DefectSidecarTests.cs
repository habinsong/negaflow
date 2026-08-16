using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

using static Negaflow.Catalog.UnitTests.DefectTestFixture;

internal static class DefectSidecarTests
{
    public static void Run(StorageRootSet roots) => VerifyDefectSidecarStore(roots);

    private static void VerifyDefectSidecarStore(StorageRootSet parentRoots)
    {
        string sidecarBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-sidecar");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(sidecarBase).Roots!;
        Guid frameId = Guid.Parse("8ac67219-88d5-46b0-af56-42b4600615f3");
        IReadOnlyList<DefectEditItem> items = DefectRecipeItems();

        DefectEditItem fingerprintProbe = new(
            Guid.Parse("00000000-0000-0000-0000-000000000001"),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(DefectEditSummaryKind.ClassBreakdown),
            BaseSize: null,
            Preview: [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(0, 0, 3, 3),
                    new DefectMask(false, new byte[36]),
                    3,
                    3,
                    new DefectMask(false, new byte[18])),
            ],
        };
        string canonicalV2 = DefectRecipeFingerprint.Compute(
            [fingerprintProbe],
            DefectRecipeFingerprint.LegacyVersion);
        Check(canonicalV2 ==
              "cc899b7949653a977862b0f24247b10dbcb820b7fcd38341823ede922b74b599",
            "defect_fingerprint_preserves_canonical_v2_golden");
        DefectEditItem changedProbe = fingerprintProbe with
        {
            Clusters =
            [
                fingerprintProbe.Clusters![0] with
                {
                    AttenuationR16 = new DefectMask(
                        false,
                        Enumerable.Repeat((byte)1, 18).ToArray()),
                },
            ],
        };
        Check(DefectRecipeFingerprint.Compute(
                  [changedProbe],
                  DefectRecipeFingerprint.LegacyVersion) == canonicalV2,
            "defect_fingerprint_v2_ignores_post_baseline_attenuation");
        Check(DefectRecipeFingerprint.Compute([changedProbe]) !=
              DefectRecipeFingerprint.Compute([fingerprintProbe]),
            "defect_fingerprint_v3_binds_attenuation_bytes");

        DefectRecipeSnapshot revisionOne = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity: null,
            items);
        DefectSidecarWriteResult first = DefectSidecarStore.Write(roots, revisionOne);
        Check(first.IsSuccess && first.Kind == DefectSidecarWriteKind.Written,
            "defect_sidecar_first_write");

        DefectSidecarReadResult read = DefectSidecarStore.Read(roots, frameId);
        Check(read.IsSuccess && read.Snapshot?.RecipeRevision == 1,
            "defect_sidecar_read_revision");
        Check(read.Snapshot?.Items.Select(item => item.Kind).SequenceEqual(
            new[]
            {
                DefectEditKind.Brush,
                DefectEditKind.Region,
                DefectEditKind.Infrared,
                DefectEditKind.Clone,
            }) == true,
            "defect_sidecar_preserves_ordered_kinds");
        JsonObject legacyFingerprintJson = JsonNode.Parse(
            DefectSidecarCodec.Serialize(revisionOne))!.AsObject();
        legacyFingerprintJson["fingerprintVersion"] =
            DefectRecipeFingerprint.LegacyVersion;
        legacyFingerprintJson["recipeSHA256"] = DefectRecipeFingerprint.Compute(
            revisionOne.Items,
            DefectRecipeFingerprint.LegacyVersion);
        DefectSidecarReadResult migratedFingerprint = DefectSidecarCodec.Decode(
            CatalogJson.SerializeCanonical(legacyFingerprintJson),
            frameId,
            validateCompressedMasks: true);
        Check(migratedFingerprint.IsSuccess &&
              migratedFingerprint.Snapshot?.FingerprintVersion ==
                  DefectRecipeFingerprint.CurrentVersion &&
              migratedFingerprint.Snapshot.RecipeSha256 == revisionOne.RecipeSha256,
            "defect_sidecar_dual_reads_v2_and_migrates_identity_to_v3");
        JsonObject migratedFingerprintJson = JsonNode.Parse(
            DefectSidecarCodec.Serialize(migratedFingerprint.Snapshot!))!.AsObject();
        Check(migratedFingerprintJson["fingerprintVersion"]!.GetValue<int>() ==
                  DefectRecipeFingerprint.CurrentVersion &&
              migratedFingerprintJson["recipeSHA256"]!.GetValue<string>() ==
                  revisionOne.RecipeSha256,
            "defect_sidecar_migrated_snapshot_serializes_as_v3");
        Check(read.Snapshot is { } decodedRecipe &&
              DefectMaskCodec.TryDecodeRgba8(
                  decodedRecipe.Items[1].RegionMask!,
                  2,
                  2,
                  out byte[] decodedRegionMask) &&
              decodedRegionMask.SequenceEqual(
                  Enumerable.Range(0, 16).Select(value => (byte)value)),
            "defect_sidecar_preserves_region_mask");
        Check(read.Snapshot is { } decodedInfraredRecipe &&
              DefectMaskCodec.TryDecodeR16LittleEndian(
                  decodedInfraredRecipe.Items[2].Clusters![0].AttenuationR16!,
                  2,
                  2,
                  out byte[] decodedAttenuation) &&
              decodedAttenuation.SequenceEqual(
                  new byte[] { 0x00, 0x00, 0x01, 0x00, 0x34, 0x12, 0xff, 0xff }),
            "defect_sidecar_preserves_infrared_attenuation_r16");
        Check(DefectSidecarStore.Write(roots, revisionOne).Kind ==
              DefectSidecarWriteKind.AlreadyCurrent,
            "defect_sidecar_same_snapshot_idempotent");

        string firstSidecarPath = DefectSidecarStore.PathFor(roots, frameId);
        byte[] firstSidecarBytes = File.ReadAllBytes(firstSidecarPath);
        JsonObject corruptedAttenuation = JsonNode.Parse(firstSidecarBytes)!.AsObject();
        JsonObject infraredCluster = corruptedAttenuation["items"]![2]!["clusters"]![0]!
            .AsObject();
        infraredCluster["attenuationR16"]!["data"] = Convert.ToBase64String([1, 2, 3]);
        File.WriteAllBytes(
            firstSidecarPath,
            CatalogJson.SerializeCanonical(corruptedAttenuation));
        Check(DefectSidecarStore.Read(roots, frameId).Error ==
              DefectSidecarError.InvalidContent,
            "defect_sidecar_corrupt_infrared_attenuation_rejected");
        File.WriteAllBytes(firstSidecarPath, firstSidecarBytes);

        Guid legacyFrameId = Guid.Parse("316fb66a-b882-4130-82dd-854976a6e6ac");
        DefectEditItem legacyInfrared = items[2] with
        {
            Clusters =
            [
                items[2].Clusters![0] with { AttenuationR16 = null },
            ],
        };
        DefectRecipeSnapshot legacySnapshot = DefectRecipeSnapshot.Create(
            legacyFrameId,
            recipeRevision: 1,
            sourceIdentity: null,
            [legacyInfrared]);
        JsonObject legacyJson = JsonNode.Parse(
            DefectSidecarCodec.Serialize(legacySnapshot))!.AsObject();
        legacyJson["items"]![0]!["clusters"]![0]!.AsObject()
            .Remove("attenuationR16");
        Check(DefectSidecarCodec.Decode(
                  CatalogJson.SerializeCanonical(legacyJson),
                  legacyFrameId,
                  validateCompressedMasks: true).IsSuccess,
            "defect_sidecar_legacy_mask_only_cluster_reads");

        DefectSourceIdentity sourceIdentity = new(
            1_234,
            new string('a', 64));
        DefectRecipeSnapshot bound = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity,
            items);
        Check(DefectSidecarStore.Write(roots, bound).Kind ==
              DefectSidecarWriteKind.Written,
            "defect_sidecar_same_revision_binds_source_identity");
        Check(DefectSidecarStore.Read(roots, frameId).Snapshot?.SourceIdentity ==
              sourceIdentity,
            "defect_sidecar_source_identity_readback");

        DefectEditItem changedAttenuation = items[2] with
        {
            Clusters =
            [
                items[2].Clusters![0] with
                {
                    AttenuationR16 = new DefectMask(
                        false,
                        new byte[] { 0x00, 0x00, 0x01, 0x00, 0x35, 0x12, 0xff, 0xff }),
                },
            ],
        };
        DefectRecipeSnapshot attenuationConflict = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity,
            [items[0], items[1], changedAttenuation, items[3]]);
        Check(DefectSidecarStore.Write(roots, attenuationConflict).Error ==
              DefectSidecarError.ConflictingSameRevision,
            "defect_sidecar_same_revision_attenuation_conflict");

        DefectEditItem changedRegion = items[1] with { Strength = 0.25 };
        DefectRecipeSnapshot conflicting = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity,
            [items[0], changedRegion, items[2], items[3]]);
        Check(DefectSidecarStore.Write(roots, conflicting).Error ==
              DefectSidecarError.ConflictingSameRevision,
            "defect_sidecar_same_revision_conflict");

        DefectRecipeSnapshot revisionTwo = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 2,
            sourceIdentity,
            [items[0], changedRegion, items[2], items[3]]);
        Check(DefectSidecarStore.Write(roots, revisionTwo).Kind ==
              DefectSidecarWriteKind.Written,
            "defect_sidecar_newer_revision_writes");
        DefectSidecarWriteResult stale = DefectSidecarStore.Write(roots, bound);
        Check(stale.Kind == DefectSidecarWriteKind.SkippedNewer &&
              stale.ExistingRevision == 2,
            "defect_sidecar_stale_completion_skipped");

        Check(DefectSidecarStore.Remove(roots, frameId, minimumRevision: 3).IsSuccess,
            "defect_sidecar_revision_aware_remove");
        Check(DefectSidecarStore.Write(roots, revisionTwo).Kind ==
              DefectSidecarWriteKind.SkippedNewer,
            "defect_sidecar_removed_revision_floor_blocks_late_write");
        Check(DefectSidecarStore.Read(roots, frameId).Error ==
              DefectSidecarError.NotFound,
            "defect_sidecar_remove_leaves_missing");

        DefectRecipeSnapshot revisionFour = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 4,
            sourceIdentity,
            items);
        Check(DefectSidecarStore.Write(roots, revisionFour).IsSuccess,
            "defect_sidecar_write_after_floor");
        string sidecarPath = DefectSidecarStore.PathFor(roots, frameId);
        JsonObject future = JsonNode.Parse(File.ReadAllBytes(sidecarPath))!.AsObject();
        future["version"] = 99;
        File.WriteAllBytes(sidecarPath, CatalogJson.SerializeCanonical(future));
        DefectSidecarReadResult unsupported = DefectSidecarStore.Read(roots, frameId);
        Check(unsupported.Error == DefectSidecarError.UnsupportedVersion &&
              unsupported.ObservedVersion == 99,
            "defect_sidecar_future_version_rejected");
        Check(DefectSidecarStore.Write(roots, revisionFour).Error ==
              DefectSidecarError.UnsupportedVersion,
            "defect_sidecar_future_version_not_overwritten");

        Guid invalidFrameId = Guid.Parse("2a35899b-f983-47d4-8047-57e99c5e2504");
        DefectEditItem invalidCompressed = items[2] with
        {
            Clusters =
            [
                items[2].Clusters![0] with
                {
                    Mask = new DefectMask(true, [1, 2, 3]),
                },
            ],
        };
        DefectRecipeSnapshot invalidZlib = DefectRecipeSnapshot.Create(
            invalidFrameId,
            recipeRevision: 1,
            sourceIdentity,
            [invalidCompressed]);
        Check(DefectSidecarStore.Write(roots, invalidZlib).Error ==
              DefectSidecarError.InvalidSnapshot,
            "defect_sidecar_invalid_zlib_rejected_before_publish");
    }

}
