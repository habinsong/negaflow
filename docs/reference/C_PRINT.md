# Print layouts and C-print preview

[Docs home](../README.md)

Print has eight layouts: single image, contact sheet, picture package, custom package, cyanotype, glass plate, gelatin silver and watermark.

## Contact sheets

- A new contact sheet starts black, with 6 columns × 7 rows and 2 mm gaps. Every other layout starts white. Each layout can switch its sheet among black, gray and white, and captions, custom text, crop marks and page outlines change to a contrasting color on their own.
- Margins, row and column counts and gaps share one physical layout contract. An impossible combination is reduced to the largest valid spacing instead of breaking the preview. Automatic orientation follows the grid. **Fit** keeps the whole photo visible and may leave space inside its cell. **Fill Cell** crops each photo to the common cell and evens the gutters.
- Captions can be the file name, original frame number, sequence number (from 1 in the current image order), rating or custom text. Any installed Mac font can be chosen, and preview and export use the same font. Per-image captions align left, center or right. Custom text supports several independent boxes, each with its own text, alignment, position, width and height.

## Paper controls and rulers

Every layout uses the same paper controls. The catalog has common photographic inch sizes from 3.5 × 5 to 24 × 36, Letter, Tabloid, A3+, ISO A1–A6 and ISO B1–B6. Surface sits below Sheet Color and offers Matte (default), Glossy, Lustre and Silk.

Rulers are off by default. Turning them on adds an in/cm selector below the switch, a horizontal ruler above the page and a vertical ruler at its left. Whole inches or centimeters are numbered, with subdivision ticks between them.

## Individual and historical layouts

Single image, cyanotype, glass plate and gelatin silver produce one page per selected photo. Several selected photos appear as a vertical stack. Cyanotype maps luminance to a blue monochrome image, glass plate shows a monochrome negative, and gelatin silver shows a neutral monochrome positive.

These three styles use the same paper, orientation, margin, output and inspector controls as Single Image, and they are rendered into Export and Quick Export. They are deliberate visual styles, not a measured reconstruction of any historic chemistry, plate, paper or viewing condition.

## Watermarks and layout templates

Watermark is its own layout type. Selecting it sets the paper size to Photo Ratio (another size can be chosen afterwards) and adds borders outside the photo. The name position menu is always available: Bottom Center, Top Left, Top Center or Top Right, and a top position turns on the top border. Shutter speeds get no added quote mark, and empty text fields stay empty. Name text is centered in its position. When the name and the histogram share a position, the histogram sits above the name and each is centered.

A layout template restores the layout, paper settings, sheet color and watermark settings, then refreshes the preview. DPI and ruler settings stay as they were. Templates saved before these fields existed keep the current sheet color and watermark. Field placement and the DNG source and color-space rules are in [Library to print workflow](../product/WORKFLOW.md).

## Print export

**Print Export**, directly below Quick Export, renders the current page size, orientation, margins, layout, sheet color, captions, custom text and crop marks, using the format, DPI, folder, naming and delivery color space shown in Export. Screen-only aids are not baked in: gamut warnings, soft-proof simulation and paper-surface sheen. While either Print Export path runs, the Export panel shows the completed-page count, a linear progress bar and a percentage.

### Page counts and rendering

The count is finished pages. A 39-photo 6 × 7 contact sheet exports one composed page, a four-up picture package exports 10 pages, the default custom package exports one page, and each individual-image layout exports 39 files through the same bounded batch scheduler as Quick Export.

The package preview does not build interactive and settled full-resolution previews for every photo. It reuses available images and makes only a thumbnail-sized fast preview for a missing item. Final export derives the layout from source metadata, develops only the pixels each placement needs, prepares two to four unique sources at a time and keeps the Core Image graph connected until the page is written. The shared render context and a 512 MiB per-page source-raster budget bound memory without changing the visible layout or the output contract.

### Printer output profile

The Printer Output Profile chosen in Print is part of the exported result. negaflow composes the whole page first and applies the profile once to the finished page, which covers every placement in a picture package or custom package, whether it repeats one photo or mixes several. The profile does not affect the Library or Develop preview, only Print preview and Print Export.

## C-print use

Output Process is Standard or C-print. C-print records the destination lab and paper and uses an RGB ICC profile supplied by that lab for an on-screen soft proof. The Surface control stays in Layout for every process and layout. Without a measured profile, negaflow applies no generic “C-print look”.

1. Open the Print workspace and choose **C-print** under Output Process.
2. Enter the lab and paper. Choose the surface under Layout if needed.
3. Choose the RGB ICC profile supplied for that lab, paper and machine.
4. Turn on Print Preview. Paper and black-ink simulation and the gamut warning are under Advanced.

Without a valid RGB ICC profile the destination settings are still saved, but Print Preview stays unavailable. CMYK and device-link profiles are not accepted by this RGB preview path.

## Color contract

The C-print proof ICC is proof-only. It changes the on-screen preview, not the pixels or the embedded profile of an exported file. Print Export uses the Delivery Color Space chosen in Export unless a Printer Output Profile is selected, so a lab soft-proof profile is never silently used as a delivery profile. The `PRINT` develop target is separate. It requires a valid RGB printer-class ICC profile and converts output through it.

## Accuracy limits

The preview includes the ICC transform and can optionally simulate paper white, black point and out-of-gamut colors. Its accuracy depends on a calibrated display and a current profile for the exact lab process. It cannot predict viewing light, chemistry drift, machine calibration or paper batch variation. negaflow does not bundle or invent a lab profile.
