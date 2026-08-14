using System.Globalization;
using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

public enum LibraryRollKind
{
    Physical,
    Unassigned,
}

/// <summary>
/// 한 롤입니다. macOS <c>LibraryRoll</c> 과 같은 필드·같은 catalog 표(<c>rolls</c>)이며,
/// 롤 기록(<see cref="RollRecord"/>)은 이 롤에 속한 frame 의 **비어 있는 칸만** 채웁니다.
/// </summary>
/// <remarks>
/// 한 롤은 대개 같은 카메라·렌즈·필름으로 찍힙니다. 그것을 프레임마다 36번 적게 하는 대신 롤에
/// 한 번 적습니다. 이미 적어 둔 프레임 값은 건드리지 않습니다 — 롤 중간에 렌즈를 바꾸는 일이
/// 실제로 있기 때문입니다.
/// </remarks>
public sealed record LibraryRollSnapshot(
    string Id,
    LibraryRollKind Kind,
    string? Name,
    DateTimeOffset CreatedAt,
    FilmType? FilmType,
    IReadOnlyList<string> FrameIds,
    RollRecord? Record)
{
    /// <summary>macOS 와 같은 고정 id 입니다. 어느 롤에도 넣지 않은 사진이 여기에 모입니다.</summary>
    public const string UnassignedId = "00000000-0000-4000-8000-000000000001";
}

/// <summary>
/// 롤에 적어 두는 기록입니다. 롤 코드는 파일 이름 토큰으로도 씁니다 — 네거티브 봉투에 적는
/// 코드와 내보낸 파일 이름이 같아야 나중에 필름과 파일을 맞출 수 있습니다.
/// </summary>
public sealed record RollRecord(
    string? Code = null,
    FilmShotMetadata? Shot = null,
    string? Notes = null)
{
    public bool IsEmpty =>
        Code is null && Notes is null && (Shot?.IsEmpty ?? true);

    public RollRecord Normalized() => new(
        AppMetadataOverlay.NormalizeText(Code),
        Shot is { } shot && !shot.Normalized().IsEmpty ? shot.Normalized() : null,
        AppMetadataOverlay.NormalizeText(Notes));

    /// <summary>
    /// 프레임의 촬영 기록에서 비어 있는 칸만 롤 값으로 채웁니다. 채울 것이 없으면 null 입니다.
    /// </summary>
    public FilmShotMetadata? Filling(FilmShotMetadata? frameShot)
    {
        if (Shot is not { } roll)
        {
            return null;
        }
        FilmShotMetadata current = frameShot ?? new FilmShotMetadata();
        FilmShotMetadata merged = new(
            current.CameraMake ?? roll.CameraMake,
            current.CameraModel ?? roll.CameraModel,
            current.LensModel ?? roll.LensModel,
            current.FilmStock ?? roll.FilmStock,
            current.IsoSpeed ?? roll.IsoSpeed,
            current.ExposureTimeSeconds ?? roll.ExposureTimeSeconds,
            current.FNumber ?? roll.FNumber,
            current.FocalLengthMm ?? roll.FocalLengthMm);
        return merged == frameShot ? null : merged;
    }
}

internal static class LibraryRollRecordCodec
{
    private const string IdName = "id";
    private const string KindName = "kind";
    private const string NameName = "name";
    private const string CreatedAtName = "createdAt";
    private const string FilmTypeName = "filmType";
    private const string FrameIdsName = "frameIDs";
    private const string RecordName = "record";
    private const string RecordCodeName = "code";
    private const string RecordNotesName = "notes";
    private const string RecordShotName = "shot";

    public static bool TryRead(CatalogEntityRow row, out LibraryRollSnapshot roll)
    {
        roll = default!;
        if (string.IsNullOrWhiteSpace(row.Id) ||
            row.Payload[IdName]?.GetValue<string>() is not { } payloadId ||
            !string.Equals(row.Id, payloadId, StringComparison.Ordinal) ||
            !TryReadKind(row.Payload[KindName], out LibraryRollKind kind) ||
            !TryReadCreatedAt(row.Payload[CreatedAtName], out DateTimeOffset createdAt) ||
            !TryReadFrameIds(row.Payload[FrameIdsName], out IReadOnlyList<string> frameIds) ||
            !TryReadRecord(row.Payload[RecordName], out RollRecord? record))
        {
            return false;
        }
        FilmType? filmType = null;
        if (row.Payload[FilmTypeName]?.GetValue<string>() is { } filmTypeText)
        {
            if (!Enum.TryParse(filmTypeText, ignoreCase: true, out FilmType parsed))
            {
                return false;
            }
            filmType = parsed;
        }
        roll = new LibraryRollSnapshot(
            row.Id,
            kind,
            AppMetadataOverlay.NormalizeText(row.Payload[NameName]?.GetValue<string>()),
            createdAt,
            filmType,
            frameIds,
            record);
        return true;
    }

