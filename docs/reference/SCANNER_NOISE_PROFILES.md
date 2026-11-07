# Scanner noise profiles

[Docs home](../README.md)

A noise profile cannot be built from one ordinary photograph, because its high-frequency part mixes the subject with film grain.

Scan a flat or stepped target at least three times with the same settings. The change in pixel value at the same position gives the variance per signal level.

- [ISO 15739:2023](https://www.iso.org/standard/82233.html) sets how noise per signal is measured and reported for digital imaging devices.
- [ISO 21550:2004](https://www.iso.org/standard/35939.html) sets how the dynamic range of transmissive and reflective scanners is measured.

ISO 15739 is written for digital cameras. negaflow does not claim scanners fall under it and borrows only the ideas of repeated measurement and variance per signal.

> [!NOTE]
> The current bundle has no `holdoutValidated` device noise profile, so none applies automatically. Texture numbers from existing profiles are not used as sensor noise data.

## What one profile covers

`ScannerNoiseProfile` matches only when all of these are the same:

- Scanner maker and model
- Resolution in DPI
- Bit depth per channel
- Color mode
- Whether multi-exposure is on

Values from a similar model or another resolution are not borrowed. If more than one automatic profile matches exactly, it fails instead of picking one.

From at least three linear RGB scans of the same scene, this is fitted per channel:

```math
\operatorname{variance}(x) = m_{\mathrm{shot}}x + b_{\mathrm{read}}
```

The profile also records:

- SHA-256 of the calibration material
- Number of measured frames and samples
- The observed signal range
- Regression R²
- The validated noise reduction strength

The maximum strength in code only guards against a broken calculation. It is not a quality pass mark.

## States

| State | Meaning | Applies automatically |
|---|---|---|
| `draft` | Measurement or tuning is unfinished | No |
| `measured` | Repeated measurement on a real device, no independent validation | No |
| `holdoutValidated` | Strength checked against separate validation material | Only on an exact match |

Automatic use needs exactly one matching `holdoutValidated` profile, and the SHA-256 of the calibration and validation material and the file structure checks must pass. `draft` and `measured` cannot change the existing general settings.

## Where it stands

The NORITSU and SP-3000 color profiles in the repository carry `texture` values from real scenes. Those values mix subject, focus and film grain, so they are no use as sensor noise data.

Repeated flat targets and separate validation material do not exist yet. No validated device noise profile is bundled, and the automatic path uses the existing general settings.

A real profile needs all of this:

1. Three or more linear scans with the same device, resolution, bit depth, color mode and multi-exposure setting
2. The file list and SHA-256 of the calibration material
3. A validation scene not used for calibration, with its SHA-256
4. A comparison of noise reduction against detail and film grain preservation
5. A 100% zoom check by a real user

Capture on real hardware is handled by the `negaflow-scanner-sane` plugin. SANE options and device control code do not go into this repository.
