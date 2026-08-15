# Base Auto/Manual mode control

Date: 2026-08-09

## Scope

The Develop inspector exposes Auto, Film, and Manual as one RadioButton group. Film stock and
light-source choices are available only while Film is selected; scanner-profile grading remains
unavailable because no native scanner-profile pipeline exists.

- Auto hides all manual RGB controls and sends the existing v2 Auto request. A retained manual
  sample is not deleted and Auto does not consume it.
- Manual exposes R/G/B only. Switching to it keeps the stored sample; with no sample, it stores
  the macOS fallback `(0.90, 0.65, 0.45)`, clamped to native limits.
- Film accepts only the bundled resolver IDs. Selecting stock `None` returns to Auto without
  deleting the retained Manual sample or the stored light-source ID.
- Positive and rendered-digital frames disable all three mode buttons and their child controls.
- Stable IDs are `negaflow.develop.base`, `.mode.auto`, `.mode.film`, `.mode.manual`,
  `.film-stock`, and `.light-source`. Hidden mode-specific controls are removed from the visible
  UI tree. Slider value buttons are keyboard tab stops.

## Evidence

`powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-debug`
completed with zero build warnings/errors, Catalog 317 assertions, and Shell 267 assertions.
The Shell coverage includes Auto/Film/Manual round-trips, stock `None` returning to Auto,
known/unknown stock and light-source validation, retention of Manual state, and fallback
initialization for an Auto frame without a manual sample.

## Limits

This is not full macOS Base parity. It does not provide scanner-profile grading, the canvas base
picker/reset action, the macOS confident-only estimator, grouped Film picker presentation, or
rendered/UIA/high-contrast/compact/ARM64 runtime evidence.
