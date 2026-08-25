using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

internal static class DefectSourceIdentityTests
{
    internal static void Run()
    {
        string parent = Path.Combine(Path.GetTempPath(), "negaflow-defect-source-identity-tests");
        string isolated = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        string source = Path.Combine(isolated, "source.tiff");
        string copy = Path.Combine(isolated, "copy.tiff");
        try
        {
            Directory.CreateDirectory(isolated);
            byte[] original = Enumerable.Range(0, 4096)
                .Select(index => (byte)(index * 31))
                .ToArray();
            File.WriteAllBytes(source, original);
            File.WriteAllBytes(copy, original);

            Check(
                DefectSourceIdentityReader.TryRead(
                    source,
                    out DefectSourceIdentity identity,
                    out DefectSourceObservation observation) &&
                DefectSourceIdentityReader.TryObserve(source, out DefectSourceObservation unchanged) &&
                observation == unchanged,
                "defect_source_observation_matches_unchanged_file");
            Check(
                DefectSourceIdentityReader.TryRead(copy, out DefectSourceIdentity copiedIdentity) &&
                copiedIdentity == identity,
                "defect_source_content_identity_preserves_same_byte_relink");

            byte[] replacement = original.Select(value => (byte)(value ^ 0x5a)).ToArray();
            File.WriteAllBytes(source, replacement);
            Check(
                DefectSourceIdentityReader.TryObserve(source, out DefectSourceObservation changed) &&
                changed != observation,
                "defect_source_observation_detects_same_size_rewrite");
            Check(
                DefectSourceIdentityReader.TryRead(source, out DefectSourceIdentity changedIdentity) &&
                changedIdentity != identity,
                "defect_source_content_identity_changes_with_bytes");

            VerifyRacyRewriteIsNotCached(isolated);
        }
        finally
        {
            if (Directory.Exists(isolated) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolated))
            {
                Directory.Delete(isolated, recursive: true);
            }
        }
    }

    /// <summary>
    /// 파일 시각의 눈금이 굵어서 같은 크기로 연달아 쓰면 관측값이 그대로일 수 있습니다 - 이
    /// 기계에서 200회 중 92회(46%)가 같은 `LastWriteTime` 을 받았습니다. 그때 identity 캐시가
    /// 이전 내용의 SHA 를 돌려주면 GrainMend 의 "검출 중 원본이 바뀌었나" 판정이 무너집니다.
    /// 한 번은 운으로 통과하므로 충분히 반복해서 못 박습니다.
    /// </summary>
    private static void VerifyRacyRewriteIsNotCached(string isolated)
    {
        string path = Path.Combine(isolated, "racy.tiff");
        const int rounds = 40;
        int stale = 0;
        int observedSame = 0;
        for (int round = 0; round < rounds; round++)
        {
            byte[] first = new byte[4096];
            byte[] second = new byte[4096];
            Array.Fill(first, (byte)(round + 1));
            Array.Fill(second, (byte)(round + 129));
            File.WriteAllBytes(path, first);
            if (!DefectSourceIdentityReader.TryRead(
                    path,
                    out DefectSourceIdentity before,
                    out DefectSourceObservation beforeObserved))
            {
                stale++;
                continue;
            }
            File.WriteAllBytes(path, second);
            if (!DefectSourceIdentityReader.TryRead(
                    path,
                    out DefectSourceIdentity after,
                    out DefectSourceObservation afterObserved))
            {
                stale++;
                continue;
            }
            if (beforeObserved == afterObserved)
            {
                observedSame++;
            }
            if (before == after)
            {
                stale++;
            }
        }
        Check(stale == 0, "defect_source_identity_never_stale_after_same_size_rewrite");
        // 관측값이 한 번도 겹치지 않았다면 이 시험이 실제로 그 경우를 밟지 못한 것입니다.
        // 그 사실 자체는 실패가 아니지만, 밟았을 때 stale 이 0 이어야 한다는 것이 요점입니다.
        _ = observedSame;
    }
}
