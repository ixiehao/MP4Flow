# MP4Flow website maintenance

[Documentation index](README.md) · [Development](DEVELOPMENT.md)

## Source and public URL

- Source: [`website/`](../website/), not the repository root or `docs/`.
- Public URL: https://ixiehao.github.io/MP4Flow/
- Deployment: [`.github/workflows/deploy-pages.yml`](../.github/workflows/deploy-pages.yml).
- Languages: English, Simplified Chinese and Japanese.

`website/` is a source directory, not part of the public URL. Keep the public address and existing external links unchanged.

## Interface icons

- Website UI icons use `website/assets/tabler-icons.svg`, a local SVG sprite with paths copied unchanged from the app's curated Tabler Icons Outline v3.49.0 set in `Sources/FastConvert/Resources/TablerOutline/`.
- Reference icons with `<use href="assets/tabler-icons.svg#icon-name">`; don't add hand-drawn UI glyphs or a second icon family. If a needed icon is not in the app's curated set, add and license it in both places.
- The MP4Flow brand mark and favicon are product artwork, not interface glyphs, so they remain the real app icon.
- Attribution and MIT terms are recorded in [`AppResources/ASSET_NOTICES.md`](../AppResources/ASSET_NOTICES.md).

## Local preview

Run from the repository root:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory website
```

Open <http://127.0.0.1:8000/>. Use HTTP rather than opening files directly, especially when testing fetched resources.

## Validation

```sh
node --check website/app.js
git diff --check
```

Check images, favicon, navigation, official download destinations, desktop and narrow layouts, keyboard focus, language switching, localized metadata and download/signing wording. Check canonical and share URLs, robots and sitemap where present. A path-only migration should preserve site content.

## Deployment

The workflow uploads `website/` and deploys it as the site root. It runs on relevant changes to `main` and supports manual dispatch. Pages should be configured to use **GitHub Actions**; moving the source directory must be accompanied by the matching workflow path update.

Only publish when authorized. After deployment, read the public URL back and verify resources, navigation and downloads. A successful local preview is not proof that the public site has updated.
