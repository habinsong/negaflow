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
    public static void Run(StorageRootSet roots)
    {
        VerifyDefectSidecarStore(roots);
        VerifyDefectCatalogTransaction(roots);
    }

    internal static void RunTransaction(StorageRootSet roots) =>
        VerifyDefectCatalogTransaction(roots);

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

    private static void VerifyDefectCatalogTransaction(StorageRootSet parentRoots)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-catalog-transaction")).Roots!;
        Guid frameId = Guid.Parse("dc881525-6db3-4ae8-b4dc-09947787919f");
        IReadOnlyList<DefectEditItem> items = DefectRecipeItems();
        DefectRecipeSnapshot revisionOne = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity: null,
            items);
        DefectRecipeSnapshot emptyRevisionOne = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity: null,
            items: []);
        DefectEditItem[] changedItems = [.. items];
        changedItems[0] = changedItems[0] with { Strength = 0.375 };
        DefectRecipeSnapshot revisionTwo = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 2,
            sourceIdentity: null,
            changedItems);
        changedItems[0] = changedItems[0] with { Strength = 0.625 };
        DefectRecipeSnapshot revisionFour = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 4,
            sourceIdentity: null,
            changedItems);
        string sidecarPath = DefectSidecarStore.PathFor(roots, frameId);

        CatalogWriteResult seeded = SqliteCatalogStore.Write(
            DefectCatalog(frameId, hasEdits: false, marker: 0),
            roots.CatalogPath);
        Check(seeded.IsSuccess,
            $"defect_transaction_catalog_seed_without_sidecar_{seeded.Error}");
        Check(CatalogRecovery.IsValidCatalogSource(roots.CatalogPath),
            "defect_transaction_catalog_seed_is_valid_recovery_source");
        using (CatalogSession session = CatalogSession.Open(roots).Session!)
        {
            Check(CatalogMarker(session.Read()) == 0,
                "defect_transaction_catalog_seed_readback");

            DefectSidecarWriteResult emptySidecar =
                session.WriteDefectRecipe(emptyRevisionOne);
            Check(!emptySidecar.IsSuccess &&
                  emptySidecar.Error == DefectSidecarError.InvalidSnapshot &&
                  DefectSidecarStore.Read(roots, frameId).Error ==
                      DefectSidecarError.NotFound,
                "defect_sidecar_store_rejects_empty_recipe_before_publish");

            DefectRecipeCatalogWriteResult emptyCommit =
                session.WriteDefectRecipeAndCatalog(
                    emptyRevisionOne,
                    DefectCatalog(frameId, hasEdits: true, marker: 0));
            Check(!emptyCommit.IsSuccess &&
                  emptyCommit.Sidecar.Error == DefectSidecarError.InvalidSnapshot &&
                  DefectSidecarStore.Read(roots, frameId).Error ==
                      DefectSidecarError.NotFound &&
                  CatalogHasDefectEdits(session.Read()) == false,
                "defect_transaction_rejects_empty_recipe_before_publish");

            DefectRecipeCatalogWriteResult absentRollback =
                session.WriteDefectRecipeAndCatalogForTesting(
                    revisionOne,
                    DefectCatalog(frameId, hasEdits: true, marker: 0),
                    writer: (_, _) => CatalogWriteResult.Failure(CatalogStoreError.IoFailure));
            Check(absentRollback.CatalogError == CatalogStoreError.IoFailure &&
                  DefectSidecarStore.Read(roots, frameId).Error == DefectSidecarError.NotFound &&
                  CatalogMarker(session.Read()) == 0,
                "defect_transaction_catalog_failure_restores_sidecar_absence");

            DefectRecipeCatalogWriteResult initialCommit =
                session.WriteDefectRecipeAndCatalog(
                    revisionOne,
                    DefectCatalog(frameId, hasEdits: true, marker: 0));
            Check(initialCommit.IsSuccess && File.Exists(sidecarPath),
                $"defect_transaction_initial_commit_{initialCommit.Sidecar.Error}_" +
                $"{initialCommit.CatalogError}_{initialCommit.Sidecar.Kind}");
            if (!initialCommit.IsSuccess || !File.Exists(sidecarPath))
            {
                return;
            }
            byte[] revisionOneBytes = File.ReadAllBytes(sidecarPath);

            DefectRecipeCatalogWriteResult byteRollback =
                DefectSidecarCatalogWriter.Write(
                    roots,
                    revisionTwo,
                    commitCatalog: () =>
                        CatalogWriteResult.Failure(CatalogStoreError.IoFailure));
            Check(byteRollback.CatalogError == CatalogStoreError.IoFailure &&
                  File.ReadAllBytes(sidecarPath).SequenceEqual(revisionOneBytes) &&
                  DefectSidecarStore.Read(roots, frameId).Snapshot?.RecipeRevision == 1 &&
                  CatalogMarker(session.Read()) == 0,
                "defect_transaction_catalog_failure_restores_exact_previous_sidecar");
        }

        using (CatalogSession reopened = CatalogSession.Open(roots).Session!)
        {
            Check(reopened.ReadOrCreate().IsSuccess &&
                  reopened.ReadDefectRecipe(frameId).Snapshot?.RecipeRevision == 1 &&
                  CatalogMarker(reopened.Read()) == 0,
                "defect_transaction_reopen_keeps_previous_recipe");
            Check(reopened.WriteDefectRecipeAndCatalog(
                    revisionTwo,
                    DefectCatalog(frameId, hasEdits: true, marker: 0)).IsSuccess &&
                  reopened.ReadDefectRecipe(frameId).Snapshot?.RecipeRevision == 2,
                "defect_transaction_rollback_restores_revision_floor");
            DefectRecipeCatalogWriteResult unsafeTarget =
                reopened.WriteDefectRecipeAndCatalog(
                    revisionTwo,
                    DefectCatalog(frameId, hasEdits: true, marker: 3));
            Check(!unsafeTarget.IsSuccess &&
                  unsafeTarget.CatalogError == CatalogStoreError.MissingAuthoritativeData &&
                  reopened.ReadDefectRecipe(frameId).Snapshot?.RecipeRevision == 2 &&
                  CatalogMarker(reopened.Read()) == 0,
                "defect_transaction_rejects_uncommitted_catalog_delta_before_sidecar");
            DefectRecipeCatalogWriteResult staleCommit =
                reopened.WriteDefectRecipeAndCatalog(
                    revisionOne,
                    DefectCatalog(frameId, hasEdits: true, marker: 0));
            Check(!staleCommit.IsSuccess &&
                  staleCommit.Sidecar.Error == DefectSidecarError.InvalidSnapshot &&
                  reopened.ReadDefectRecipe(frameId).Snapshot?.RecipeRevision == 2 &&
                  CatalogMarker(reopened.Read()) == 0,
                "defect_transaction_skipped_newer_does_not_commit_catalog");

            DefectRecipeCatalogDeleteResult gapDelete =
                reopened.DeleteDefectRecipeAndCatalog(
                    frameId,
                    deletionRevision: 4,
                    DefectCatalog(frameId, hasEdits: false, marker: 0));
            Check(!gapDelete.IsSuccess &&
                  gapDelete.SidecarError == DefectSidecarError.InvalidSnapshot &&
                  reopened.ReadDefectRecipe(frameId).Snapshot?.RecipeRevision == 2 &&
                  CatalogHasDefectEdits(reopened.Read()) == true,
                "defect_transaction_rejects_gap_delete_before_catalog_commit");

            DefectRecipeCatalogDeleteResult deleted =
                reopened.DeleteDefectRecipeAndCatalog(
                    frameId,
                    deletionRevision: 3,
                    DefectCatalog(frameId, hasEdits: false, marker: 0));
            Check(deleted.IsSuccess &&
                  reopened.ReadDefectRecipe(frameId).Error == DefectSidecarError.NotFound &&
                  CatalogHasDefectEdits(reopened.Read()) == false,
                $"defect_transaction_delete_commits_catalog_and_removes_sidecar_" +
                $"{deleted.SidecarError}_{deleted.CatalogError}");

            Check(reopened.WriteDefectRecipeAndCatalog(
                    revisionFour,
                    DefectCatalog(frameId, hasEdits: true, marker: 0)).IsSuccess &&
                  reopened.ReadDefectRecipe(frameId).Snapshot?.RecipeRevision == 4,
                "defect_transaction_next_revision_after_delete_succeeds");

            DefectRecipeCatalogDeleteResult lockedDelete;
            using (FileStream held = new(
                       sidecarPath,
                       FileMode.Open,
                       FileAccess.Read,
                       FileShare.Read))
            {
                lockedDelete = reopened.DeleteDefectRecipeAndCatalog(
                    frameId,
                    deletionRevision: 5,
                    DefectCatalog(frameId, hasEdits: false, marker: 0));
            }
            Check(!lockedDelete.IsSuccess &&
                  lockedDelete.SidecarError == DefectSidecarError.IoFailure &&
                  lockedDelete.CatalogError == CatalogStoreError.None &&
                  reopened.ReadDefectRecipe(frameId).Snapshot?.RecipeRevision == 4 &&
                  CatalogHasDefectEdits(reopened.Read()) == true,
                $"defect_transaction_delete_failure_restores_catalog_" +
                $"{lockedDelete.SidecarError}_{lockedDelete.CatalogError}");

            DefectRecipeCatalogDeleteResult retryDelete =
                reopened.DeleteDefectRecipeAndCatalog(
                    frameId,
                    deletionRevision: 5,
                    DefectCatalog(frameId, hasEdits: false, marker: 0));
            Check(retryDelete.IsSuccess &&
                  reopened.ReadDefectRecipe(frameId).Error == DefectSidecarError.NotFound &&
                  CatalogHasDefectEdits(reopened.Read()) == false,
                "defect_transaction_failed_delete_does_not_advance_revision_floor");
        }

        StorageRootSet recoveryRoots = StorageRootResolver.ResolveForTests(Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-catalog-rollback-failure")).Roots!;
        Check(SqliteCatalogStore.Write(
                DefectCatalog(frameId, hasEdits: false, marker: 0),
                recoveryRoots.CatalogPath).IsSuccess,
            "defect_transaction_recovery_catalog_seed");
        using (CatalogSession session = CatalogSession.Open(recoveryRoots).Session!)
        {
            DefectRecipeCatalogWriteResult rollbackFailure =
                session.WriteDefectRecipeAndCatalogForTesting(
                    revisionOne,
                    DefectCatalog(frameId, hasEdits: true, marker: 0),
                    writer: (_, _) => CatalogWriteResult.Failure(CatalogStoreError.IoFailure),
                    forceSidecarRollbackFailure: true);
            Check(rollbackFailure.CatalogError == CatalogStoreError.RollbackFailed &&
                  session.Write(DefectCatalog(frameId, hasEdits: false, marker: 0)).Error ==
                      CatalogStoreError.RollbackFailed,
                "defect_transaction_sidecar_rollback_failure_blocks_session");
        }

        CatalogSessionOpenResult recoveryOpen = CatalogSession.Open(recoveryRoots);
        using CatalogSession? recovery = recoveryOpen.Session;
        Check(!recoveryOpen.IsSuccess ||
              recovery?.ReadOrCreate().Error == CatalogStoreError.RollbackFailed,
            "defect_transaction_sidecar_rollback_failure_blocks_reopen");

        Guid aliasFrameId = Guid.Parse("abcdefab-cdef-4abc-8def-abcdefabcdef");
        DefectRecipeSnapshot aliasRecipe = DefectRecipeSnapshot.Create(
            aliasFrameId,
            1,
            revisionOne.SourceIdentity,
            revisionOne.Items);
        StorageRootSet aliasRoots = StorageRootResolver.ResolveForTests(Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-catalog-guid-alias")).Roots!;
        using (CatalogSession aliasSeed = CatalogSession.Open(aliasRoots).Session!)
        {
            Check(aliasSeed.ReadOrCreate().IsSuccess,
                "defect_orphan_alias_catalog_create");
            Check(aliasSeed.WriteDefectRecipe(aliasRecipe).IsSuccess,
                "defect_orphan_alias_sidecar_seed");
            JsonObject lowerPayload = new()
            {
                ["hasDefectEdits"] = false,
            };
            JsonObject upperPayload = new()
            {
                ["hasDefectEdits"] = true,
            };
            Check(aliasSeed.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] =
                    [
                        new(aliasFrameId.ToString("D"), lowerPayload),
                        new(aliasFrameId.ToString("D").ToUpperInvariant(), upperPayload),
                    ],
                })).IsSuccess, "defect_orphan_alias_catalog_seed");
        }
        string aliasSidecarPath = DefectSidecarStore.PathFor(aliasRoots, aliasFrameId);
        CatalogSessionOpenResult aliasOpen = CatalogSession.Open(aliasRoots);
        aliasOpen.Session?.Dispose();
        Check(!aliasOpen.IsSuccess &&
              aliasOpen.Error == CatalogSessionError.MissingAuthoritativeData &&
              aliasOpen.DefectSidecarError == DefectSidecarError.InvalidFrameId &&
              File.Exists(aliasSidecarPath),
            "defect_orphan_alias_fails_before_authoritative_sidecar_delete");

        Guid orphanFrameId = Guid.Parse("3ca0aecc-d727-4e62-ab37-d9c3c06d4a84");
        Guid missingFrameId = Guid.Parse("09cd48e7-28c2-4b15-98cb-e8a7dd7b5ecf");
        StorageRootSet mixedHealthRoots = StorageRootResolver.ResolveForTests(Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-catalog-mixed-health")).Roots!;
        DefectRecipeSnapshot orphanRecipe = DefectRecipeSnapshot.Create(
            orphanFrameId,
            1,
            revisionOne.SourceIdentity,
            revisionOne.Items);
        Check(DefectSidecarStore.Write(mixedHealthRoots, orphanRecipe).IsSuccess,
            "defect_orphan_mixed_health_sidecar_seed");
        JsonObject orphanPayload = new()
        {
            ["hasDefectEdits"] = false,
        };
        JsonObject missingPayload = new()
        {
            ["hasDefectEdits"] = true,
        };
        Check(SqliteCatalogStore.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] =
                    [
                        new(orphanFrameId.ToString("D"), orphanPayload),
                        new(missingFrameId.ToString("D"), missingPayload),
                    ],
                }), mixedHealthRoots.CatalogPath).IsSuccess,
            "defect_orphan_mixed_health_catalog_seed");
        string mixedOrphanPath = DefectSidecarStore.PathFor(mixedHealthRoots, orphanFrameId);
        CatalogSessionOpenResult mixedHealthOpen = CatalogSession.Open(mixedHealthRoots);
        mixedHealthOpen.Session?.Dispose();
        Check(!mixedHealthOpen.IsSuccess &&
              mixedHealthOpen.Error == CatalogSessionError.MissingAuthoritativeData &&
              mixedHealthOpen.DefectSidecarError == DefectSidecarError.NotFound &&
              File.Exists(mixedOrphanPath),
            "defect_orphan_authoritative_health_fails_before_cleanup");

        Guid markedFrameId = Guid.Parse("98308931-0756-41df-bdbf-93ef558b2c57");
        DefectRecipeSnapshot markedRecipe = DefectRecipeSnapshot.Create(
            markedFrameId,
            1,
            revisionOne.SourceIdentity,
            revisionOne.Items);
        StorageRootSet markerRoots = StorageRootResolver.ResolveForTests(Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-catalog-unresolved-marker")).Roots!;
        using (CatalogSession markerSeed = CatalogSession.Open(markerRoots).Session!)
        {
            Check(markerSeed.ReadOrCreate().IsSuccess &&
                  markerSeed.Write(DefectCatalog(markedFrameId, hasEdits: false, marker: 0))
                      .IsSuccess &&
                  markerSeed.WriteDefectRecipe(markedRecipe).IsSuccess,
                "defect_orphan_marker_seed");
        }
        string markedSidecarPath = DefectSidecarStore.PathFor(markerRoots, markedFrameId);
        File.WriteAllBytes($"{markerRoots.CatalogPath}.rollback-required", [1]);
        CatalogSessionOpenResult markerOpen = CatalogSession.Open(markerRoots);
        markerOpen.Session?.Dispose();
        Check(!markerOpen.IsSuccess &&
              markerOpen.Error == CatalogSessionError.MissingAuthoritativeData &&
              File.Exists(markedSidecarPath),
            "defect_orphan_marker_blocks_before_sidecar_cleanup");
    }

    private static CatalogSnapshot DefectCatalog(Guid frameId, bool hasEdits, int marker)
    {
        JsonObject payload = new()
        {
            ["hasDefectEdits"] = hasEdits,
            ["marker"] = marker,
        };
        return new CatalogSnapshot(
            null,
            new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
            {
                [CatalogEntityTable.Frames] =
                [new CatalogEntityRow(frameId.ToString("D"), payload)],
            });
    }

    private static int? CatalogMarker(CatalogReadResult read)
    {
        IReadOnlyList<CatalogEntityRow>? rows = read.Snapshot?.Rows(CatalogEntityTable.Frames);
        return rows?.Count == 1 &&
            rows[0].Payload["marker"] is JsonValue value &&
            value.TryGetValue(out int marker)
                ? marker
                : null;
    }

    private static bool? CatalogHasDefectEdits(CatalogReadResult read)
    {
        IReadOnlyList<CatalogEntityRow>? rows = read.Snapshot?.Rows(CatalogEntityTable.Frames);
        return rows?.Count == 1 &&
            rows[0].Payload["hasDefectEdits"] is JsonValue value &&
            value.TryGetValue(out bool hasEdits)
                ? hasEdits
                : null;
    }

}
