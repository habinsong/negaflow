using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

internal static class CatalogProcessLockTests
{
    internal const string LockContenderArgument = "--lock-contender";

    public static void Run() => VerifyCatalogProcessLock();

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


    internal static int RunLockContender(string isolatedBase)
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
    internal static string RunContenderProcess(string isolatedBase)
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

}
