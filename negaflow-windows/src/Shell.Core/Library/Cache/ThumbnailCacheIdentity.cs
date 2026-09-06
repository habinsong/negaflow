using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text.Json;
using Negaflow.Catalog;

namespace Negaflow.Shell.Library;

internal sealed record ThumbnailCacheIdentity(string Recipe, string? SourceStamp)
{
    private sealed record CachedRecipe(string Value);
    private static readonly string EngineStamp = EngineIdentity();
    private static string EngineIdentity()
    {
        try
        {
            var file = new FileInfo(Path.Combine(AppContext.BaseDirectory, "Negaflow.Native.dll"));
            return file.Exists ? $"{file.Length}:{file.LastWriteTimeUtc.Ticks}" : "no-native";
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return "unavailable"; }
    }
    private static readonly ConditionalWeakTable<LibraryFrameSnapshot, CachedRecipe> recipes = new();
    internal static ThumbnailCacheIdentity? Create(LibraryFrameSnapshot frame)
    {
        try
        {
            string recipe = recipes.GetValue(frame, value =>
            {
                var request = DevelopRequestFactory.Create(value, Path.ChangeExtension(value.SourcePath, ".thumbnail.png")).Request;
                if (request is null) { throw new ArgumentException("Invalid thumbnail recipe."); }
                byte[] bytes = DevelopedPreviewCacheRecipeCodec.Compose(request, value.DefectRecipe);
                return new CachedRecipe(typeof(ThumbnailCacheIdentity).Assembly.ManifestModule.ModuleVersionId + ":" +
                    Convert.ToHexString(SHA256.HashData(bytes)) + ":" + EngineStamp);
            }).Value;
            if (OperatingSystem.IsWindows())
            {
                return new(recipe, DevelopedPreviewCacheIdentityFactory.TryObserve(frame.SourcePath, out var observed)
                    ? $"{observed.VolumeSerialNumber}:{observed.FileIndex}:{observed.FileBytes}:{observed.LastWriteTicks}" : null);
            }
            var file = new FileInfo(frame.SourcePath);
            return new(recipe, file.Exists ? $"{file.Length}:{file.LastWriteTimeUtc.Ticks}" : null);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or
            InvalidOperationException or JsonException or NotSupportedException or OverflowException)
        { return null; }
    }
    internal bool Accepts(ThumbnailCacheIdentity? stored) => stored is not null && Recipe == stored.Recipe &&
        (SourceStamp is null || SourceStamp == stored.SourceStamp);
}
