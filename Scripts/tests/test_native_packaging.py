"""Packaging contracts, including failure paths; no Swift build or real DMG."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import build_contract
import verify_native_binary

LANGUAGES = ["en", "zh-Hans", "fr", "ru", "es", "ja", "ko"]


def write_metadata(project, **updates):
    info = {
        "CFBundleShortVersionString": "1.5.0", "CFBundleVersion": "20",
        "LSMinimumSystemVersion": "13.0", "CFBundleLocalizations": LANGUAGES,
    }
    info.update(updates)
    resources = project / "AppResources"
    resources.mkdir(exist_ok=True)
    (resources / "Info.plist").write_bytes(plistlib.dumps(info))
    return info


class BuildContractTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="mp4flow-contract-")
        self.root = Path(self.scratch.name).resolve()
        self.project = self.root / "project"
        self.project.mkdir()
        write_metadata(self.project)

    def tearDown(self):
        self.scratch.cleanup()

    def test_metadata_rejects_unsafe_versions_and_changed_minimum(self):
        for fields in [
            {"CFBundleShortVersionString": "1.5.0/../../other"},
            {"CFBundleVersion": ""}, {"LSMinimumSystemVersion": "27.0"},
        ]:
            write_metadata(self.project, **fields)
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                build_contract.metadata(self.project)

    def test_app_preflight_preserves_existing_bundle_and_dangling_symlink(self):
        destination = self.project / "MP4Flow.app"
        destination.mkdir()
        marker = destination / "existing-user-build"
        marker.write_bytes(b"keep this build")
        with self.assertRaises(ValueError):
            build_contract.app_destination(self.project, destination)
        self.assertEqual(marker.read_bytes(), b"keep this build")
        shutil.rmtree(destination)
        destination.symlink_to(self.root / "nonexistent.app")
        with self.assertRaises(ValueError):
            build_contract.app_destination(self.project, destination)
        self.assertTrue(destination.is_symlink())

    def test_app_destination_resolves_ancestors_before_enforcing_boundary(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.project / "escape").symlink_to(outside, target_is_directory=True)
        with mock.patch.object(build_contract.tempfile, "gettempdir", return_value=str(self.root / "allowed-temp")):
            with self.assertRaises(ValueError):
                build_contract.app_destination(self.project, self.project / "escape/Build.app")
        self.assertFalse((outside / "Build.app").exists())

    def test_source_identity_includes_new_files_and_excludes_ignored_builds(self):
        subprocess.run(["git", "init", "-q", str(self.project)], check=True, capture_output=True)
        (self.project / ".gitignore").write_text(".build/\n")
        before = build_contract.source_identity(self.project)
        source = self.project / "NewSource.swift"
        source.write_text("let value = 1\n")
        with_new_source = build_contract.source_identity(self.project)
        self.assertNotEqual(before, with_new_source)
        cache = self.project / ".build"
        cache.mkdir()
        (cache / "binary").write_bytes(b"regenerable build product")
        self.assertEqual(with_new_source, build_contract.source_identity(self.project))
        source.write_text("let value = 2\n")
        self.assertNotEqual(with_new_source, build_contract.source_identity(self.project))

    @unittest.skipUnless(sys.platform == "darwin", "Darwin exclusive rename contract")
    def test_exclusive_publication_moves_verified_staging_on_same_volume(self):
        staging_parent = self.project / ".staging"
        staging_parent.mkdir()
        source = staging_parent / "MP4Flow.app"
        source.mkdir()
        (source / "verified").write_bytes(b"candidate")
        destination = self.project / "MP4Flow.app"
        build_contract.publish_directory(source, destination)
        self.assertFalse(source.exists())
        self.assertEqual((destination / "verified").read_bytes(), b"candidate")

    @unittest.skipUnless(sys.platform == "darwin", "Darwin exclusive rename contract")
    def test_exclusive_publication_refuses_destination_created_after_preflight(self):
        for kind in ["directory", "dangling-link"]:
            with self.subTest(kind=kind):
                source = self.project / (kind + ".stage")
                destination = self.project / (kind + ".app")
                source.mkdir()
                (source / "verified").write_bytes(b"candidate")
                self.assertEqual(build_contract.app_destination(self.project, destination), destination)
                if kind == "directory":
                    destination.mkdir()
                    (destination / "existing").write_bytes(b"do not replace")
                else:
                    destination.symlink_to(self.root / "missing")
                with self.assertRaises(OSError):
                    build_contract.publish_directory(source, destination)
                self.assertEqual((source / "verified").read_bytes(), b"candidate")
                if kind == "directory":
                    self.assertEqual((destination / "existing").read_bytes(), b"do not replace")
                    self.assertFalse((destination / "verified").exists())
                else:
                    self.assertTrue(destination.is_symlink())


class NativeBinaryContractTests(unittest.TestCase):
    def tools(self, architectures="arm64", minimum="13.0", platform="1", symbols=None, libraries=None, commands=None):
        identifiers = symbols or {}
        def result(*args):
            if args[1:3] == ("lipo", "-archs"):
                return architectures
            if args[1:3] == ("otool", "-l"):
                return commands or "Load command 0\n cmd LC_BUILD_VERSION\n cmdsize 32\n platform %s\n minos %s\n sdk 27.2\n" % (platform, minimum)
            if args[1:3] == ("otool", "-L"):
                return "binary:\n" + "\n".join("  %s (compatibility version 1.0.0, current version 1.0.0)" % value for value in (libraries or ["/usr/lib/libSystem.B.dylib", "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"]))
            if args[1:3] == ("dwarfdump", "--uuid"):
                return identifiers.get(args[-1], "UUID: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64) binary")
            raise AssertionError("Unexpected external tool call: %r" % (args,))
        return mock.patch.object(verify_native_binary, "output", side_effect=result)

    def test_native_slice_and_matching_symbols_are_accepted(self):
        for architecture in ["arm64", "x86_64"]:
            uuid = "UUID: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (%s) file" % architecture
            with self.subTest(architecture=architecture), self.tools(architectures=architecture, symbols={"binary": uuid, "symbols": uuid}):
                verify_native_binary.verify("binary", architecture, "symbols")

    def test_universal_and_wrong_native_slice_are_rejected(self):
        for actual in ["x86_64", "arm64 x86_64", "", "arm64 arm64e"]:
            with self.subTest(actual=actual), self.tools(architectures=actual), self.assertRaises(ValueError):
                verify_native_binary.verify("binary", "arm64")

    def test_changed_or_missing_macos_minimum_is_rejected(self):
        for minimum in ["12.0", "13.1", "27.0"]:
            with self.subTest(minimum=minimum), self.tools(minimum=minimum), self.assertRaises(ValueError):
                verify_native_binary.verify("binary", "arm64")
        with self.tools(commands="Load command 0\n cmd LC_UUID\n uuid ABC\n"), self.assertRaises(ValueError):
            verify_native_binary.verify("binary", "arm64")

    def test_ios_platform_or_cross_command_minimum_is_rejected(self):
        with self.tools(platform="2"), self.assertRaises(ValueError):
            verify_native_binary.verify("binary", "arm64")
        crossed = "Load command 0\n cmd LC_BUILD_VERSION\n platform 1\nLoad command 1\n cmd LC_OTHER\n minos 13.0\n"
        with self.tools(commands=crossed), self.assertRaises(ValueError):
            verify_native_binary.verify("binary", "arm64")

    def test_old_macos_load_command_remains_supported(self):
        legacy = "Load command 0\n cmd LC_VERSION_MIN_MACOSX\n cmdsize 16\n version 13.0\n sdk 13.3\n"
        with self.tools(commands=legacy):
            verify_native_binary.verify("binary", "arm64")

    def test_third_party_absolute_runtime_dependency_is_rejected(self):
        with self.tools(libraries=["/opt/homebrew/opt/ffmpeg/lib/libavcodec.dylib"]), self.assertRaises(ValueError):
            verify_native_binary.verify("binary", "arm64")

    def test_empty_wrong_uuid_or_wrong_symbol_architecture_is_rejected(self):
        for symbols in ["", "UUID: FFFFFFFF-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64) symbols", "UUID: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (x86_64) symbols"]:
            with self.subTest(symbols=symbols), self.tools(symbols={"symbols": symbols}), self.assertRaises(ValueError):
                verify_native_binary.verify("binary", "arm64", "symbols")

    def test_bundle_rejects_wrong_languages_missing_catalogs_and_bundled_fonts(self):
        with tempfile.TemporaryDirectory(prefix="mp4flow-bundle-contract-") as scratch:
            app = Path(scratch) / "MP4Flow.app"
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            info = {"LSMinimumSystemVersion": "13.0", "CFBundleLocalizations": LANGUAGES}
            plist = app / "Contents/Info.plist"
            plist.write_bytes(plistlib.dumps(info))
            (resources / "ASSET_NOTICES.md").write_text("MIT")
            icons = resources / "MP4Flow_FastConvert.bundle/TablerOutline"
            icons.mkdir(parents=True)
            (icons / "video.svg").write_text("<svg/>")
            for language in LANGUAGES:
                catalog = resources / (language + ".lproj/Localizable.strings")
                catalog.parent.mkdir()
                catalog.write_text('"key" = "value";')
            with mock.patch.object(verify_native_binary, "verify") as native:
                verify_native_binary.verify_bundle(app, "arm64")
                native.assert_called_once()
            (resources / "ja.lproj/Localizable.strings").unlink()
            with mock.patch.object(verify_native_binary, "verify"), self.assertRaises(ValueError):
                verify_native_binary.verify_bundle(app, "arm64")
            (resources / "ja.lproj/Localizable.strings").write_text('"key" = "value";')
            info["CFBundleLocalizations"] = LANGUAGES + ["en"]
            plist.write_bytes(plistlib.dumps(info))
            with mock.patch.object(verify_native_binary, "verify"), self.assertRaises(ValueError):
                verify_native_binary.verify_bundle(app, "arm64")
            info["CFBundleLocalizations"] = LANGUAGES
            plist.write_bytes(plistlib.dumps(info))
            (resources / "Unlicensed.ttf").write_bytes(b"font")
            with mock.patch.object(verify_native_binary, "verify"), self.assertRaises(ValueError):
                verify_native_binary.verify_bundle(app, "arm64")


class PackagingScriptFailureTests(unittest.TestCase):
    """Run real zsh scripts in a fake checkout with bounded, harmless tools."""
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="mp4flow-package-tests-")
        self.root = Path(self.scratch.name).resolve()
        self.project = self.root / "project"
        self.project.mkdir()
        scripts = self.project / "Scripts"
        scripts.mkdir()
        for name in ["build-app.sh", "package-dmg.sh", "build_contract.py", "verify_native_binary.py"]:
            shutil.copy2(SCRIPTS / name, scripts / name)
        write_metadata(self.project)
        self.bin = self.root / "tools"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        self.env = os.environ.copy()
        self.env.update({"PATH": str(self.bin) + os.pathsep + self.env.get("PATH", ""), "MP4FLOW_ARCH": "arm64", "APP_OUTPUT_PATH": str(self.project / "Candidate.app"), "QA_LOG": str(self.log), "QA_ROOT": str(self.root)})
        self.env.pop("MP4FLOW_ARCHS", None)
        self.env.pop("OUTPUT_DIR", None)
        self.stub("swift", """
