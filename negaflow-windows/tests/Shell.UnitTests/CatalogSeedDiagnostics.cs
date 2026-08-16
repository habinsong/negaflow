using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class CatalogSeedDiagnostics
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length < 3 || args[0] != "--seed")
        {
            return false;
        }
        bool blackAndWhite = args[2] == "--bw";
        exitCode = SeedCatalog(args[1], args[(blackAndWhite ? 3 : 2)..], blackAndWhite);
        return true;
    }

    private static int SeedCatalog(
        string storageRoot,
        string[] sourcePaths,
        bool blackAndWhite = false)
    {
        StorageRootResolutionResult resolution = StorageRootResolver.ResolveForTests(storageRoot);
        if (resolution.Roots is not { } roots)
        {
            Console.Error.WriteLine($"storage root refused: {resolution.Error}");
            return 2;
        }
        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        if (opened.Session is not { } session)
        {
            Console.Error.WriteLine($"catalog refused: {opened.Error}");
            return 2;
        }
        using (session)
        {
            if (!session.ReadOrCreate().IsSuccess)
            {
                Console.Error.WriteLine("catalog create failed");
                return 2;
            }
            List<CatalogEntityRow> rows = [];
            for (int index = 0; index < sourcePaths.Length; ++index)
            {
                // 셸의 여러 경로가 frame id 를 GUID 로 해석합니다(썸네일 캐시 파일명, 결함
                // sidecar). 사람이 읽기 좋은 id 를 심으면 그 경로들이 조용히 멈춥니다.
                string id = Guid.NewGuid().ToString("D");
                JsonObject record = FrameRecord(id, "unused.tif", 0.0);
                if (blackAndWhite)
                {
                    record["filmType"] = "bwNegative";
                    record["params"]!.AsObject()["filmType"] = "bwNegative";
                }
                string full = Path.GetFullPath(sourcePaths[index]);
                record["rawScanPath"] = full;
                // 실제 파일의 크기·화소 수가 있어야 셸이 결함 편집을 좌표로 옮길 수 있습니다.
                if (TryProbe(full, out TiffSourceMetadata probed))
                {
                    record["sourceMetadata"] = new JsonObject
                    {
                        ["fileBytes"] = probed.FileBytes,
                        ["pixelWidth"] = probed.PixelWidth,
                        ["pixelHeight"] = probed.PixelHeight,
                        ["samplesPerPixel"] = probed.SamplesPerPixel,
                        ["bitsPerSample"] = probed.BitsPerSample,
                        ["sampleFormat"] = probed.SampleFormat,
                        ["orientation"] = probed.Orientation,
                    };
                }
                record["customDisplayName"] = Path.GetFileNameWithoutExtension(sourcePaths[index]);
                rows.Add(new CatalogEntityRow(id, record));
            }
            CatalogWriteResult written = session.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] = rows,
                }));
            if (!written.IsSuccess)
            {
                Console.Error.WriteLine($"catalog write failed: {written.Error}");
                return 2;
            }
            Console.WriteLine($"seeded {rows.Count} frames into {roots.CatalogPath}");
        }
        return 0;
    }

    /// <summary>
    /// 네이티브 엔진이 옆에 없으면 메타데이터 없이 심습니다. 씨앗은 검증 편의 도구이므로
    /// 그것 때문에 실패하지는 않게 합니다.
    /// </summary>
    private static bool TryProbe(string path, out TiffSourceMetadata metadata)
    {
        metadata = default;
        try
        {
            return NativeTiffSourceProbe.TryRead(path, out metadata);
        }
        catch (DllNotFoundException)
        {
            Console.Error.WriteLine("native engine missing; seeding without source metadata");
            return false;
        }
    }

    /// <summary>
    /// 단축키는 한 키에 한 명령이어야 합니다. 둘이 걸리면 하나는 영영 실행되지 않고, 사용자는
    /// 어느 쪽이 죽었는지 볼 방법이 없습니다.
    /// </summary>
}
