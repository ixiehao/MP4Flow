# Native platforms and future macOS readiness

MP4Flow builds Apple Silicon and Intel separately from one shared codebase. Both target **macOS 13.0+**. Packaging verifies the Mach-O minimum as well as `Info.plist`; building on a newer macOS does not change this contract.

| Area | Apple Silicon (`arm64`) | Intel (`x86_64`) |
| --- | --- | --- |
| Conversion, merge and editing | Shared media planning, quality and validation | Same rules and quality |
| VideoToolbox acceleration | Probe actual local support; bounded software fallback | Probe actual local support; bounded software fallback |
| Optional native Smart Enhance | Requires supported macOS 27+ API, SDK and device | Explicitly unavailable; ordinary conversion remains available |
| Preferred Homebrew installation | `/opt/homebrew` | `/usr/local` |
| CI host | `macos-15` | `macos-26-intel` |

Executable discovery selects a complete FFmpeg/ffprobe pair within one installation, including optional keg-only `ffmpeg-full`. It never borrows a probe from another distribution. The current architecture determines search order, not codec capability; the installed tools and real encoder sessions determine that.

## Preparing for macOS 28

Apple documents general-purpose Rosetta support through macOS 27, with only a limited games-oriented subset afterwards. The Apple Silicon installer therefore contains native arm64 code and must not depend on an Intel-only helper. The separately installed media tools must also remain runnable on the target system. See [Apple's Rosetta guidance](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment).

Keep platform-specific framework implementation behind compile-time architecture and SDK checks, with runtime availability and capability checks. Preserve one shared export/error contract; do not maintain two copies of queue, geometry, audio or quality logic. An Intel hardware failure must not silently change an explicitly chosen codec.

This is preparation, **not a claim that macOS 28 has been tested**. Before claiming support after a new SDK/system becomes available:

1. Compile each native target with complete Swift concurrency checking; review newly deprecated APIs rather than suppressing diagnostics globally.
2. Run the media matrix on real Apple Silicon and supported Intel systems. Cover no-hardware fallback, HEVC, VFR, multi-audio, subtitles, HDR decisions, aspect, rotation, brightness, first-frame preview, cancellation and recovery.
3. Validate cold-start editors, repeated mode changes, menu accessibility and seven-language narrow layouts on the actual new system.
4. Remount both installers, verify CPU/minimum/symbol UUIDs and resources, and exercise a copied final app. Check Gatekeeper on a clean machine; ad-hoc signing is not notarization.
5. Record SDK compilation, cross-compilation, Rosetta execution, virtual CI and physical hardware results separately. Keep future-system and physical-hardware gaps explicit.

Two legacy menu accessibility overrides are retained as a bounded compatibility fallback after the modern setter; removing them merely to hide a deprecation warning can regress translated VoiceOver titles. Recheck their behavior when a new macOS is available.
