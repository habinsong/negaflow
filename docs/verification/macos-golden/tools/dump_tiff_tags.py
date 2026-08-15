#!/usr/bin/env python3
"""Dump the TIFF/EXIF/GPS/IPTC tags actually present in a baseline TIFF.

Reads the IFD structure straight out of the file so the reported numbers are the
real on-disk tag numbers, not a library's friendly names.

    python3 dump_tiff_tags.py <file.tif> [...]        # human readable
    python3 dump_tiff_tags.py --json <file.tif> [...] # machine readable
"""
import json
import struct
import sys

TYPE_FORMAT = {
    1: ("B", 1), 2: ("s", 1), 3: ("H", 2), 4: ("I", 4), 5: ("II", 8),
    6: ("b", 1), 7: ("s", 1), 8: ("h", 2), 9: ("i", 4), 10: ("ii", 8),
    11: ("f", 4), 12: ("d", 8),
}
TYPE_NAME = {
    1: "BYTE", 2: "ASCII", 3: "SHORT", 4: "LONG", 5: "RATIONAL", 6: "SBYTE",
    7: "UNDEFINED", 8: "SSHORT", 9: "SLONG", 10: "SRATIONAL", 11: "FLOAT",
    12: "DOUBLE",
}
TIFF_NAMES = {
    256: "ImageWidth", 257: "ImageLength", 258: "BitsPerSample",
    259: "Compression", 262: "PhotometricInterpretation", 266: "FillOrder",
    270: "ImageDescription",
    271: "Make", 272: "Model", 273: "StripOffsets", 274: "Orientation",
    277: "SamplesPerPixel", 278: "RowsPerStrip", 279: "StripByteCounts",
    282: "XResolution", 283: "YResolution", 284: "PlanarConfiguration",
    296: "ResolutionUnit", 305: "Software", 306: "DateTime", 315: "Artist",
    338: "ExtraSamples", 339: "SampleFormat", 33432: "Copyright",
    33723: "IPTC/NAA", 34377: "PhotoshopImageResources", 34665: "ExifIFDPointer",
    34675: "ICCProfile", 34853: "GPSInfoIFDPointer", 700: "XMLPacket(XMP)",
}
EXIF_NAMES = {
    33434: "ExposureTime", 33437: "FNumber", 34855: "ISOSpeedRatings",
    36867: "DateTimeOriginal", 36868: "DateTimeDigitized", 36880: "OffsetTime",
    36881: "OffsetTimeOriginal", 36882: "OffsetTimeDigitized",
    37510: "UserComment", 40962: "PixelXDimension", 40963: "PixelYDimension",
    42036: "LensModel",
}
GPS_NAMES = {
    0: "GPSVersionID", 1: "GPSLatitudeRef", 2: "GPSLatitude",
    3: "GPSLongitudeRef", 4: "GPSLongitude",
}
IPTC_ENVELOPE_NAMES = {90: "CodedCharacterSet"}
IPTC_NAMES = {
    0: "RecordVersion", 5: "ObjectName", 25: "Keywords", 55: "DateCreated", 60: "TimeCreated",
    62: "DigitalCreationDate", 63: "DigitalCreationTime", 80: "By-line",
    85: "By-lineTitle", 90: "City", 92: "Sub-location", 95: "Province/State",
    100: "Country/PrimaryLocationCode", 101: "Country/PrimaryLocationName",
    105: "Headline", 110: "Credit", 115: "Source", 116: "CopyrightNotice",
    120: "Caption/Abstract",
}


