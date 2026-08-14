using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 적어 둔 메타데이터를 frame record 에 씁니다. 레시피가 아니므로 <c>params</c> 안이 아니라
/// macOS 와 같이 그 형제 자리에 둡니다.
/// </summary>
/// <remarks>
/// 이 writer 가 모르는 키는 그대로 둡니다. macOS 는 원본 파일이 바뀐 것을 알아채려고
/// <c>sourceMetadataSHA256</c> 도 함께 적는데, Windows 는 아직 그 해시를 계산하지 않습니다 —
/// 남의 키를 지우면 macOS 에서 만든 카탈로그가 조용히 그 보호를 잃습니다.
/// </remarks>
public static class AppMetadataWriter
{
    public static LibraryFrameWriteResult Apply(
        JsonObject frameRecord,
        AppMetadataOverlay? overlay)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        JsonObject updated = frameRecord.DeepClone().AsObject();
        if (overlay is null || overlay.Normalized().IsEmpty)
        {
            // 다 비우면 키 자체를 지웁니다. macOS 도 빈 오버레이는 쓰지 않습니다.
            updated.Remove(LibraryFrameReader.AppMetadataName);
            return LibraryFrameWriteResult.Success(updated);
        }

        AppMetadataOverlay written = overlay.Normalized();
        if (written.Revision == 0)
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidAppMetadata);
        }

        JsonObject node = updated[LibraryFrameReader.AppMetadataName] is JsonObject existing
            ? existing
            : [];
        node[LibraryFrameReader.AppMetadataVersionName] = AppMetadataOverlay.CurrentVersion;
        WriteOptional(node, LibraryFrameReader.AppMetadataTitleName, written.Title);
        WriteOptional(node, LibraryFrameReader.AppMetadataCaptionName, written.Caption);
        WriteOptional(node, LibraryFrameReader.AppMetadataCopyrightName, written.Copyright);
        if (written.Keywords.Count == 0)
        {
            node.Remove(LibraryFrameReader.AppMetadataKeywordsName);
        }
        else
        {
            var keywords = new JsonArray();
            foreach (string keyword in written.Keywords)
            {
                keywords.Add(keyword);
            }
            node[LibraryFrameReader.AppMetadataKeywordsName] = keywords;
        }
        if (written.FilmShot is { } shot && !shot.IsEmpty)
        {
            JsonObject shotNode = node[LibraryFrameReader.FilmShotName] is JsonObject existingShot
                ? existingShot
                : [];
            WriteOptional(shotNode, LibraryFrameReader.FilmShotCameraMakeName, shot.CameraMake);
            WriteOptional(shotNode, LibraryFrameReader.FilmShotCameraModelName, shot.CameraModel);
            WriteOptional(shotNode, LibraryFrameReader.FilmShotLensModelName, shot.LensModel);
            WriteOptional(shotNode, LibraryFrameReader.FilmShotFilmStockName, shot.FilmStock);
            WriteOptional(shotNode, LibraryFrameReader.FilmShotIsoSpeedName, shot.IsoSpeed);
            WriteOptional(shotNode, LibraryFrameReader.FilmShotExposureTimeName, shot.ExposureTimeSeconds);
            WriteOptional(shotNode, LibraryFrameReader.FilmShotFNumberName, shot.FNumber);
            WriteOptional(shotNode, LibraryFrameReader.FilmShotFocalLengthName, shot.FocalLengthMm);
            node[LibraryFrameReader.FilmShotName] = shotNode;
        }
        else
        {
            node.Remove(LibraryFrameReader.FilmShotName);
        }
        node[LibraryFrameReader.AppMetadataRevisionName] = written.Revision;
        node[LibraryFrameReader.AppMetadataUpdatedAtName] =
            (written.UpdatedAt - LibraryFrameReader.AppleReferenceDate).TotalSeconds;
        updated[LibraryFrameReader.AppMetadataName] = node;
        return LibraryFrameWriteResult.Success(updated);
    }

    private static void WriteOptional(JsonObject owner, string name, string? value)
    {
        if (value is null)
        {
            owner.Remove(name);
        }
        else
        {
            owner[name] = value;
        }
    }

    private static void WriteOptional(JsonObject owner, string name, int? value)
    {
        if (value is null)
        {
            owner.Remove(name);
        }
        else
        {
            owner[name] = value.Value;
        }
    }

    private static void WriteOptional(JsonObject owner, string name, double? value)
    {
        if (value is null)
        {
            owner.Remove(name);
        }
        else
        {
            owner[name] = value.Value;
        }
    }
}
