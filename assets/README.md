# App icon

`mac-tools-icon-01.svg` is the selected **01 — Everyday toolbox** artwork from
[issue #1](https://github.com/denwilliams/mac-tools/issues/1), preserved unchanged.
`AppIcon.iconset` contains the standard macOS 16, 32, 128, 256 and 512 point
representations at 1x and 2x (up to 1024 pixels), rendered directly from the SVG.
The transparent rounded corners, warm orange tile and ivory toolbox are retained.

The PNGs are checked in, so normal app builds need no extra dependencies.
`scripts/build-app.sh` uses macOS `iconutil` to create
`Contents/Resources/AppIcon.icns` before signing, and sets `CFBundleIconFile`.
This does not change the monochrome menu-bar symbol or enable a Dock icon.

## Regenerate after editing the SVG

Use Python 3.9+ in a virtual environment with CairoSVG 2.8.2 installed
(`python3 -m pip install CairoSVG==2.8.2`; CairoSVG also requires system Cairo).
From the repository root:

```sh
python3 scripts/generate-app-icon.py
python3 -m unittest discover -s tests -v
```

Inspect the 16px and 32px PNGs at native size, on light and dark backgrounds;
confirm the handle, toolbox body and central latch remain distinguishable.
The seam may be subtle at 16px; do not redraw the selected geometry just to
make that detail heavier.

## Review screenshots

The [desktop preview](previews/desktop.png) and [mobile preview](previews/mobile.png)
show the checked-in PNGs at native 256, 16, 32 and 64 pixel sizes against light
and dark backgrounds. Open [the preview page](previews/index.html) locally to
inspect the artwork without GitHub scaling the screenshot to fit its page.
These are **browser-rendered artwork screenshots**, not screenshots of the
installed app, Finder, Get Info or the Dock. No icon artwork or website is changed
by this preview page.

To reproduce, install development-only `playwright-core@1.52.0` and a compatible
Firefox browser outside the repository. Run from the repository root, pointing
`NODE_PATH` at that installation's `node_modules` and `ICON_PREVIEW_BROWSER` at
the Firefox executable (omit the latter for Playwright's installed Firefox):

```sh
NODE_PATH=/path/to/node_modules ICON_PREVIEW_BROWSER=/path/to/firefox \
  node scripts/capture-icon-previews.cjs
```

The committed screenshots were captured on Linux using Playwright Core 1.52.0
with `/opt/camoufox/camoufox`, at a 1100×740 desktop viewport and a 390×844 mobile
viewport, full-page, with device scale factor 1. Fonts/browser versions can
change text rendering. The capture script verifies that all eight images decode
and display at native dimensions with no horizontal overflow before saving.
No Node/browser dependencies are needed for app builds or the portable tests.

## Verify on an authorized macOS machine

```sh
scripts/build-app.sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "dist/Mac Tools.app/Contents/Info.plist"
iconutil --convert iconset "dist/Mac Tools.app/Contents/Resources/AppIcon.icns" --output /tmp/MacTools-verified.iconset
codesign --verify --deep --strict "dist/Mac Tools.app"
```

Use a fresh output path for the extracted iconset. Check that the plist names
`AppIcon.icns`, the extracted PNG sizes match the checked-in iconset, and Finder
and Get Info show the orange toolbox on the built app (and the unzipped release).
Linux asset checks and mocked packaging tests do **not** verify macOS icon
compilation, signing or Finder display. There is currently no macOS CI workflow.
