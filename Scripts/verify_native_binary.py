#!/usr/bin/env python3
"""Verify one native CPU slice, deployment target and matching crash symbols."""
import argparse
from pathlib import Path
import re
import subprocess

from build_contract import ARCHITECTURES, MINIMUM_MACOS


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def verify(binary, architecture, symbols=None):
    if architecture not in ARCHITECTURES:
        raise ValueError("Choose arm64 or x86_64")
    actual = set(output("xcrun", "lipo", "-archs", str(binary)).split())
    if actual != {architecture}:
        raise ValueError(f"Expected only {architecture}; found {sorted(actual)}")
    commands = output("xcrun", "otool", "-l", str(binary))
    builds = [block for block in re.split(r"\nLoad command \d+\n", commands)
              if re.search(r"\bcmd LC_(?:BUILD_VERSION|VERSION_MIN_MACOSX)\b", block)]
    if len(builds) != 1:
        raise ValueError("Expected one macOS deployment load command")
    build = builds[0]
    if "LC_BUILD_VERSION" in build:
        platform = re.search(r"\bplatform (\S+)", build)
        if platform is None or platform[1] not in {"1", "MACOS", "macos"}:
            raise ValueError("Mach-O must target macOS")
        minimum = re.search(r"\bminos (\S+)", build)
    else:
        minimum = re.search(r"\bversion (\S+)", build)
    if minimum is None or minimum[1] not in {MINIMUM_MACOS, "13.0.0"}:
        raise ValueError("Mach-O minimum must remain macOS 13.0")
    for line in output("xcrun", "otool", "-L", str(binary)).splitlines()[1:]:
        library = line.strip().split(" (", 1)[0]
        if not library.startswith(("/System/Library/", "/usr/lib/", "@rpath/")):
            raise ValueError(f"Unexpected non-system runtime dependency: {library}")
    if symbols is not None:
        def uuids(path):
            return set(re.findall(r"UUID: ([\w-]+) \(([^)]+)\)",
                                  output("xcrun", "dwarfdump", "--uuid", str(path))))
        binary_ids, symbol_ids = uuids(binary), uuids(symbols)
        if not binary_ids or binary_ids != symbol_ids or {cpu for _, cpu in binary_ids} != {architecture}:
            raise ValueError("The dSYM must match the shipped executable's UUID and architecture")


def verify_bundle(app, architecture, symbols=None):
    import plistlib
    app = Path(app)
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if info.get("LSMinimumSystemVersion") not in {MINIMUM_MACOS, "13.0.0"}:
        raise ValueError("App minimum must remain macOS 13.0")
    resources = app / "Contents/Resources"
    languages = {path.stem for path in resources.glob("*.lproj")}
    expected_languages = {"en", "zh-Hans", "fr", "ru", "es", "ja", "ko"}
    declared = info.get("CFBundleLocalizations", [])
    if languages != expected_languages or set(declared) != expected_languages or len(declared) != 7:
        raise ValueError("App metadata and seven bundled localizations must match")
    if any(not (resources / f"{language}.lproj/Localizable.strings").is_file() for language in languages):
        raise ValueError("Every language must contain its real catalog")
    if not any(list(bundle.rglob("TablerOutline/*.svg")) for bundle in resources.glob("*.bundle")):
        raise ValueError("Missing Tabler Outline resources")
    if not (resources / "ASSET_NOTICES.md").is_file():
        raise ValueError("Missing third-party asset notices")
    forbidden = {".ttf", ".otf", ".ttc", ".woff", ".woff2"}
    if any(path.suffix.lower() in forbidden or path.name in {"ffmpeg", "ffprobe"}
           for path in app.rglob("*") if path.is_file()):
        raise ValueError("Do not bundle fonts or a separate FFmpeg runtime")
    verify(app / "Contents/MacOS/MP4Flow", architecture, symbols)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=sorted(ARCHITECTURES), required=True)
    parser.add_argument("--symbols")
    parser.add_argument("--bundle", action="store_true")
    parser.add_argument("path")
    args = parser.parse_args()
    if args.bundle:
        verify_bundle(args.path, args.arch, args.symbols)
    else:
        verify(args.path, args.arch, args.symbols)
    print(f"Verified {args.arch}, macOS {MINIMUM_MACOS}" + (", matching dSYM" if args.symbols else ""))
