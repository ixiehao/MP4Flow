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

The feature section has one reading order, without a second screenshot menu or a repeated feature grid. Three concise summaries cover Smart Convert, Merge Clips and Queue Recovery. Four visual articles cover Trim, Crop & Rotate, Aspect Correction and Brightness & Denoise. One wider article explains Export Settings. Together these eight groups cover the same ten capabilities listed in the READMEs and structured data.

Every visual article places one description directly beside its matching localized App image. Images are static illustrations: no full-size link, zoom cursor, switching controls or explanatory “real screenshot” labels. Keep existing `#demo-*`, merge, aspect, adjustment and export anchors valid for previously shared links. All feature content is already present in the HTML and remains visible without JavaScript.

Brightness and denoise share the App's Edit Video panel. Mention live preview, optional light denoise, SDR re-encoding and possible softening once in that article. Crop and rotation share one explanation; preserve aspect ratio when describing rotation. Aspect Correction must state live preview and custom proportions. Merging works with unedited waiting clips: compatible inputs can be copied directly; Compatible Merge re-encodes mismatched formats. Export size is an estimate and can reduce quality; all audio tracks are kept by default. Do not claim universal lossless conversion.

Phone layouts show one visual article per row; wider screens use two columns. Keep image dimensions automatic with maximum bounds and a rounded mask on the actual image box, rather than clipping an object-fit letterbox. Use one film credit for the page in the footer. Do not repeat feature descriptions as tags, screenshot captions and another list.

The FAQ uses the same full-width, pale rounded panel as the surrounding sections. Place its heading beside the disclosure cards on desktop and above them on phones. Keep the native `details` controls, visible keyboard focus and a generous question hit area; long translations and expanded answers must remain inside their cards.

## Images, icons and fonts

- Current hero images are `mp4flow-v150-queue-*.jpg`; the feature articles use `mp4flow-v150-{crop,aspect,adjust,trim,export}-*.jpg`. These are real v1.5.0 native window captures using *Tears of Steel*, with a matching interface language for each page. Exact sizes and hashes are in `website/screenshots.json`; the builder uses those dimensions in HTML and schema.
- READMEs use the corresponding lossless WebP files under `docs/assets/readme/`, with transparent rounded corners baked into the asset because GitHub Markdown cannot rely on custom CSS. Generate them with `Scripts/prepare-readme-screenshots.swift`; preserve the JPEG sources and check the derivative manifest. Do not flatten the corners onto a white background, which leaves visible boxes in dark mode.
- Film attribution, CC BY 3.0 links and modification notes accompany the screenshots in every locale and README, and are embedded in the social card. Source, scope and capture provenance: [MEDIA-CREDITS.md](MEDIA-CREDITS.md). No film/audio/subtitle files are published.
- `Scripts/prepare-website-screenshots.swift` only crops empty main-window chrome, resizes and JPEG-encodes real captures. Do not paint UI or invent progress. `Scripts/create-social-preview.swift` preserves the complete English crop-window proportions. Use system fonts.
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

The automated checks validate translation parity, seven static routes, metadata, FAQ answers, schema facts, sitemap alternates, local resources and distinct localized images. They also require one heading per feature group, absence of the removed screenshot controls, and valid legacy image-section anchors. The builder derives stylesheet and script cache versions from their file contents.

Check all seven languages in a browser at phone, tablet and desktop sizes, including both sides of the 520/640/760/960 px breakpoints. Check full images, natural aspect ratios, rounded corners, heading uniqueness, primary action hit areas, installation dialogs, optional libass guidance, FAQ expansion, language menu Enter/Escape/focus behavior and shared `#demo-*` links. Verify the effective CSS viewport when browser zoom is active; do not assume the requested device-pixel width equals `innerWidth`. Record any screenshot-tool scaling limitation separately from actual page layout. Store QA screenshots and reports under ignored `dist/`.

## Deployment

[The Pages workflow](../.github/workflows/deploy-pages.yml) validates and builds the site, then uploads **`_site/`**, never the template directory. It runs on relevant `main` changes and supports manual dispatch. The required CI `build` job also validates the website before merge.

Use the repository's protected-branch PR flow. After deployment, verify the public seven-language pages, screenshots, stylesheet, sitemap and legacy links. A passing local preview does not confirm that GitHub Pages has updated.