def read_values(data, endian, kind, count, payload, offset_field):
    if kind not in TYPE_FORMAT:
        return "<unknown type %d>" % kind
    _, size = TYPE_FORMAT[kind]
    total = size * count
    raw = payload if total <= 4 else data[offset_field:offset_field + total]
    if kind in (2, 7):
        text = raw[:total].split(b"\x00")[0]
        try:
            return text.decode("utf-8")
        except UnicodeDecodeError:
            return repr(text)
    if kind in (5, 10):
        code = "II" if kind == 5 else "ii"
        out = []
        for i in range(count):
            num, den = struct.unpack(endian + code, raw[i * 8:(i + 1) * 8])
            out.append("%d/%d" % (num, den))
        return out if count > 1 else out[0]
    code = TYPE_FORMAT[kind][0]
    values = list(struct.unpack(endian + code * count, raw[:total]))
    return values if count > 1 else values[0]


def read_ifd(data, endian, offset, names):
    entries = []
    count = struct.unpack(endian + "H", data[offset:offset + 2])[0]
    pointers = {}
    for i in range(count):
        base = offset + 2 + i * 12
        tag, kind, n = struct.unpack(endian + "HHI", data[base:base + 8])
        payload = data[base + 8:base + 12]
        value_offset = struct.unpack(endian + "I", payload)[0]
        value = read_values(data, endian, kind, n, payload, value_offset)
        if isinstance(value, (bytes, bytearray)):
            value = repr(value)
        if isinstance(value, list) and len(value) > 16:
            value = value[:16] + ["...(%d total)" % len(value)]
        entries.append({
            "tag": tag,
            "name": names.get(tag, TIFF_NAMES.get(tag, "?")),
            "type": TYPE_NAME.get(kind, str(kind)),
            "count": n,
            "value": value,
        })
        if tag in (34665, 34853, 33723):
            pointers[tag] = (value_offset, n)
    entries.sort(key=lambda e: e["tag"])
    return entries, pointers


def read_iptc(blob):
    out, i = [], 0
    while i + 5 <= len(blob):
        if blob[i] != 0x1C:
            i += 1
            continue
        record, dataset, size = struct.unpack(">BBH", blob[i + 1:i + 5])
        payload = blob[i + 5:i + 5 + size]
        try:
            text = payload.decode("utf-8")
        except UnicodeDecodeError:
            text = repr(payload)
        names = IPTC_ENVELOPE_NAMES if record == 1 else IPTC_NAMES
        out.append({
            "record": record,
            "dataset": dataset,
            "name": names.get(dataset, "?"),
            "value": text,
        })
        i += 5 + size
    return out


def dump(path):
    data = open(path, "rb").read()
    endian = "<" if data[:2] == b"II" else ">"
    first = struct.unpack(endian + "I", data[4:8])[0]
    tiff, pointers = read_ifd(data, endian, first, TIFF_NAMES)
    result = {"file": path, "byteOrder": "little" if endian == "<" else "big",
              "tiffIFD0": tiff}
    if 34665 in pointers:
        result["exifIFD"], _ = read_ifd(data, endian, pointers[34665][0], EXIF_NAMES)
    if 34853 in pointers:
        result["gpsIFD"], _ = read_ifd(data, endian, pointers[34853][0], GPS_NAMES)
    if 33723 in pointers:
        offset, count = pointers[33723]
        result["iptcIIM"] = read_iptc(data[offset:offset + count])
    return result


def main(argv):
    as_json = "--json" in argv
    files = [a for a in argv[1:] if not a.startswith("--")]
    reports = [dump(path) for path in files]
    if as_json:
        print(json.dumps(reports, indent=2, sort_keys=True, ensure_ascii=False))
        return
    for report in reports:
        print("=== %s (%s endian)" % (report["file"], report["byteOrder"]))
        for section in ("tiffIFD0", "exifIFD", "gpsIFD"):
            if section not in report:
                continue
            print("  [%s]" % section)
            for entry in report[section]:
                print("    %-6d %-28s %-9s x%-5d %s" % (
                    entry["tag"], entry["name"], entry["type"],
                    entry["count"], entry["value"]))
        for entry in report.get("iptcIIM", []):
            print("    IPTC %d:%-3d %-28s %s" % (
                entry["record"], entry["dataset"], entry["name"], entry["value"]))


if __name__ == "__main__":
    main(sys.argv)
