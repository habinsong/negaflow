using System.Buffers;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

public static class CatalogJson
{
    public static byte[] SerializeCanonical(JsonNode value)
    {
        ArgumentNullException.ThrowIfNull(value);

        ArrayBufferWriter<byte> buffer = new();
        using (Utf8JsonWriter writer = new(buffer))
        {
            WriteNode(writer, value);
        }
        return buffer.WrittenSpan.ToArray();
    }

    private static void WriteNode(Utf8JsonWriter writer, JsonNode? node)
    {
        switch (node)
        {
            case null:
                writer.WriteNullValue();
                return;
            case JsonObject jsonObject:
                writer.WriteStartObject();
                foreach ((string name, JsonNode? child) in
                    jsonObject.OrderBy(property => property.Key, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(name);
                    WriteNode(writer, child);
                }
                writer.WriteEndObject();
                return;
            case JsonArray jsonArray:
                writer.WriteStartArray();
                foreach (JsonNode? child in jsonArray)
                {
                    WriteNode(writer, child);
                }
                writer.WriteEndArray();
                return;
            case JsonValue jsonValue:
                jsonValue.WriteTo(writer);
                return;
            default:
                throw new JsonException($"Unsupported JSON node type: {node.GetType().FullName}");
        }
    }
}
