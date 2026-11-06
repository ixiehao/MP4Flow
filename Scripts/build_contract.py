#!/usr/bin/env python3
"""Shared fail-closed contracts for local app and installer builds."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from datetime import datetime, timezone

ARCHITECTURES = {"arm64", "x86_64"}
MINIMUM_MACOS = "13.0"


def metadata(project):
    with (Path(project) / "AppResources/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    for field in ("CFBundleShortVersionString", "CFBundleVersion"):
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", str(info.get(field, ""))):
            raise ValueError(f"Missing or invalid {field}")
    if info.get("LSMinimumSystemVersion") not in {MINIMUM_MACOS, "13.0.0"}:
        raise ValueError("The bundle and build must both target macOS 13.0")
    return info


def app_destination(project, destination):
    """Never remove or replace an app, including a dangling symlink."""
    project = Path(project).resolve()
    destination = Path(os.path.abspath(destination))
    if destination.suffix != ".app" or os.path.lexists(destination):
        raise ValueError("APP_OUTPUT_PATH must name a new .app bundle")
    parent = destination.parent.resolve()
    allowed = (project, Path(tempfile.gettempdir()).resolve())
    if not any(parent == root or root in parent.parents for root in allowed):
        raise ValueError("App output must be inside this project or the temporary build directory")
    return parent / destination.name


def publish_directory(source, destination):
    """Darwin RENAME_EXCL publishes a verified group without replacement."""
    source, destination = Path(source), Path(destination)
    if source.is_symlink() or not source.is_dir():
        raise ValueError("Publication requires an owned staging directory")
    if source.stat().st_dev != destination.parent.stat().st_dev:
        raise ValueError("Atomic publication requires staging on the destination filesystem")
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(os.fsencode(source), os.fsencode(destination), 4) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def source_identity(project):
    """Source bytes, including new local files; no personal paths."""
    paths = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=project
    ).split(b"\0")
    digest = hashlib.sha256()
    for raw in sorted(p for p in paths if p):
        path = Path(project) / os.fsdecode(raw)
        digest.update(raw + b"\0")
        digest.update(path.read_bytes() if path.is_file() else b"<deleted>")
        digest.update(b"\0")
    return digest.hexdigest()


def write_provenance(project, architecture, output):
    info = metadata(project)
    record = {
        "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
        "architecture": architecture, "minimum_macos": MINIMUM_MACOS,
        "source_commit": command("git", "-C", str(project), "rev-parse", "HEAD"),
        "source_tree": command("git", "-C", str(project), "rev-parse", "HEAD^{tree}"),
        "source_dirty": bool(command("git", "-C", str(project), "status", "--porcelain")),
        "workspace_source_sha256": source_identity(project),
        "built_at": datetime.now(timezone.utc).isoformat(),
        "host_architecture": command("uname", "-m"), "host_macos": command("sw_vers", "-productVersion"),
        "sdk": command("xcrun", "--sdk", "macosx", "--show-sdk-version"),
        "xcode": command("xcodebuild", "-version"), "swift": command("swift", "--version"),
        "signing": "ad-hoc", "notarized": False,
    }
    Path(output).write_text(json.dumps(record, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    meta = commands.add_parser("metadata")
    meta.add_argument("project")
    meta.add_argument("field")
    app = commands.add_parser("app-destination")
    app.add_argument("project")
    app.add_argument("destination")
    publish = commands.add_parser("publish")
    publish.add_argument("source")
    publish.add_argument("destination")
    identity = commands.add_parser("source-identity")
    identity.add_argument("project")
    provenance = commands.add_parser("provenance")
    provenance.add_argument("project")
    provenance.add_argument("architecture", choices=sorted(ARCHITECTURES))
    provenance.add_argument("output")
    args = parser.parse_args()
    if args.action == "metadata":
        print(metadata(args.project)[args.field])
    elif args.action == "app-destination":
        print(app_destination(args.project, args.destination))
    elif args.action == "publish":
        publish_directory(args.source, args.destination)
    elif args.action == "source-identity":
        print(source_identity(args.project))
    else:
        write_provenance(args.project, args.architecture, args.output)


if __name__ == "__main__":
    main()
