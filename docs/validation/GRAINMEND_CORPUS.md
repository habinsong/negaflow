# GrainMend real scan comparison

[Docs home](../README.md)

Regression checks for GrainMend RGB use FILM-R v2.

| Item | Value |
|---|---|
| Damaged and hand-restored pairs | 44 each |
| License | CC BY 4.0 |
| Total size | 437,570,872 bytes |
| Location | `build/defect-corpus/` |
| Used for | GrainMend RGB regression comparison |

## The material

- Title: *Authentically damaged & manually restored film scans*
- Author: Daniela Ivanova
- DOI: <https://doi.org/10.6084/m9.figshare.21803304.v2>
- Paper: <https://doi.org/10.1111/cgf.14749>
- Description: <https://daniela997.github.io/FilmDamageSimulator/>
- License: CC BY 4.0
- Contents: 44 damaged 35mm film scans and 44 expert hand restorations
- Total size: 437,570,872 bytes

The images stay out of the repository.
`Config/defect-corpus-film-r-v2.json` pins the DOI version, license, pair count, and total size.
The fetch script checks the per-file MD5 and size Figshare provides.
Downloads and results go to `build/defect-corpus/`, which Git ignores.

## Fetching

The plain command fetches one pair for a quick look.

<details>
<summary>Fetch commands</summary>

```bash
python3 scripts/defect-corpus/fetch-film-r.py
```

All 44 pairs:

```bash
python3 scripts/defect-corpus/fetch-film-r.py --all
```

If the Figshare file CDN blocks automated requests,
download the ZIP from the dataset page with `Download all` and verify it as it is.
Extraction finishes only when the file names, sizes,
and Figshare MD5 in the ZIP all match the pinned contract.

```bash
python3 scripts/defect-corpus/fetch-film-r.py \
  --archive ~/Downloads/21803304.zip \
  --all
```

One case only:

```bash
python3 scripts/defect-corpus/fetch-film-r.py --case portra400_135_1
```

</details>

## Running the comparison

Put the damaged files and the restorations, whose names end in `_restored`, in the same folder.

<details open>
<summary>Command for the 44 pairs</summary>

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run -c release negaflow defect-bench build/defect-corpus/film-r-v2 \
  --reference-dir build/defect-corpus/film-r-v2 \
  --out build/defect-corpus/film-r-v2-report \
  --metrics-only
```

</details>

`--metrics-only` skips the large PNGs.
Drop the option and it also writes `before`, `after`, `diff`, `mask`,
and 100% crops for manual review.

What the report carries:

- Existing detection count, confidence, changed pixel count, processing time
- PSNR and mean absolute error between the damaged file and the expert restoration
- PSNR and mean absolute error between the GrainMend result and the expert restoration
- Change in PSNR
- Share of pixels whose error against the reference went down or up

The FILM-R paper uses PSNR, SSIM, and LPIPS together. This repository adds no new ML dependency,
so it computes only PSNR and absolute error from the standard library.

These numbers alone do not approve a release.
Hand restorations carry editing judgement and JPEG differences too.
The automatic quality floor for re-running the same material and settings is pinned in
`Config/defect-removal-film-r-v2-baseline.json` .
The final call needs `before`, `after`, `diff`, `mask`, and the 100% crops side by side.

> [!CAUTION]
> GrainMend image quality is not approved on PSNR or mean error alone. Damage to real texture
> and false detections are judged from the before and after images, the difference image, the
> mask, and 100% crops together.

This material can only check the GrainMend RGB path on rendered images.
It cannot prove RAW decoding, film inversion accuracy, IR alignment, or how a real scanner behaves.

## Result on 2026-07-25

All 44 pairs ran on a Release build with `--metrics-only --crops 0`.
The previous regression baseline at sensitivity 3.0 was compared against 0.7,
the automatic path for the release.

| Metric | Previous baseline 3.0 | Safe auto 0.7 |
|---|---:|---:|
| Images evaluated | 44 | 44 |
| PSNR better / worse / same | 11 / 33 / 0 | 34 / 6 / 4 |
| Mean PSNR change | -1.688 dB | +0.466 dB |
| Median PSNR change | -0.237 dB | +0.118 dB |
| Worst PSNR change | -18.952 dB | -1.338 dB |
| Weighted improved pixels | 0.128% | 0.029% |
| Weighted worsened pixels | 0.792% | 0.017% |
| Weighted changed pixels | 0.794% | 0.043% |
| Automatic safety stop | none | 3 images |

The old app default was 6.0, more aggressive even than the 3.0 baseline.
The automatic path for the release drops to 0.7, and micro-speck detection is off by default.
When candidates exceed 2% of a tile, components touching that tile are dropped.
If any tile goes over 5%, or total candidates after filtering go over 0.06%,
automatic repair is not applied to that photo. The user can narrow the area with Guided instead.

This safety line applies to Auto only.
It does not restrict detection range or repair behavior for Guided, Brush, Clone Stamp, or IR.

`Config/defect-removal-film-r-v2-baseline.json` checks the observed regression baseline plus these
absolute floors.

- At least 30 improved, at most 10 worsened
- Mean and median PSNR change of 0 dB or better
- Worst PSNR change of -1.5 dB or better
- Weighted worsened pixels at 0.03% or less
- Total changed pixels at 0.06% or less

Against the previous baseline this run improved 23 more images, worsened 27 fewer,
and lifted the worst case by 17.614 dB.
Six images still score lower in PSNR than the expert restoration.
FILM-R gives real damage and hand restorations,
and it also carries the ambiguity of restoration judgement.
The material and the paper are at [the FILM-R project](https:
//daniela997.github.io/FilmDamageSimulator/) and [the FILM-R paper](https:
//arxiv.org/abs/2302.10004).

Dropping dense candidates from Auto lines up with earlier image restoration work on cutting false
detections in textured areas.
Even so, this result cannot claim any of the following.

- Automatic results beat hand restoration on every photo.
- GrainMend RGB is the same as hardware IR cleaning.
- RGB/IR alignment and optical quality on a real scanner are verified.

A full re-run happens in the manual `GrainMend corpus` workflow.
Alongside the automatic quality gate, the 100% crops still need a manual look.
