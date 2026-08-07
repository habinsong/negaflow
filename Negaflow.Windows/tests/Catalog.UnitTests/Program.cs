using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;

namespace Negaflow.Catalog.UnitTests;

internal static class Program
{
    private static readonly List<string> Failures = [];
    private static int assertionCount;

    /// <summary>
    /// 이 인자로 실행되면 테스트가 아니라 lock 경쟁자로 동작합니다. 자기 자신을 다시 띄워
    /// **다른 프로세스**에서 세션을 열어 보게 하는 용도이며, 그래야 단일 작성자 계약이 프로세스
    /// 경계에서도 성립한다는 것이 추론이 아니라 관측이 됩니다.
    /// </summary>
    private const string LockContenderArgument = "--lock-contender";

    private static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == LockContenderArgument)
        {
            return RunLockContender(args[1]);
        }

        string fixturePath = Path.Combine(AppContext.BaseDirectory, "develop-route-v1.json");
        using JsonDocument fixture = JsonDocument.Parse(File.ReadAllBytes(fixturePath));

        VerifyValidFixtureCases(fixture.RootElement);
        VerifyInvalidFixtureCases(fixture.RootElement);
        VerifyReaderShapeErrors();
        VerifyRouteWriting(fixture.RootElement);
        VerifyAllFilmEmulationNames(fixture.RootElement);
        VerifyInvalidSelections(fixture.RootElement);
        VerifyCanonicalJson();
        VerifyStorageRootResolution();
        VerifyCatalogProcessLock();
        VerifySqliteCatalogStore();

        var report = new
        {
            status = Failures.Count == 0 ? "ok" : "failed",
            operation = "catalog_unit_tests",
            assertions = assertionCount,
            failures = Failures,
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return Failures.Count == 0 ? 0 : 1;
    }

    private static void VerifyValidFixtureCases(JsonElement root)
    {
        Check(root.GetProperty("schemaVersion").GetInt32() == 1, "fixture_schema_version");

        foreach (JsonElement testCase in root.GetProperty("validCases").EnumerateArray())
        {
            string id = testCase.GetProperty("id").GetString() ?? "missing-id";
            DevelopRouteReadResult result = DevelopRouteReader.Read(
                testCase.GetProperty("frame"));
            Check(result.IsSuccess, $"{id}_read_success");
            if (result.Route is not { } route)
            {
                continue;
            }

            JsonElement expected = testCase.GetProperty("expected");
            Check(SourceTransportName(route.SourceTransport) ==
                expected.GetProperty("sourceTransport").GetString(), $"{id}_transport");
            Check(SourceSignalName(route.SourceSignalKind) ==
                expected.GetProperty("sourceSignalKind").GetString(), $"{id}_signal");
            Check(ProcessName(route.DevelopmentProcess) ==
                expected.GetProperty("developmentProcess").GetString(), $"{id}_process");
            Check(FilmLookSourceName(route.FilmLookSource) ==
                expected.GetProperty("filmLookSource").GetString(), $"{id}_look_source");
            Check(FilmEmulationName(route.FilmEmulation) ==
                expected.GetProperty("filmEmulation").GetString(), $"{id}_emulation");
            Check(Math.Abs(route.FilmEmulationIntensity -
                expected.GetProperty("filmEmulationIntensity").GetDouble()) < 1e-12,
                $"{id}_intensity");
            Check(route.UsedLegacySourceSignal ==
                expected.GetProperty("usedLegacySourceSignal").GetBoolean(),
                $"{id}_legacy_signal");
            Check(route.UsedLegacyIntensityDefault ==
                expected.GetProperty("usedLegacyIntensityDefault").GetBoolean(),
                $"{id}_legacy_intensity");
            Check(route.IsDigitalSource ==
                (route.SourceSignalKind == SourceSignalKind.RenderedDigital),
                $"{id}_digital_derived");
        }
    }

    private static void VerifyInvalidFixtureCases(JsonElement root)
    {
        foreach (JsonElement testCase in root.GetProperty("invalidCases").EnumerateArray())
        {
            string id = testCase.GetProperty("id").GetString() ?? "missing-id";
            DevelopRouteReadResult result = DevelopRouteReader.Read(
                testCase.GetProperty("frame"));
            Check(!result.IsSuccess, $"{id}_read_rejected");
            Check(ErrorName(result.Error) == testCase.GetProperty("expectedError").GetString(),
                $"{id}_error");
            Check(result.Route is null, $"{id}_no_partial_route");
        }
    }

    private static void VerifyRouteWriting(JsonElement root)
    {
        JsonElement legacyFrame = root.GetProperty("validCases")[0].GetProperty("frame");
        JsonObject original = JsonNode.Parse(legacyFrame.GetRawText())!.AsObject();
        DevelopRouteSelection digitalSelection = DevelopRouteSelection.FromProcess(
            DevelopmentProcess.DigitalColor,
            FilmEmulation.Portra400);

        Check(digitalSelection.FilmEmulationIntensity == 0.5, "new_recipe_intensity_half");
        DevelopRouteWriteResult write = DevelopRouteWriter.Apply(original, digitalSelection);
        Check(write.IsSuccess, "write_digital_success");
        if (write.FrameRecord is not { } digitalFrame)
        {
            return;
        }

        Check(original["sourceSignalKind"] is null, "write_original_unchanged");
        Check(digitalFrame["sourceKind"]!.GetValue<string>() == "imported",
            "write_preserves_transport");
        Check(digitalFrame["futureFrameValue"]!.GetValue<string>() == "preserve-me",
            "write_preserves_unknown_frame_field");
        JsonObject digitalParameters = digitalFrame["params"]!.AsObject();
        Check(digitalParameters["unknownAdjustment"]!["value"]!.GetValue<int>() == 7,
            "write_preserves_unknown_parameter_field");
        Check(digitalParameters["isDigitalSource"]!.GetValue<bool>(),
            "write_sets_legacy_digital_marker");

        DevelopRouteReadResult digitalRead = ReadNode(digitalFrame);
        Check(digitalRead.IsSuccess, "write_digital_round_trip");
        Check(digitalRead.Route?.DevelopmentProcess == DevelopmentProcess.DigitalColor,
            "write_digital_process");
        Check(digitalRead.Route?.SourceTransport == FrameSourceTransport.Imported,
            "import_transport_does_not_override_signal");

        DevelopRouteWriteResult filmWrite = DevelopRouteWriter.Apply(
            digitalFrame,
            DevelopRouteSelection.FromProcess(
                DevelopmentProcess.E6,
                FilmEmulation.Velvia50,
                0.35));
        Check(filmWrite.IsSuccess, "write_film_success");
        if (filmWrite.FrameRecord is not { } filmFrame)
        {
            return;
        }
        Check(!filmFrame["params"]!.AsObject().ContainsKey("isDigitalSource"),
            "write_film_omits_false_marker");
        DevelopRouteReadResult filmRead = ReadNode(filmFrame);
        Check(filmRead.IsSuccess, "write_film_round_trip");
        Check(filmRead.Route?.SourceSignalKind == SourceSignalKind.FilmPositiveScan,
            "write_film_explicit_signal");
        Check(filmRead.Route?.UsedLegacySourceSignal == false,
            "write_film_not_legacy_signal");
    }

    private static void VerifyReaderShapeErrors()
    {
        using JsonDocument array = JsonDocument.Parse("[]");
        DevelopRouteReadResult result = DevelopRouteReader.Read(array.RootElement);
        Check(result.Error == DevelopRouteError.FrameRecordNotObject,
            "reader_rejects_non_object");
        Check(result.Route is null, "reader_non_object_no_partial_route");
    }

    private static void VerifyAllFilmEmulationNames(JsonElement root)
    {
        JsonObject frame = JsonNode.Parse(
            root.GetProperty("validCases")[1].GetProperty("frame").GetRawText())!.AsObject();
        foreach (FilmEmulation emulation in Enum.GetValues<FilmEmulation>())
        {
            DevelopRouteWriteResult write = DevelopRouteWriter.Apply(
                frame,
                DevelopRouteSelection.FromProcess(DevelopmentProcess.D76, emulation));
            Check(write.IsSuccess, $"emulation_{emulation}_write");
            if (write.FrameRecord is not { } written)
            {
                continue;
            }
            DevelopRouteReadResult read = ReadNode(written);
            Check(read.Route?.FilmEmulation == emulation, $"emulation_{emulation}_round_trip");
            Check(read.Route?.SourceTransport == FrameSourceTransport.Imported,
                $"emulation_{emulation}_transport_independent");
        }
    }

    private static void VerifyInvalidSelections(JsonElement root)
    {
        JsonObject frame = JsonNode.Parse(
            root.GetProperty("validCases")[0].GetProperty("frame").GetRawText())!.AsObject();
        DevelopRouteWriteResult mismatched = DevelopRouteWriter.Apply(
            frame,
            new DevelopRouteSelection(
                SourceSignalKind.RenderedDigital,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5));
        Check(mismatched.Error == DevelopRouteError.SourceSignalFilmTypeMismatch,
            "invalid_selection_signal_type");
        Check(mismatched.FrameRecord is null, "invalid_selection_no_partial_record");
        Check(frame["sourceSignalKind"] is null, "invalid_selection_input_unchanged");

        DevelopRouteWriteResult nonfinite = DevelopRouteWriter.Apply(
            frame,
            new DevelopRouteSelection(
                SourceSignalKind.FilmPositiveScan,
                FilmType.ColorPositive,
                FilmEmulation.None,
                double.NaN));
        Check(nonfinite.Error == DevelopRouteError.InvalidFilmEmulationIntensity,
            "invalid_selection_nonfinite");

        JsonObject missingTransport = new()
        {
            ["params"] = new JsonObject(),
        };
        DevelopRouteWriteResult missingTransportWrite = DevelopRouteWriter.Apply(
            missingTransport,
            DevelopRouteSelection.FromProcess(DevelopmentProcess.C41));
        Check(missingTransportWrite.Error == DevelopRouteError.MissingSourceTransport,
            "writer_requires_transport");

        JsonObject invalidParameters = new()
        {
            ["sourceKind"] = "scanner",
            ["params"] = new JsonArray(),
        };
        DevelopRouteWriteResult invalidParametersWrite = DevelopRouteWriter.Apply(
            invalidParameters,
            DevelopRouteSelection.FromProcess(DevelopmentProcess.C41));
        Check(invalidParametersWrite.Error == DevelopRouteError.ParametersNotObject,
            "writer_rejects_non_object_parameters");
    }

    private static void VerifyCanonicalJson()
    {
        JsonNode first = JsonNode.Parse(
            """{"z":0,"a":{"b":2,"a":1},"list":[{"z":3,"a":2}]}""")!;
        JsonNode second = JsonNode.Parse(
            """{"list":[{"a":2,"z":3}],"a":{"a":1,"b":2},"z":0}""")!;
        byte[] firstBytes = CatalogJson.SerializeCanonical(first);
        byte[] secondBytes = CatalogJson.SerializeCanonical(second);
        const string expected = "{\"a\":{\"a\":1,\"b\":2},\"list\":[{\"a\":2,\"z\":3}],\"z\":0}";

        Check(firstBytes.SequenceEqual(secondBytes), "canonical_order_independent");
        Check(Encoding.UTF8.GetString(firstBytes) == expected, "canonical_expected_bytes");
    }

    private static void VerifyStorageRootResolution()
    {
        StorageRootResolutionResult missing = StorageRootResolver.ResolveForTests(string.Empty);
        Check(missing.Error == StorageRootResolutionError.MissingBaseRoot,
            "storage_root_rejects_empty");
        Check(missing.Roots is null, "storage_root_empty_no_partial_result");

        StorageRootResolutionResult relative = StorageRootResolver.ResolveForTests("relative");
        Check(relative.Error == StorageRootResolutionError.BaseRootNotFullyQualified,
            "storage_root_rejects_relative");

        string isolatedBase = Path.Combine(
            AppContext.BaseDirectory,
            "storage-root-tests",
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootResolutionResult resolution = StorageRootResolver.ResolveForTests(isolatedBase);
        Check(resolution.IsSuccess, "storage_root_test_resolution_success");
        if (resolution.Roots is not { } roots)
        {
            return;
        }

        string expectedProductRoot = Path.Combine(
            Path.GetFullPath(isolatedBase),
            "Negaflow");
        Check(roots.IsTestIsolated, "storage_root_marks_test_isolation");
        Check(roots.ProductDataRoot == expectedProductRoot, "storage_root_product_path");
        Check(roots.LibraryRoot == Path.Combine(expectedProductRoot, "Library"),
            "storage_root_library_path");
        Check(roots.CatalogPath == Path.Combine(roots.LibraryRoot, "library.sqlite"),
            "storage_root_catalog_path");
        Check(roots.CatalogBackupPath ==
            Path.Combine(roots.LibraryRoot, "library.backup.sqlite"),
            "storage_root_catalog_backup_path");
        Check(roots.CatalogLockPath ==
            Path.Combine(roots.LibraryRoot, "library.sqlite.lock"),
            "storage_root_catalog_lock_path");
        Check(roots.DefectRecipeRoot == Path.Combine(roots.LibraryRoot, "defects"),
            "storage_root_defects_path");
        Check(roots.BackupRoot == Path.Combine(roots.LibraryRoot, "Backups"),
            "storage_root_backups_path");
        Check(roots.PendingRestoreRoot == Path.Combine(roots.LibraryRoot, "PendingRestore"),
            "storage_root_pending_restore_path");
        Check(roots.MigrationRoot == Path.Combine(roots.LibraryRoot, "Migration"),
            "storage_root_migration_path");
        Check(roots.CacheRoot == Path.Combine(expectedProductRoot, "Cache"),
            "storage_root_cache_path");
        Check(roots.JournalRoot == Path.Combine(expectedProductRoot, "Journals"),
            "storage_root_journal_path");
        Check(roots.PluginRoot == Path.Combine(expectedProductRoot, "Plugins"),
            "storage_root_plugin_path");
        Check(roots.LogRoot == Path.Combine(expectedProductRoot, "Logs"),
            "storage_root_log_path");
        Check(roots.SettingsRoot == Path.Combine(expectedProductRoot, "Settings"),
            "storage_root_settings_path");
        Check(StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            roots.CatalogPath), "storage_path_catalog_contained");
        Check(StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            roots.ProductDataRoot), "storage_path_root_contains_itself");
        Check(!StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            $"{roots.ProductDataRoot}-outside"), "storage_path_rejects_prefix_sibling");

        Check(StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("Library", "library.sqlite"),
            out string resolvedCatalog), "storage_path_resolves_relative");
        Check(resolvedCatalog == roots.CatalogPath, "storage_path_relative_value");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("..", "outside"),
            out _), "storage_path_rejects_parent_escape");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            roots.CatalogPath,
            out _), "storage_path_rejects_rooted_input");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("Library", ".", "library.sqlite"),
            out _), "storage_path_rejects_dot_component");
    }

    private static void VerifyCatalogProcessLock()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "storage-lock-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        CatalogProcessLock? firstLock = null;
        CatalogProcessLock? reacquiredLock = null;

        try
        {
            Check(!Directory.Exists(roots.ProductDataRoot), "catalog_lock_root_initially_absent");
            CatalogProcessLockAcquireResult first = CatalogProcessLock.TryAcquire(roots);
            firstLock = first.Lock;
            Check(first.IsSuccess, "catalog_lock_first_acquire");
            Check(firstLock?.IsHeld == true, "catalog_lock_first_held");
            Check(Directory.Exists(roots.LibraryRoot), "catalog_lock_creates_library_root");
            Check(File.Exists(roots.CatalogLockPath), "catalog_lock_file_exists");
            Check(!File.Exists(roots.CatalogPath), "catalog_lock_does_not_create_catalog");
            Check(!Directory.Exists(roots.CacheRoot), "catalog_lock_does_not_create_cache");

            CatalogProcessLockAcquireResult second = CatalogProcessLock.TryAcquire(roots);
            Check(!second.IsSuccess, "catalog_lock_second_rejected");
            Check(second.Error == CatalogProcessLockError.Busy, "catalog_lock_second_busy");
            Check(second.Lock is null, "catalog_lock_busy_no_partial_handle");

            firstLock?.Dispose();
            Check(firstLock?.IsHeld == false, "catalog_lock_dispose_releases_handle");
            Check(File.Exists(roots.CatalogLockPath), "catalog_lock_stale_file_is_not_owner");

            CatalogProcessLockAcquireResult reacquired = CatalogProcessLock.TryAcquire(roots);
            reacquiredLock = reacquired.Lock;
            Check(reacquired.IsSuccess, "catalog_lock_reacquire_after_dispose");
            Check(reacquiredLock?.IsHeld == true, "catalog_lock_reacquired_held");
            reacquiredLock?.Dispose();
            reacquiredLock?.Dispose();
            Check(reacquiredLock?.IsHeld == false, "catalog_lock_dispose_idempotent");
        }
        finally
        {
            reacquiredLock?.Dispose();
            firstLock?.Dispose();
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static void VerifySqliteCatalogStore()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "catalog-store-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        try
        {
            VerifyStoreLifecycle(roots);
            VerifyStoreRefusals(roots);
            VerifyCatalogSession(roots);
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static void VerifyStoreLifecycle(StorageRootSet roots)
    {
        string catalogPath = roots.CatalogPath;

        // 없는 파일을 빈 라이브러리로 읽지 않습니다.
        CatalogReadResult absent = SqliteCatalogStore.Read(catalogPath);
        Check(!absent.IsSuccess, "store_absent_not_success");
        Check(absent.Error == CatalogStoreError.NotFound, "store_absent_not_found");
        Check(absent.Snapshot is null, "store_absent_no_partial_snapshot");

        CatalogSnapshot first = Snapshot(
            "roll-a",
            Row("frame-1", "one"),
            Row("frame-2", "two"),
            Row("frame-3", "three"));
        Check(SqliteCatalogStore.Write(first, catalogPath).IsSuccess, "store_first_write");
        Check(File.Exists(catalogPath), "store_first_write_creates_file");

        CatalogReadResult reopened = SqliteCatalogStore.Read(catalogPath);
        Check(reopened.IsSuccess, "store_reopen_success");
        Check(FrameOrder(reopened) == "frame-1,frame-2,frame-3", "store_reopen_preserves_order");
        Check(FrameLabels(reopened) == "one,two,three", "store_reopen_preserves_payload");
        Check(reopened.Snapshot?.ActiveRollId == "roll-a", "store_reopen_preserves_active_roll");
        Check(reopened.Snapshot?.Rows(CatalogEntityTable.Rolls).Count == 0,
            "store_reopen_untouched_table_empty");

        // 자리 바꾸기입니다. position 이 UNIQUE 이므로 재배치 중 제약을 어기면 여기서 걸립니다.
        CatalogSnapshot reordered = Snapshot(
            "roll-a",
            Row("frame-3", "three"),
            Row("frame-1", "one-edited"),
            Row("frame-2", "two"));
        Check(SqliteCatalogStore.Write(reordered, catalogPath).IsSuccess, "store_reorder_write");
        CatalogReadResult afterReorder = SqliteCatalogStore.Read(catalogPath);
        Check(FrameOrder(afterReorder) == "frame-3,frame-1,frame-2", "store_reorder_order");
        Check(FrameLabels(afterReorder) == "three,one-edited,two", "store_reorder_payload");

        // 되돌리기도 같은 경로를 반대 방향으로 지납니다.
        Check(SqliteCatalogStore.Write(first, catalogPath).IsSuccess, "store_reorder_back_write");
        Check(FrameOrder(SqliteCatalogStore.Read(catalogPath)) == "frame-1,frame-2,frame-3",
            "store_reorder_back_order");

        CatalogSnapshot removed = Snapshot("roll-a", Row("frame-2", "two"));
        Check(SqliteCatalogStore.Write(removed, catalogPath).IsSuccess, "store_remove_write");
        CatalogReadResult afterRemove = SqliteCatalogStore.Read(catalogPath);
        Check(FrameOrder(afterRemove) == "frame-2", "store_remove_drops_rows");

        CatalogSnapshot cleared = Snapshot(activeRollId: null);
        Check(SqliteCatalogStore.Write(cleared, catalogPath).IsSuccess, "store_clear_write");
        CatalogReadResult afterClear = SqliteCatalogStore.Read(catalogPath);
        Check(afterClear.IsSuccess, "store_clear_reopen_success");
        Check(afterClear.Snapshot?.Rows(CatalogEntityTable.Frames).Count == 0,
            "store_clear_empties_table");
        Check(afterClear.Snapshot?.ActiveRollId is null, "store_clear_active_roll_null");

        Check(CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_valid_recovery_source");

        // Pooling 을 켜 두면 여기서 파일이 잠겨 backup 교체가 막힙니다.
        File.Delete(catalogPath);
        Check(!File.Exists(catalogPath), "store_no_lingering_file_handle");
    }

    private static void VerifyStoreRefusals(StorageRootSet roots)
    {
        string catalogPath = Path.Combine(roots.LibraryRoot, "refusals.sqlite");

        CatalogSnapshot duplicated = Snapshot(
            null,
            Row("frame-1", "one"),
            Row("frame-1", "again"));
        CatalogWriteResult duplicateWrite = SqliteCatalogStore.Write(duplicated, catalogPath);
        Check(duplicateWrite.Error == CatalogStoreError.InvalidSnapshot,
            "store_rejects_duplicate_ids");
        Check(!File.Exists(catalogPath), "store_rejects_duplicate_ids_without_creating_file");

        CatalogSnapshot emptyId = Snapshot(null, Row(string.Empty, "one"));
        Check(SqliteCatalogStore.Write(emptyId, catalogPath).Error ==
            CatalogStoreError.InvalidSnapshot, "store_rejects_empty_id");

        Check(SqliteCatalogStore.Write(Snapshot(null, Row("frame-1", "one")), catalogPath)
            .IsSuccess, "store_refusal_fixture_write");

        // 물리 schema 가 미래 버전이면 읽지 않습니다.
        SetStorageVersion(catalogPath, 99);
        CatalogReadResult futureStorage = SqliteCatalogStore.Read(catalogPath);
        Check(futureStorage.Error == CatalogStoreError.UnsupportedStorageVersion,
            "store_rejects_future_storage_version");
        Check(futureStorage.ObservedVersion == 99, "store_reports_observed_storage_version");
        Check(!CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_future_storage_is_not_recovery_source");
        Check(SqliteCatalogStore.Write(Snapshot(null), catalogPath).Error ==
            CatalogStoreError.UnsupportedStorageVersion,
            "store_refuses_write_over_future_storage_version");
        SetStorageVersion(catalogPath, 1);

        // macOS 파일은 논리 version 6 입니다. 조용히 읽지 않고 그 값을 보고합니다.
        SetCatalogVersion(catalogPath, 6);
        CatalogReadResult foreign = SqliteCatalogStore.Read(catalogPath);
        Check(foreign.Error == CatalogStoreError.UnsupportedCatalogVersion,
            "store_rejects_foreign_catalog_version");
        Check(foreign.ObservedVersion == 6, "store_reports_observed_catalog_version");
        Check(!CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_foreign_catalog_is_not_recovery_source");
        SetCatalogVersion(catalogPath, CatalogSnapshot.CurrentCatalogVersion);
        Check(SqliteCatalogStore.Read(catalogPath).IsSuccess, "store_restored_fixture_reads");

        string garbagePath = Path.Combine(roots.LibraryRoot, "garbage.sqlite");
        File.WriteAllBytes(garbagePath, "this is not a database"u8.ToArray());
        CatalogReadResult garbage = SqliteCatalogStore.Read(garbagePath);
        Check(garbage.Error == CatalogStoreError.CorruptDatabase, "store_rejects_garbage_file");
        Check(garbage.Snapshot is null, "store_garbage_no_partial_snapshot");
        Check(!CatalogRecovery.IsValidCatalogSource(garbagePath),
            "store_garbage_is_not_recovery_source");
        Check(SqliteCatalogStore.Write(Snapshot(null), garbagePath).Error !=
            CatalogStoreError.None, "store_refuses_write_over_garbage_file");

        Check(SqliteCatalogStore.Read("library.sqlite").Error == CatalogStoreError.InvalidPath,
            "store_rejects_relative_path");
        Check(SqliteCatalogStore.Write(Snapshot(null), "library.sqlite").Error ==
            CatalogStoreError.InvalidPath, "store_write_rejects_relative_path");
    }

    private static int RunLockContender(string isolatedBase)
    {
        StorageRootResolutionResult resolution =
            StorageRootResolver.ResolveForTests(isolatedBase);
        if (resolution.Roots is not { } contenderRoots)
        {
            Console.WriteLine("resolve-failed");
            return 2;
        }

        CatalogSessionOpenResult opened = CatalogSession.Open(contenderRoots);
        if (opened.Session is { } session)
        {
            session.Dispose();
            Console.WriteLine("acquired");
            return 0;
        }
        Console.WriteLine(opened.Error.ToString());
        return 1;
    }

    /// <summary>
    /// 같은 실행 파일을 별도 프로세스로 띄워 lock 을 잡아 보게 합니다. 결과 문자열을 돌려줍니다.
    /// </summary>
    private static string RunContenderProcess(string isolatedBase)
    {
        string executablePath = Environment.ProcessPath ?? string.Empty;
        ProcessStartInfo startInfo = new()
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        // apphost 로 빌드되면 exe 를 바로 띄우고, dotnet 호스트로 실행 중이면 dll 을 넘깁니다.
        string assemblyPath = Path.Combine(
            AppContext.BaseDirectory,
            "Negaflow.Catalog.UnitTests.dll");
        if (Path.GetFileNameWithoutExtension(executablePath) == "dotnet")
        {
            startInfo.FileName = executablePath;
            startInfo.ArgumentList.Add(assemblyPath);
        }
        else
        {
            startInfo.FileName = executablePath;
        }
        startInfo.ArgumentList.Add(LockContenderArgument);
        startInfo.ArgumentList.Add(isolatedBase);

        using Process? contender = Process.Start(startInfo);
        if (contender is null)
        {
            return "start-failed";
        }
        string output = contender.StandardOutput.ReadToEnd().Trim();
        contender.WaitForExit(30_000);
        return output;
    }

    private static void VerifyCatalogSession(StorageRootSet roots)
    {
        string sessionBase = Path.Combine(
            Path.GetDirectoryName(roots.LocalApplicationDataRoot)!,
            $"session-{Guid.NewGuid():N}");
        StorageRootSet sessionRoots = StorageRootResolver.ResolveForTests(sessionBase).Roots!;
        CatalogSession? session = null;

        try
        {
            CatalogSessionOpenResult opened = CatalogSession.Open(sessionRoots);
            session = opened.Session;
            Check(opened.IsSuccess, "session_open");
            Check(session?.IsOpen == true, "session_open_is_open");
            Check(File.Exists(sessionRoots.CatalogLockPath), "session_holds_lock");
            Check(!File.Exists(sessionRoots.CatalogPath), "session_open_does_not_create_catalog");

            // 두 번째 작성자는 lock 에서 막힙니다. 세션 없이는 store 에 닿을 방법이 없습니다.
            CatalogSessionOpenResult second = CatalogSession.Open(sessionRoots);
            Check(!second.IsSuccess, "session_second_rejected");
            Check(second.Error == CatalogSessionError.Busy, "session_second_busy");
            Check(second.Session is null, "session_busy_no_partial_session");

            // 프로세스 경계에서도 같아야 합니다. 같은 프로세스 안의 거부만 보면 FileShare.None 이
            // 실제로 무엇을 막는지는 추론으로 남습니다.
            Check(RunContenderProcess(sessionBase) == "Busy", "session_other_process_busy");

            Check(session!.Read().Error == CatalogStoreError.NotFound,
                "session_read_absent_is_not_found");

            CatalogReadResult created = session.ReadOrCreate();
            Check(created.IsSuccess, "session_read_or_create_success");
            Check(created.Snapshot?.Rows(CatalogEntityTable.Frames).Count == 0,
                "session_read_or_create_is_empty");
            Check(File.Exists(sessionRoots.CatalogPath), "session_read_or_create_creates_file");

            Check(session.Write(Snapshot("roll-s", Row("frame-1", "one"))).IsSuccess,
                "session_write");
            Check(FrameOrder(session.Read()) == "frame-1", "session_write_round_trip");

            // 이미 있는 카탈로그에서는 ReadOrCreate 가 덮지 않습니다.
            CatalogReadResult reopened = session.ReadOrCreate();
            Check(FrameOrder(reopened) == "frame-1", "session_read_or_create_preserves_existing");

            // 손상은 ReadOrCreate 에서도 빈 라이브러리가 되지 않습니다.
            session.Dispose();
            File.WriteAllBytes(sessionRoots.CatalogPath, "not a database"u8.ToArray());
            CatalogSessionOpenResult reopenedSession = CatalogSession.Open(sessionRoots);
            session = reopenedSession.Session;
            Check(reopenedSession.IsSuccess, "session_reopen_after_dispose");
            Check(session!.ReadOrCreate().Error == CatalogStoreError.CorruptDatabase,
                "session_read_or_create_refuses_corrupt");

            session.Dispose();
            Check(session.IsOpen == false, "session_dispose_releases_lock");
            bool threw = false;
            try
            {
                session.Read();
            }
            catch (ObjectDisposedException)
            {
                threw = true;
            }
            Check(threw, "session_read_after_dispose_throws");

            CatalogSessionOpenResult third = CatalogSession.Open(sessionRoots);
            Check(third.IsSuccess, "session_reacquire_after_dispose");
            third.Session?.Dispose();

            // lock 이 풀린 뒤에는 다른 프로세스가 잡을 수 있어야 합니다. 위의 Busy 가 경로 오류나
            // 프로세스 기동 실패를 잘못 읽은 것이 아님을 이것이 확인합니다.
            Check(RunContenderProcess(sessionBase) == "acquired",
                "session_other_process_acquires_when_free");
        }
        finally
        {
            session?.Dispose();
            if (Directory.Exists(sessionBase))
            {
                Directory.Delete(sessionBase, recursive: true);
            }
        }
    }

    private static void SetStorageVersion(string catalogPath, int version) =>
        ExecuteFixtureSql(catalogPath, $"PRAGMA user_version={version}");

    private static void SetCatalogVersion(string catalogPath, int version) =>
        ExecuteFixtureSql(
            catalogPath,
            $"UPDATE catalog_metadata SET catalog_version={version} WHERE singleton=1");

    private static void ExecuteFixtureSql(string catalogPath, string sql)
    {
        SqliteConnectionStringBuilder builder = new()
        {
            DataSource = catalogPath,
            Mode = SqliteOpenMode.ReadWrite,
            Pooling = false,
        };
        using SqliteConnection connection = new(builder.ConnectionString);
        connection.Open();
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static CatalogEntityRow Row(string id, string label) =>
        new(id, new JsonObject { ["label"] = label });

    private static CatalogSnapshot Snapshot(
        string? activeRollId,
        params CatalogEntityRow[] frames) =>
        new(activeRollId, new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] = frames,
        });

    private static string FrameOrder(CatalogReadResult result) =>
        result.Snapshot is null
            ? "<none>"
            : string.Join(',', result.Snapshot.Rows(CatalogEntityTable.Frames)
                .Select(row => row.Id));

    private static string FrameLabels(CatalogReadResult result) =>
        result.Snapshot is null
            ? "<none>"
            : string.Join(',', result.Snapshot.Rows(CatalogEntityTable.Frames)
                .Select(row => row.Payload["label"]!.GetValue<string>()));

    private static DevelopRouteReadResult ReadNode(JsonObject frameRecord)
    {
        byte[] bytes = CatalogJson.SerializeCanonical(frameRecord);
        using JsonDocument document = JsonDocument.Parse(bytes);
        return DevelopRouteReader.Read(document.RootElement);
    }

    private static string SourceTransportName(FrameSourceTransport value) => value switch
    {
        FrameSourceTransport.Scanner => "scanner",
        FrameSourceTransport.Imported => "imported",
        _ => "invalid",
    };

    private static string SourceSignalName(SourceSignalKind value) => value switch
    {
        SourceSignalKind.FilmNegativeScan => "filmNegativeScan",
        SourceSignalKind.FilmPositiveScan => "filmPositiveScan",
        SourceSignalKind.RenderedDigital => "renderedDigital",
        SourceSignalKind.SceneLinearDigital => "sceneLinearDigital",
        SourceSignalKind.Unknown => "unknown",
        _ => "invalid",
    };

    private static string ProcessName(DevelopmentProcess value) => value switch
    {
        DevelopmentProcess.C41 => "c41",
        DevelopmentProcess.E6 => "e6",
        DevelopmentProcess.D76 => "d76",
        DevelopmentProcess.BlackAndWhiteReversal => "bwReversal",
        DevelopmentProcess.DigitalColor => "digitalColor",
        DevelopmentProcess.DigitalBlackAndWhite => "digitalBW",
        _ => "invalid",
    };

    private static string FilmLookSourceName(FilmLookSource value) => value switch
    {
        FilmLookSource.FilmScan => "filmScan",
        FilmLookSource.RenderedDigital => "renderedDigital",
        _ => "invalid",
    };

    private static string FilmEmulationName(FilmEmulation value) => value switch
    {
        FilmEmulation.None => "none",
        FilmEmulation.EktachromeE100 => "ektachromeE100",
        FilmEmulation.Provia100F => "provia100F",
        FilmEmulation.Velvia50 => "velvia50",
        FilmEmulation.Portra160 => "portra160",
        FilmEmulation.Portra400 => "portra400",
        FilmEmulation.Portra800 => "portra800",
        FilmEmulation.Ektar100 => "ektar100",
        FilmEmulation.Ultramax400 => "ultramax400",
        FilmEmulation.ColorPlus200 => "colorPlus200",
        FilmEmulation.FujicolorC200 => "fujicolorC200",
        FilmEmulation.Pro400H => "pro400H",
        _ => "invalid",
    };

    private static string ErrorName(DevelopRouteError value) => value switch
    {
        DevelopRouteError.MissingSourceTransport => "missingSourceTransport",
        DevelopRouteError.InvalidSourceTransport => "invalidSourceTransport",
        DevelopRouteError.MissingFilmType => "missingFilmType",
        DevelopRouteError.MissingParameters => "missingParameters",
        DevelopRouteError.ParametersNotObject => "parametersNotObject",
        DevelopRouteError.MismatchedFilmType => "mismatchedFilmType",
        DevelopRouteError.InvalidDigitalSourceMarker => "invalidDigitalSourceMarker",
        DevelopRouteError.InvalidSourceSignal => "invalidSourceSignal",
        DevelopRouteError.UnsupportedSourceSignal => "unsupportedSourceSignal",
        DevelopRouteError.SourceSignalMarkerMismatch => "sourceSignalMarkerMismatch",
        DevelopRouteError.SourceSignalFilmTypeMismatch => "sourceSignalFilmTypeMismatch",
        DevelopRouteError.InvalidFilmEmulation => "invalidFilmEmulation",
        DevelopRouteError.InvalidFilmEmulationIntensity => "invalidFilmEmulationIntensity",
        _ => value.ToString(),
    };

    private static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }
}
