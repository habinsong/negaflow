using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

namespace Negaflow.Catalog.UnitTests;

internal static class LibraryFrameTests
{
    public static void RunAppMetadataPersistence()
    {
        LibraryAppMetadataTests.Run();
        LibraryAppliedBaseTests.Run();
    }

    public static void RunFrameBehavior()
    {
        LibraryFrameProjectionTests.Run();
        LibraryFrameValidationTests.Run();
        LibraryFrameWritingTests.Run();
        LibraryFrameOrganizationTests.Run();
    }
}
