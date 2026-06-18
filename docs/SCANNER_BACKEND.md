# Scanner Backend Strategy

How Negaflow talks to a Plustek OpticFilm on macOS.

## TL;DR

| Backend | Role on 8200i today |
|---|---|
| **SANE (`scanimage` + `genesys`)** | **Primary.** Verified end-to-end. |
| **Mock** | Development/demo. No hardware required. |
| **ImageCaptureCore** | **Inactive.** The 8200i never appears in `ICDeviceBrowser`. Kept as a bridge for any future model that does. |

---

## 1. Why SANE is primary (not ICA)

The original plan (`develop_plan.md` §6) assumed ImageCaptureCore would be first choice and SANE a fallback. Phase 0 hardware testing on a real **Plustek OpticFilm 8200i** proved the opposite.

### Evidence (Phase 0, 2026-06-17, this machine)

**USB** — the scanner is present:
```
ioreg -p IOUSB -l
  "USB Product Name" = "Film Scanner"
  "USB Vendor Name"  = "Plustek INC"
  "idVendor"  = 1971   (0x07b3 Plustek)
  "idProduct" = 4876   (0x130C OpticFilm 8200i)
```

**ImageCaptureCore** — the scanner is **not** exposed:
```
ICDeviceBrowser (browsedDeviceTypeMask = .scanner) → 0 devices
```
The OpticFilm has no manufacturer ICA driver that registers it with macOS Image Capture, so `ICScannerDevice` never sees it. This is the single biggest risk in the plan (§16.1), now confirmed real.

**SANE** — the scanner **is** usable:
```
$ scanimage -L
device `genesys:libusb:000:010' is a PLUSTEK OpticFilm 8100 flatbed scanner

$ scanimage -A -d genesys:libusb:000:010
  --mode Color|Gray
  --depth 16
  --resolution 7200|3600|2400|1200|600dpi
  --source "Transparency Adapter"
  -l/-t/-x/-y  (mm geometry)
```
- Backend is **`genesys`** (Genesys Logic chipset), not `plustek`.
- SANE labels the 8200i as an "OpticFilm 8100" — same chipset, overlapping firmware reports. This is precisely why we never branch on a model string.
- **16-bit, 7200 dpi and the transparency unit all open.**
- A **real 3600 dpi / 16-bit RGB TIFF** was captured (5088×3401, ~99 MB, 42 s) and successfully developed through Chromabase.

### What this means
- Negaflow's scanner layer is **SANE first**.
- ICA stays as an inactive bridge (`InactiveImageCaptureBackend`) so a future model that does expose itself to Image Capture can slot in without architectural change.
- IR channel capture is **not** exposed by the genesys backend on this device. IR dust removal remains a Phase 5 research item, exactly as the plan's risk section allows.

---

## 2. Architecture

```
UI  ──▶  ScannerKit (ScannerBackend protocol)
                  ├── SANEBackend        (scanimage CLI wrapper)   ← primary
                  ├── MockScannerBackend (synthetic negatives)     ← dev/demo
                  └── ImageCaptureBridge (ICA)                     ← inactive on 8200i
```

The UI only ever calls `ScannerBackend`. It does not know which backend is live (`develop_plan.md` §4.3).

### Device ID convention
- `sane-<devname>`   e.g. `sane-genesys:libusb:000:010`
- `ica-<uid>`
- `mock-<id>`

`BackendType(fromScannerID:)` reads the prefix so the registry can hand a device back to the right backend.

---

## 3. SANE packaging risk (§16.2)

SANE is a Homebrew dependency during development. For a shipped product:
- developer builds may require `brew install sane-backends`;
- before public beta we evaluate bundling SANE inside the app;
- end users should never have to install SANE manually.

For now, `SANEBackend.findScanimage()` probes the standard Homebrew paths.

---

## 4. How capability discovery works

`scanimage -A` output is parsed into `ScannerCapabilities` (plan §7.3). The UI is built from capabilities, never from a model lookup:

```swift
// GOOD (plan §5.3)
if capabilities.supportsInfrared      { showInfraredUI() }
if capabilities.supports(depth: .16)  { show16BitOption() }
if capabilities.supports(resolution: .r7200) { show7200Option() }

// BAD — never do this
if model == "8200i" { ... }
```

This is what lets the 8100/8300i (and unknown Plustek models) work without code changes: a user runs **Scanner Diagnostics → Export Report**, sends the JSON, and we read the real capabilities.

---

## 5. Reproducing Phase 0

```bash
brew install sane-backends
scanimage -L                                    # expect genesys:libusb:… OpticFilm
scanimage -A -d 'genesys:libusb:000:010'        # capability dump

# a real full-frame 16-bit scan:
scanimage -d 'genesys:libusb:000:010' \
  --mode Color --resolution 3600 --depth 16 \
  -x 36 -y 24 --format=tiff > raw_3600_16bit.tiff

# develop it:
negaflow develop raw_3600_16bit.tiff out.jpg --look rich-neutral
```

> Note: USB device addresses (`libusb:000:NNN`) re-enumerate on replug. Always re-run `scanimage -L` and use the current address. Negaflow's `SANEBackend` does this in `detectScanners()`.
