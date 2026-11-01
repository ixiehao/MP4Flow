# Demonstration media and screenshots

## Tears of Steel

The current website, seven READMEs and social card show excerpts from
**Tears of Steel (2012)** inside the real MP4Flow application.

**(CC) Blender Foundation | [mango.blender.org](https://mango.blender.org/)**

- Licence: [Creative Commons Attribution 3.0 Unported (CC BY 3.0)](https://creativecommons.org/licenses/by/3.0/).
- Official permission and attribution: [Mango sharing page](https://mango.blender.org/sharing/).
- Film source: [official 720p movie](https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov).
- English subtitle source: [official TOS-en.srt](https://download.blender.org/demo/movies/ToS/subtitles/TOS-en.srt), by the film project and its volunteer translators.

Film excerpts were trimmed and transcoded for demonstration. The crop and
image-adjustment examples were produced in MP4Flow. The aspect example uses
a deliberately stretched derivative, then restores its original **640:267**
display ratio through the application's custom-ratio controls. These are
interface demonstrations, not before/after quality benchmarks.

Only still application screenshots and the social card are published here.
The film, audio and subtitle files are not included in the repository or app.
The separately distributed original soundtrack has its own licence; it is
not redistributed with these assets.

The film remains under CC BY 3.0; MP4Flow's MIT licence does not replace its
licence. The film's creators, actors and sponsors do not endorse MP4Flow.
Their logos, trademarks and personality rights are not granted by the film
licence.

## Capture provenance

- App: **MP4Flow 1.5.0**, release source
  [`3ba503f`](https://github.com/ixiehao/MP4Flow/commit/3ba503f071fed188a19a17121c44618c9a5054a4).
- Captured on 1 November 2026 in a separate test application identity, with
  the same application code as the published release. Production media,
  preferences and queue were not used or changed.
- Six states in **all seven interface languages**: conversion queue, export
  settings, trim, crop, aspect correction and image adjustments.
- `website/assets/mp4flow-v150-{state}-{language}.jpg` are actual native-window
  captures. UI text, selected options, film frames and progress were not
  painted over or generated. The empty top 60 pixels of the main-window
  capture were removed to omit macOS window chrome and its sharing indicator;
  all other windows retain their complete content. Images were resized and
  JPEG-compressed for the web.
- [`website/screenshots.json`](../website/screenshots.json) records exact image
  dimensions and SHA-256 hashes. Originals and local capture records remain
  outside the published site.

Prepare a fresh set of captured windows on macOS with:

```sh
swift Scripts/prepare-website-screenshots.swift \
  /path/to/raw-captures website/assets website/screenshots.json
swift Scripts/create-social-preview.swift \
  website/assets/mp4flow-app-icon.png \
  website/assets/mp4flow-v150-crop-en.jpg website/assets/social-preview.jpg
```

The social card uses the **actual English crop window**, an original MP4Flow
layout and system fonts. It retains the full window proportions and includes
the film attribution and licence URL in the image. The website and READMEs
also provide clickable film and licence credits.

Older manually edited captures are retained for existing links; current
README, hero, feature and share metadata all reference the new assets.