import json, os, sys, time
with open(os.environ['QA_LOG'], 'a') as log: log.write(json.dumps(['swift'] + sys.argv[1:]) + '\\n')
if '--show-bin-path' in sys.argv:
    if os.environ.get('QA_BIN_FAILURE') == 'status': sys.exit(9)
    if os.environ.get('QA_BIN_FAILURE') == 'empty': sys.exit(0)
    print(os.environ.get('QA_BIN_DIR', ''))
elif os.environ.get('QA_HOLD'):
    open(os.environ['QA_HOLD'], 'w').write(str(os.getpid()))
    time.sleep(30)
""")
        # Even malformed mktemp output must never make a test mutate / or a
        # user directory. Log requests and reject every destination outside QA.
        for name in ["mkdir", "rm", "cp"]:
            self.stub(name, """
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ['QA_LOG'], 'a') as log: log.write(json.dumps([name] + sys.argv[1:]) + '\\n')
root = Path(os.environ['QA_ROOT']).resolve()
for value in sys.argv[1:]:
    if value.startswith('-'): continue
    path = Path(value).absolute()
    if root != path and root not in path.parents: sys.exit(98)
os.execv('/bin/' + name, [name] + sys.argv[1:])
""")
        self.built = self.root / "built"
        self.built.mkdir()
        (self.built / "MP4Flow").write_bytes(b"fake binary")
        self.env["QA_BIN_DIR"] = str(self.built)

    def tearDown(self):
        self.scratch.cleanup()

    def stub(self, name, source):
        path = self.bin / name
        path.write_text("#!" + sys.executable + "\n" + source)
        path.chmod(0o755)
        return path

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def run_script(self, name="build-app.sh", arguments=(), **environment):
        env = dict(self.env, **environment)
        return subprocess.run(["/bin/zsh", str(self.project / "Scripts" / name)] + list(arguments), cwd=self.root, env=env, capture_output=True, text=True, timeout=15)

    def test_architecture_group_cannot_create_a_universal_app(self):
        result = self.run_script(MP4FLOW_ARCH="arm64 x86_64")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(command[0] == "swift" for command in self.commands()))

    def test_existing_or_dangling_app_is_preserved_before_build(self):
        app = self.project / "Candidate.app"
        app.symlink_to(self.root / "missing.app")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(app.is_symlink())
        self.assertFalse(any(command[0] == "swift" for command in self.commands()))

    def test_failed_or_empty_mktemp_never_stages_at_root(self):
        for status in [0, 7]:
            with self.subTest(status=status):
                self.stub("mktemp", "import sys\nsys.exit(%d)\n" % status)
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(Path(self.env["APP_OUTPUT_PATH"]).exists())
                for command in self.commands():
                    if command[0] not in {"mkdir", "cp", "rm"}: continue
                    for value in command[1:]:
                        if not value.startswith("-"):
                            self.assertTrue(str(Path(value).absolute()).startswith(str(self.root) + os.sep), command)
                self.assertFalse((self.project / ".build/app-arm64.lock").exists())

    def test_failed_or_empty_binary_path_never_copies_root_executable(self):
        for failure in ["status", "empty"]:
            with self.subTest(failure=failure):
                result = self.run_script(QA_BIN_FAILURE=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(command[0] == "cp" for command in self.commands()))
                self.assertFalse(Path(self.env["APP_OUTPUT_PATH"]).exists())
                self.assertFalse((self.project / ".build/app-arm64.lock").exists())
                self.assertFalse(list(self.project.glob(".mp4flow-app.*")))

    def test_foreign_architecture_lock_is_not_deleted(self):
        lock = self.project / ".build/app-arm64.lock"
        lock.mkdir(parents=True)
        (lock / "pid").write_text("foreign-owner")
        result = self.run_script()
        self.assertEqual(result.returncode, 75)
        self.assertEqual((lock / "pid").read_text(), "foreign-owner")
        self.assertFalse(any(command[0] == "swift" for command in self.commands()))

    def test_term_cleans_only_its_owned_stage_and_lock(self):
        marker = self.root / "swift-started"
        env = dict(self.env, QA_HOLD=str(marker))
        process = subprocess.Popen(["/bin/zsh", str(self.project / "Scripts/build-app.sh")], cwd=self.root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while not marker.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(marker.exists(), "The owned fake build must start before sending TERM")
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=5)
            self.assertNotEqual(process.returncode, 0)
            self.assertFalse((self.project / ".build/app-arm64.lock").exists())
            self.assertFalse(list(self.project.glob(".mp4flow-app.*")))
            self.assertFalse(Path(self.env["APP_OUTPUT_PATH"]).exists())
            self.assertEqual((self.built / "MP4Flow").read_bytes(), b"fake binary")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)

    def test_relative_installer_output_is_relative_to_callers_working_directory(self):
        result = self.run_script("package-dmg.sh", ["--arch", "arm64", "--output-dir", "relative-output", "--preflight-only"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "relative-output").is_dir())
        self.assertFalse((self.project / "relative-output").exists())
        self.assertFalse(any(command[0] == "swift" for command in self.commands()))

    def test_environment_relative_output_and_all_architecture_preflight_preserve_existing_group(self):
        output = self.root / "environment-output"
        output.mkdir()
        intel = output / "MP4Flow-1.5.0-x86_64"
        intel.mkdir()
        (intel / "previous.dmg").write_bytes(b"stable release")
        result = self.run_script("package-dmg.sh", ["--preflight-only"], OUTPUT_DIR="environment-output")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((intel / "previous.dmg").read_bytes(), b"stable release")
        self.assertFalse((output / "MP4Flow-1.5.0-arm64").exists())
        self.assertFalse(any(command[0] == "swift" for command in self.commands()))

    def test_installer_lock_owned_by_another_process_is_preserved(self):
        lock = self.project / ".build/package-dmg.lock"
        lock.mkdir(parents=True)
        (lock / "pid").write_text("foreign-packager")
        result = self.run_script("package-dmg.sh", ["--arch", "arm64", "--output-dir", str(self.root / "installers")])
        self.assertEqual(result.returncode, 75)
        self.assertEqual((lock / "pid").read_text(), "foreign-packager")

    def test_installer_term_releases_both_owned_build_locks_and_stages(self):
        subprocess.run(["git", "init", "-q", str(self.project)], check=True, capture_output=True)
        (self.project / ".gitignore").write_text(".build/\n")
        packaging_python = self.stub("packaging-python", "import sys\nsys.exit(0)\n")
        marker = self.root / "installer-swift-started"
        output = self.root / "installers"
        env = dict(self.env, QA_HOLD=str(marker), PACKAGING_PYTHON=str(packaging_python))
        process = subprocess.Popen(["/bin/zsh", str(self.project / "Scripts/package-dmg.sh"), "--arch", "arm64", "--output-dir", str(output)], cwd=self.root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while not marker.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(marker.exists(), "The nested app build must start before cancelling its installer")
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=5)
            self.assertNotEqual(process.returncode, 0)
            self.assertFalse((self.project / ".build/package-dmg.lock").exists())
            self.assertFalse((self.project / ".build/app-arm64.lock").exists())
            self.assertFalse(list(output.glob(".mp4flow-*")))
            self.assertFalse((output / "MP4Flow-1.5.0-arm64").exists())
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)

    def test_existing_installer_group_and_dangling_link_are_preserved(self):
        output = self.root / "installers"
        output.mkdir()
        destination = output / "MP4Flow-1.5.0-arm64"
        destination.symlink_to(self.root / "missing-artifact")
        result = self.run_script("package-dmg.sh", ["--arch", "arm64", "--output-dir", str(output), "--preflight-only"])
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(destination.is_symlink())
        self.assertFalse(any(command[0] == "swift" for command in self.commands()))


if __name__ == "__main__":
    unittest.main()