    public static CatalogEntityRow Write(LibraryRollSnapshot roll)
    {
        var frameIds = new JsonArray();
        foreach (string frameId in roll.FrameIds)
        {
            frameIds.Add(frameId);
        }
        var payload = new JsonObject
        {
            [IdName] = roll.Id,
            [KindName] = roll.Kind == LibraryRollKind.Physical ? "physical" : "unassigned",
            [CreatedAtName] = roll.CreatedAt.ToString("O", CultureInfo.InvariantCulture),
            [FrameIdsName] = frameIds,
        };
        if (roll.Name is { } name)
        {
            payload[NameName] = name;
        }
        if (roll.FilmType is { } filmType)
        {
            payload[FilmTypeName] = filmType.ToString();
        }
        if (roll.Record is { } record && !record.Normalized().IsEmpty)
        {
            RollRecord written = record.Normalized();
            var node = new JsonObject();
            if (written.Code is { } code)
            {
                node[RecordCodeName] = code;
            }
            if (written.Notes is { } notes)
            {
                node[RecordNotesName] = notes;
            }
            if (written.Shot is { } shot)
            {
                node[RecordShotName] = WriteShot(shot);
            }
            payload[RecordName] = node;
        }
        return new CatalogEntityRow(roll.Id, payload);
    }

    private static JsonObject WriteShot(FilmShotMetadata shot)
    {
        var node = new JsonObject();
        AddText(node, "cameraMake", shot.CameraMake);
        AddText(node, "cameraModel", shot.CameraModel);
        AddText(node, "lensModel", shot.LensModel);
        AddText(node, "filmStock", shot.FilmStock);
        if (shot.IsoSpeed is { } iso)
        {
            node["isoSpeed"] = iso;
        }
        if (shot.ExposureTimeSeconds is { } exposure)
        {
            node["exposureTimeSeconds"] = exposure;
        }
        if (shot.FNumber is { } fNumber)
        {
            node["fNumber"] = fNumber;
        }
        if (shot.FocalLengthMm is { } focal)
        {
            node["focalLengthMM"] = focal;
        }
        return node;
    }

    private static void AddText(JsonObject node, string name, string? value)
    {
        if (value is not null)
        {
            node[name] = value;
        }
    }

    private static bool TryReadKind(JsonNode? node, out LibraryRollKind kind)
    {
        kind = LibraryRollKind.Physical;
        return node?.GetValue<string>() switch
        {
            "physical" => true,
            "unassigned" => Assign(ref kind, LibraryRollKind.Unassigned),
            _ => false,
        };
    }

    private static bool Assign(ref LibraryRollKind target, LibraryRollKind value)
    {
        target = value;
        return true;
    }

    private static bool TryReadCreatedAt(JsonNode? node, out DateTimeOffset createdAt) =>
        DateTimeOffset.TryParse(
            node?.GetValue<string>(),
            CultureInfo.InvariantCulture,
            DateTimeStyles.RoundtripKind,
            out createdAt);

    private static bool TryReadFrameIds(JsonNode? node, out IReadOnlyList<string> frameIds)
    {
        frameIds = [];
        if (node is null)
        {
            return true;
        }
        if (node is not JsonArray array)
        {
            return false;
        }
        var read = new List<string>(array.Count);
        foreach (JsonNode? item in array)
        {
            // 한 칸이라도 모양이 다르면 롤을 통째로 거부합니다. 조용히 건너뛰면 사용자에게는
            // 사진이 롤에서 사라진 것으로 보입니다.
            if (item?.GetValue<string>() is not { } frameId || string.IsNullOrWhiteSpace(frameId))
            {
                return false;
            }
            read.Add(frameId);
        }
        frameIds = read;
        return true;
    }

    private static bool TryReadRecord(JsonNode? node, out RollRecord? record)
    {
        record = null;
        if (node is null)
        {
            return true;
        }
        if (node is not JsonObject owner)
        {
            return false;
        }
        FilmShotMetadata? shot = null;
        if (owner[RecordShotName] is { } shotNode)
        {
            if (shotNode is not JsonObject shotOwner)
            {
                return false;
            }
            shot = new FilmShotMetadata(
                shotOwner["cameraMake"]?.GetValue<string>(),
                shotOwner["cameraModel"]?.GetValue<string>(),
                shotOwner["lensModel"]?.GetValue<string>(),
                shotOwner["filmStock"]?.GetValue<string>(),
                shotOwner["isoSpeed"]?.GetValue<int>(),
                shotOwner["exposureTimeSeconds"]?.GetValue<double>(),
                shotOwner["fNumber"]?.GetValue<double>(),
                shotOwner["focalLengthMM"]?.GetValue<double>()).Normalized();
        }
        RollRecord parsed = new(
            owner[RecordCodeName]?.GetValue<string>(),
            shot is { IsEmpty: false } ? shot : null,
            owner[RecordNotesName]?.GetValue<string>());
        record = parsed.Normalized().IsEmpty ? null : parsed.Normalized();
        return true;
    }
}
