# MP4Flow website maintenance

[Documentation index](README.md) · [Development](DEVELOPMENT.md)

## Source and public URLs

The existing GitHub Pages site stays at <https://ixiehao.github.io/MP4Flow/>.

| Language | Path |
| --- | --- |
| 简体中文 | `/MP4Flow/` |
| English | `/MP4Flow/en/` |
| Français | `/MP4Flow/fr/` |
| Русский | `/MP4Flow/ru/` |
| Español | `/MP4Flow/es/` |
| 日本語 | `/MP4Flow/ja/` |
| 한국어 | `/MP4Flow/ko/` |

- `website/index.html` is the shared template; `website/locales/*.json` contains all public copy, accessible labels and metadata.
- `Scripts/build-website.mjs` uses Node.js standard libraries to generate `_site/`. No framework, package install or runtime translation request is required.
- Each generated page contains its full translation, canonical URL, reciprocal `hreflang` links, share metadata and structured data. The build also creates the seven-page sitemap.
- Existing `?lang=en`, `?lang=ja` and other supported language links redirect to the corresponding page, preserving the section and other query parameters. Explicit page URLs take priority over browser language or old preferences.
- Language links work without JavaScript. The installation guide has a no-script fallback.

Keep copy short and product-focused. Do not put implementation notes, language ordering or test results into marketing text. Maintain the same spacing rules across languages; allow natural text wrapping instead of hiding overflow or shrinking individual translations.

## Images, icons and fonts

- Hero images `mp4flow-v130-*.jpg` are real captures of the corresponding v1.3.0 App interface, using a synthetic sample video. Capture bytes are JPEG, despite the screenshot API not specifying an extension. Keep the actual format and filename consistent.
- Previously hand-edited screenshots remain in `website/assets/` for existing references. Do not overwrite them when refreshing hero images.
- UI icons use the local `website/assets/tabler-icons.svg` sprite. Paths are copied unchanged from the App's curated Tabler Icons Outline v3.49.0 set in `Sources/FastConvert/Resources/TablerOutline/`.
- The product logo and favicon use the real App artwork. Font rendering uses the operating system's fonts; no webfont files are bundled or downloaded.
- Attribution and MIT terms: [`AppResources/ASSET_NOTICES.md`](../AppResources/ASSET_NOTICES.md).

## Preview and checks

Run from the repository root with Node.js 20+:

```sh
node --check website/app.js
node --test Scripts/tests/website.test.mjs
node Scripts/build-website.mjs
python3 -m http.server 8000 --bind 127.0.0.1 --directory _site
```

Open <http://127.0.0.1:8000/>. Rebuild and reload after editing the template, translations or assets. Do not serve the template directory directly.

The automated checks validate translation parity, seven static routes, metadata, sitemap alternates, local links, anchors, icon IDs and distinct localized screenshots. They also prevent publishing source catalogs and scripts. Test layout and interactions in an actual browser: all seven languages at 320, 390, 768, 1024 and 1440 px, language switching with section links, keyboard focus/Escape, installation dialogs, and official download links. Store screenshots and QA logs under ignored `dist/`, not in the published site.

## Deployment

[The Pages workflow](../.github/workflows/deploy-pages.yml) validates and builds the site, then uploads **`_site/`**, never the template directory. It runs on relevant `main` changes and supports manual dispatch. The required CI `build` job also validates the website before merge.

Use the repository's protected-branch PR flow. After deployment, verify the public seven-language pages, screenshots, stylesheet, sitemap and legacy links. A passing local preview does not confirm that GitHub Pages has updated.
