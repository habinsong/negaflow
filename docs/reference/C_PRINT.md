# Print layouts and C-print preview

[Docs home](../README.md)

The Print workspace combines page layout, page export, and output-process preview. It supports
single image, contact sheet, picture package, custom package, cyanotype, glass plate, and gelatin
silver.

## Contact sheets

New contact sheets start with a black sheet, 6 columns × 7 rows, and 2 mm horizontal and vertical
gaps. Every other layout starts with a white sheet. Every layout can switch its sheet independently
between black, gray, and white; captions, custom text, crop marks, and page outlines automatically
use a contrasting color.

Margins, row and column counts, and horizontal and vertical gaps use one physical layout contract.
Impossible combinations are reduced to the largest valid spacing instead of producing a broken
preview. Automatic orientation follows the grid rather than the first selected photo. With **Fit**,
the full photo remains visible and unused space may remain inside its cell; **Fill Cell** crops each
photo to the common cell and makes the visible gutters uniform.

Caption choices are file name, original frame number, sequence number starting at 1 in the current
image order, rating, and custom text. When captions are enabled, any installed Mac font can be
selected and the same font is used in the preview and print export. Per-image captions can be
aligned left, center, or right.
Custom text supports multiple independent text boxes; each box has its own text, alignment,
position, width, and height anywhere on the sheet.

## Paper controls and rulers

Every layout uses the same paper controls. The paper catalog includes common photographic inch
sizes from 3.5 × 5 through 24 × 36, Letter, Tabloid, A3+, ISO A1–A6, and ISO B1–B6. Surface is
directly below Sheet Color and offers Matte, Glossy, Lustre, and Silk; Matte is the default.

Rulers are off by default. Turning them on reveals an in/cm selector directly below the switch and
adds a horizontal ruler above the page and a vertical ruler to its left. Whole inches or
centimeters are numbered, with smaller subdivision ticks between them.

## Individual and historical layouts

Single image, cyanotype, glass plate, and gelatin silver produce one page for each selected photo.
When several photos are selected, Print shows those pages in a vertical stack instead of trying to
combine them into one sheet. Cyanotype maps luminance to a blue monochrome image, glass plate shows
a monochrome negative, and gelatin silver shows a neutral monochrome positive.

These three styles use the same paper, orientation, margin, output, and inspector controls as Single
Image. They are intentional visual presentation styles and are rendered into Export and Quick
Export. They are not a measured reconstruction of a particular historic chemistry, plate, paper,
or viewing condition.

## Print export

**Print Export**, directly below Quick Export, renders the current page size, orientation, margins,
layout, black, gray, or white sheet, captions, custom text, and crop marks. It uses the format, DPI, folder,
naming, and delivery color-space settings shown in Export. Screen-only aids are not baked into the file: gamut warnings,
soft-proof simulation, and paper-surface sheen.

While either Print Export path is running, the Export panel shows the completed-page count, a
linear progress bar, and a percentage instead of an indeterminate spinner.

### Page counts and rendering

The output count reports finished pages. A 39-photo 6 × 7 contact sheet exports one composed page;
a four-up picture package exports 10 pages; the default custom package exports one page; and each
individual-image layout exports 39 files through the same bounded batch scheduler used by Quick
Export.

The package preview does not generate interactive and settled full-resolution previews for every
photo. It reuses available images and creates only a thumbnail-sized fast preview for a missing
item. Final export derives layout from source metadata, develops only the pixels required by each
placement, prepares two to four unique sources at a time, and keeps the Core Image graph connected
until the page write. The shared render context and 512 MiB per-page source-raster budget bound
memory without changing the visible layout or output contract.

### Printer output profile

The Printer Output Profile selected in the Print workspace is part of the exported result. negaflow
first composes the whole page, then applies that profile once to the finished page. This covers
every placement in a picture package or custom package, including layouts that repeat one source
photo and layouts that mix several photos.

This profile does not affect the Library or Develop preview. Changing it is limited to Print preview
and Print Export.

## C-print use

The output process can be Standard or C-print. C-print records the destination lab and paper, then
uses an RGB ICC profile supplied by that lab for an on-screen soft proof. The common Surface control
remains in Layout for every output process and layout. negaflow
does not apply a generic “C-print look” when no measured profile is available.

1. Open the Print workspace and choose **C-print** under Output Process.
2. Enter the lab and paper. Choose the surface under Layout if needed.
3. Choose the RGB ICC profile supplied for that lab, paper, and machine.
4. Turn on Print Preview. Paper and black-ink simulation and gamut warning are under Advanced.

Without a valid RGB ICC profile, the destination settings are still saved but Print Preview stays
unavailable. CMYK and device-link profiles are not accepted by this RGB preview path.

## Color contract

The C-print proof ICC is proof-only. It changes the on-screen preview, not the pixels or embedded
profile of an exported file. Print Export uses the Delivery Color Space selected in Export settings
unless a separate Printer Output Profile is selected. This prevents a lab soft-proof profile from
being silently used as a delivery profile.

The older `PRINT` develop target remains separate. It still requires a valid RGB printer-class ICC
profile and converts output through that profile.

## Accuracy limits

The preview includes the ICC transform and can optionally simulate paper white, black point, and
out-of-gamut colors. Its accuracy depends on a calibrated display and a current profile for the
exact lab process. It cannot predict viewing light, chemistry drift, machine calibration, or paper
batch variation. negaflow does not bundle or invent a lab profile.
