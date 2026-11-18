"""Portable asset and bundle-wiring checks; not a macOS build/signing test."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "assets/AppIcon.iconset"


class IconAssetsTests(unittest.TestCase):
    def test_standard_iconset_has_valid_rgba_pngs_at_every_size(self):
        expected = {
            f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png": points * scale
            for points in (16, 32, 128, 256, 512)
            for scale in (1, 2)
        }
        self.assertEqual({p.name for p in ICONSET.iterdir()}, set(expected))
        for name, size in expected.items():
            with self.subTest(name=name):
                data = (ICONSET / name).read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                offset, pixels, chunks = 8, b"", []
                while offset < len(data):
                    length = struct.unpack_from(">I", data, offset)[0]
                    kind = data[offset + 4:offset + 8]
                    payload = data[offset + 8:offset + 8 + length]
                    crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
                    self.assertEqual(zlib.crc32(kind + payload), crc)
                    chunks.append(kind)
                    if kind == b"IHDR":
                        # 8-bit RGBA, standard compression/filtering, non-interlaced.
                        self.assertEqual(struct.unpack(">IIBBBBB", payload),
                                         (size, size, 8, 6, 0, 0, 0))
                    elif kind == b"IDAT":
                        pixels += payload
                    offset += length + 12
                self.assertEqual(offset, len(data))
                self.assertEqual(chunks[0], b"IHDR")
                self.assertEqual(chunks[-1], b"IEND")
                self.assertEqual(len(zlib.decompress(pixels)), size * (1 + 4 * size))

    def test_equal_pixel_sizes_have_identical_artwork(self):
        for first, second in (("16x16@2x", "32x32"),
                              ("128x128@2x", "256x256"),
                              ("256x256@2x", "512x512")):
            self.assertEqual((ICONSET / f"icon_{first}.png").read_bytes(),
                             (ICONSET / f"icon_{second}.png").read_bytes())


# These stubs exercise the real bundle script without implying that Swift,
# iconutil or codesign ran. Each invocation is recorded for ordering assertions.
MOCK_TOOL = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

name, args = Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([name, args]) + "\n")
if name == "swift" and "--show-bin-path" in args:
    print(os.environ["MOCK_BIN"])
elif name == "iconutil":
    assert args[:3] == ["--convert", "icns", "assets/AppIcon.iconset"]
    assert args[3] == "--output"
    assert len(list(Path(args[2]).glob("*.png"))) == 10
    if os.environ.get("FAIL_ICONUTIL"):
        sys.exit(42)
    Path(args[4]).write_bytes(b"mock icon, NOT a real icns file")
elif name == "codesign":
    app = Path(args[-1])
    assert (app / "Contents/Resources/AppIcon.icns").is_file()
    assert (app / "Contents/Info.plist").is_file()
elif name == "ditto":
    Path(args[-1]).write_bytes(b"mock zip, NOT a release")
'''


class BundleWiringTests(unittest.TestCase):
    def run_bundle_script(self, work, fail_iconutil=False):
        project = work / "project"
        project.mkdir()
        for name in ("scripts", "assets", "tools"):
            shutil.copytree(ROOT / name, project / name)
        shutil.copy(ROOT / "VERSION", project / "VERSION")
        tools, binary = work / "mock-tools", work / "mock-bin"
        tools.mkdir()
        binary.mkdir()
        (binary / "MacTools").write_bytes(b"mock executable")
        driver = tools / "mock-tool"
        driver.write_text(MOCK_TOOL)
        driver.chmod(0o755)
        for name in ("swift", "iconutil", "codesign", "xattr", "ditto"):
            (tools / name).symlink_to(driver)
        log = work / "calls.jsonl"
        env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                   CALL_LOG=str(log), MOCK_BIN=str(binary))
        if fail_iconutil:
            env["FAIL_ICONUTIL"] = "1"
        result = subprocess.run(["bash", "scripts/build-app.sh"], cwd=project,
                                env=env, capture_output=True, text=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        return result, project / "dist/Mac Tools.app", calls

    def test_bundle_references_icon_and_installs_it_before_signing(self):
        with tempfile.TemporaryDirectory() as directory:
            result, app, calls = self.run_bundle_script(Path(directory))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            with (app / "Contents/Info.plist").open("rb") as source:
                info = plistlib.load(source)
            self.assertEqual(info["CFBundleIconFile"], "AppIcon.icns")
            self.assertTrue((app / "Contents/Resources" / info["CFBundleIconFile"]).is_file())
            self.assertTrue(info["LSUIElement"])
            names = [name for name, args in calls]
            self.assertLess(names.index("iconutil"), names.index("codesign"))
            self.assertIn(["codesign", ["--verify", "--deep", "--strict", "dist/Mac Tools.app"]], calls)
            self.assertTrue(list(app.parent.glob("Mac-Tools-*.zip")))

    def test_icon_generation_failure_stops_before_signing_or_zipping(self):
        with tempfile.TemporaryDirectory() as directory:
            result, app, calls = self.run_bundle_script(Path(directory), fail_iconutil=True)
            self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
            self.assertFalse((app / "Contents/Resources/AppIcon.icns").exists())
            self.assertFalse({name for name, args in calls} & {"codesign", "ditto"})


if __name__ == "__main__":
    unittest.main()
