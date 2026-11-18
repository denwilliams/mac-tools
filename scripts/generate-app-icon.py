#!/usr/bin/env python3
"""Regenerate the macOS iconset from the selected SVG (requires CairoSVG 2.8.2)."""
from pathlib import Path

import cairosvg

ROOT = Path(__file__).resolve().parent.parent


def main():
    iconset = ROOT / "assets/AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "@2x" if scale == 2 else ""
            cairosvg.svg2png(
                url=str(ROOT / "assets/mac-tools-icon-01.svg"),
                write_to=str(iconset / f"icon_{points}x{points}{suffix}.png"),
                output_width=points * scale,
                output_height=points * scale,
            )


if __name__ == "__main__":
    main()
