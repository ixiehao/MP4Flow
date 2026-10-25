# App localization

The App supports English (`en`), Simplified Chinese (`zh-Hans`), French (`fr`), Russian (`ru`), Spanish (`es`), Japanese (`ja`) and Korean (`ko`). Website, README and release translations are maintained separately; adding an App language does not imply those surfaces are translated.

On first use, MP4Flow chooses the first supported language in the user's macOS preference list, matching regional variants such as `fr-CA` and `es-MX`. Unsupported preferences fall back to English. Chinese preferences use the existing Simplified Chinese catalog. The menu-bar Language menu uses native language names and persists explicit choices without changing macOS preferences or resetting the queue.

## Resource contract

- Keep `AppLanguage`, `CFBundleLocalizations`, and `AppResources/*.lproj` in sync. Packaging copies every catalog; never add a menu language without shipping its resources.
- All catalogs contain the same keys. Existing Chinese source keys remain stable even when display copy is improved. English is the explicit fallback for a missing translation; missing keys must still fail validation before delivery.
- Stable `menu.*` format keys declare their argument contract in the validator; other source keys retain their sentence-based contract.
- Preserve printf argument types and positions, literal `%%`, line breaks, commands and product/codec names. Reordered arguments must use positional specifiers consistently.
- Use concise, natural labels. Recovery guidance must name the actual localized menu item. Distinguish temporal trimming from spatial cropping and preserve warnings about tracks, subtitles, HDR and metadata.
- Use count-neutral labels where a single string must cover zero, one and multiple items. Do not add English `(s)` suffixes or assume Russian count rules match English.
- Store media facts and structured failures, then localize at display time. File sizes and operation lists use the selected language; timecodes, filenames and FFmpeg numeric arguments retain their technical representation.
- Keep shared layout rules across languages. Keep the footer in one row: its summary yields width to actions, with shared insets and button padding. Compact configuration triggers stay on one line; full menu options and explanatory hints may wrap, with hover text available. Use native system fonts; no new font files are required.

## Validation

```sh
./Scripts/validate-localizations.sh
python3 -m unittest discover -s Scripts/tests -v
swift test --filter AppLanguageTests
./Scripts/build-app.sh
```

The Swift tests load the actual catalogs explicitly, exercise formatted messages, regional selection, fallback and live file-size localization. XCTest's main bundle alone does not contain the installed App resources and can misleadingly return source keys.

Test the packaged App in every language, including its minimum window width, preset menu, dependency dialog, trim/crop editor, queue actions, failure recovery, Help and update settings. Switch language with a populated queue and retained warnings; verify the queue and edits remain intact. Check language persistence after relaunch. The menu-bar Language menu is the only language selector, with English first and a persisted selection. The main header reserves its flexible width for the localized title and privacy subtitle. Common native menu headings and commands relabel in place using public roles/actions, retaining their targets, shortcuts and validation. The initially empty View placeholder has a narrow exact-caption fallback using shipped native translations. Verify accessibility titles too: macOS 27 SwiftUI can ignore the modern title setter, so a cached per-item public compatibility override is used only when needed. Native validation can reset an item after localization: invalidate the AX attempt cache when its display title changes, and include the notified menu copies in the deferred refresh. Dynamic Undo action names, service-provider entries and system file-dialog chrome remain system-owned; do not rewrite unknown native commands or macOS language preferences.

Arabic is intentionally outside the current scope. Supporting it later requires a separate right-to-left design and media-coordinate regression pass; a translated catalog alone is insufficient.
