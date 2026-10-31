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

## Feature content and layout

Present eight features in the same order in all seven locales and READMEs: Smart Convert, Merge Clips, Trim, Crop, Rotate, Aspect Correction, Brighten Video, Light Denoise. Keep the two conversion/merge cards together, followed by six editing cards (three columns on desktop, two on tablet, one on mobile). Avoid numbered feature decorations and full-width leftover cards.

Brightness and denoise are separate feature descriptions but share the App's **Edit Video → Image Adjustments** panel. Explain that edits must be applied before starting conversion. Image adjustments re-encode SDR video; HDR is unsupported, and optional light denoise is off by default and may soften details. Merging uses unedited waiting clips in queue order: compatible inputs can be copied directly; Compatible Merge re-encodes mismatched formats. Do not claim that every merge is lossless.

## Images, icons and fonts

- Hero images `mp4flow-v130-*.jpg` are real captures of the corresponding v1.3.0 App interface, using a synthetic sample video. Capture bytes are JPEG, despite the screenshot API not specifying an extension. Keep the actual format and filename consistent.
- Previously hand-edited screenshots remain in `website/assets/` for existing references. Do not overwrite them when refreshing hero images.
- UI icons use the local `website/assets/tabler-icons.svg` sprite. Shared paths are copied unchanged from the App's curated Tabler Icons Outline v3.49.0 set in `Sources/FastConvert/Resources/TablerOutline/`. Website-only icons (`arrows-join`, `wave-sine`, `brand-github`) come unchanged from the same upstream release.
- The product logo and favicon use the real App artwork. Font rendering uses the operating system's fonts; no webfont files are bundled or downloaded.
- Header/footer logos and favicon use the 128px PNG embedded in `AppResources/AppIcon.icns`; the touch icon uses its 256px PNG. Extract existing assets with `iconutil`, without regenerating or overwriting the original 1024px artwork. Tests compare these small PNGs with the bytes embedded in the App icon and guard their file sizes.
- Attribution and MIT terms: [`AppResources/ASSET_NOTICES.md`](../AppResources/ASSET_NOTICES.md).

## Search content and metadata

The October 2026 copy review used official product pages for [HandBrake](https://handbrake.fr/), [Shutter Encoder](https://www.shutterencoder.com/) and [Permute](https://software.charliemonroe.net/permute/). Apply the useful pattern—state the task, platform, common formats and starting steps clearly—without copying their copy or claiming their capabilities.

- Each language has its own descriptive MP4/Mac title and natural summary. Keep the established headline; use the visible category and format line to explain the product. Avoid keyword lists, hidden SEO text and arbitrary character limits presented as search-engine rules. See Google's [title](https://developers.google.com/search/docs/appearance/title-link) and [snippet](https://developers.google.com/search/docs/appearance/snippet) guidance.
- The four native HTML disclosures answer real questions about formats, local/free processing, file size/quality and installation. Answers are in the initial HTML, usable without runtime translation, and reachable through the footer. Format support depends on codecs and the installed FFmpeg build. Never promise universally lossless conversion or smaller output.
- Keep canonical, reciprocal `hreflang`, localized sharing metadata and the seven-route sitemap consistent. Do not replace stable locale URLs with browser-language-only pages. Do not invent sitemap modification dates just to imply freshness. See [localized-page guidance](https://developers.google.com/search/docs/specialty/international/localized-versions).
- `SoftwareApplication` describes the multimedia app, actual dependencies/architectures, original icon and matching localized screenshot. Basic schema validity does not establish eligibility for Google's software rich result: its [requirements](https://developers.google.com/search/docs/appearance/structured-data/software-app) include a real rating or review. Do not fabricate those fields. The screenshot is an image, not a `VideoObject`; Google [retired FAQ rich results in May 2026](https://developers.google.com/search/updates), so the useful FAQ needs no rich-result promise or extra `FAQPage` markup.
- Robots rules belong at **`https://ixiehao.github.io/robots.txt`**, managed by the host-root project. The copy at `/MP4Flow/robots.txt` does not control crawling. A root 404 is not a crawl prohibition; check the real root response and do not mistake project-file existence for an effective rule. Preserve other projects' policies when root rules are maintained. See Google's [location rules](https://developers.google.com/crawling/docs/robots-txt/create-robots-txt) and [HTTP handling](https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec).

After publication, read back all locale HTML, shared assets and sitemap; verify the latest-release redirect. Search-engine discovery/indexing and ranking require subsequent crawling and measurement. Do not report Search Console submission, rich-result eligibility, ranking improvements or Core Web Vitals scores without actually verifying them.

## Preview and checks

Run from the repository root with Node.js 20+:

```sh
node --check website/app.js
node --test Scripts/tests/website.test.mjs
node Scripts/build-website.mjs
python3 -m http.server 8000 --bind 127.0.0.1 --directory _site
```

Open <http://127.0.0.1:8000/>. Rebuild and reload after editing the template, translations or assets. Do not serve the template directory directly.

The automated checks validate translation parity, seven static routes, search metadata, initial-HTML FAQ answers, schema facts, sitemap alternates, local links, anchors, icon IDs and distinct localized screenshots. They also prevent publishing source catalogs and scripts. Test layout and interactions in an actual browser: all seven languages at 320, 390, 768, 1024 and 1440 px, closed/expanded FAQ, keyboard Enter/Space, language switching with section links, focus/Escape, installation dialogs, and official download links. Store screenshots and QA logs under ignored `dist/`, not in the published site.

## Deployment

[The Pages workflow](../.github/workflows/deploy-pages.yml) validates and builds the site, then uploads **`_site/`**, never the template directory. It runs on relevant `main` changes and supports manual dispatch. The required CI `build` job also validates the website before merge.

Use the repository's protected-branch PR flow. After deployment, verify the public seven-language pages, screenshots, stylesheet, sitemap and legacy links. A passing local preview does not confirm that GitHub Pages has updated.
