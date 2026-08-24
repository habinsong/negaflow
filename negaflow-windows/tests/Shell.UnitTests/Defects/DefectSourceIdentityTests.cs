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
}
