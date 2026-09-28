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
    private static string RecipeOf(LibraryFrameSnapshot frame) => recipes.GetValue(frame, value =>
    {
        var request = DevelopRequestFactory.Create(value, Path.ChangeExtension(value.SourcePath, ".thumbnail.png")).Request;
        if (request is null) { throw new ArgumentException("Invalid thumbnail recipe."); }
        byte[] bytes = DevelopedPreviewCacheRecipeCodec.Compose(request, value.DefectRecipe);
        return new CachedRecipe(typeof(ThumbnailCacheIdentity).Assembly.ManifestModule.ModuleVersionId + ":" +
            Convert.ToHexString(SHA256.HashData(bytes)) + ":" + EngineStamp);
    }).Value;

    /// <summary>
    /// recipe 몫을 미리 만들어 둡니다. 현상 요청 직렬화와 결함 마스크 해시라 한 장에 수~십수 ms 이고,
    /// 켤 때 현상·인화 필름스트립이 전 장을 UI 스레드에서 처음 계산해 첫 화면이 1 초 넘게
    /// 늦었습니다. 값은 스냅샷마다 한 번만 저장되므로 여기서 먼저 만들어도 결과는 같습니다.
    /// </summary>
    internal static void Prepare(IReadOnlyList<LibraryFrameSnapshot> frames) =>
        Parallel.ForEach(frames, frame =>
        {
            try
            {
                _ = RecipeOf(frame);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or
                ArgumentException or InvalidOperationException or JsonException or
                NotSupportedException or OverflowException)
            {
                // 만들지 못한 recipe 는 저장되지 않으므로 `Create` 가 같은 실패를 다시 냅니다.
            }
        });

    internal static ThumbnailCacheIdentity? Create(LibraryFrameSnapshot frame)
    {
        try
        {
            string recipe = RecipeOf(frame);
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
