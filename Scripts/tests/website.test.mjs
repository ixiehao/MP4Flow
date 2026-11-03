import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm, stat } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createHash } from 'node:crypto';
import { buildSite, languages, localePath, readCatalogs, siteURL } from '../build-website.mjs';

test('seven canonical pages are complete, crawlable and use matching real screenshots', async t => {
  const output = await mkdtemp(path.join(os.tmpdir(), 'mp4flow-website-test-'));
  t.after(() => rm(output, { recursive: true, force: true }));
  await buildSite(output);
  const catalogs = await readCatalogs();
  const sprite = await readFile(path.join(output, 'assets/tabler-icons.svg'), 'utf8');
  const shots = new Set();
  const titles = new Set();
  const descriptions = new Set();
  for (const language of languages) {
    await t.test(language.id, async () => {
      const pageDir = path.join(output, localePath(language.id));
      const html = await readFile(path.join(pageDir, 'index.html'), 'utf8');
      assert.ok(html.includes(`lang="${language.locale}"`));
      assert.ok(html.includes(`<link rel="canonical" href="${siteURL}${localePath(language.id)}"`));
      assert.doesNotMatch(html, /\{\{|undefined|语言菜单中 English/);
      assert.equal((html.match(/<h1\b/g) ?? []).length, 1);
      const copy = catalogs[language.id];
      assert.ok(html.includes(`<title>${copy.pageTitle}</title>`));
      assert.match(copy.pageTitle, /MP4Flow.*MP4.*Mac|MP4Flow.*Mac.*MP4/);
      titles.add(copy.pageTitle);
      descriptions.add(copy.pageDescription);
      assert.ok(html.includes(copy.heroFormats));
      assert.doesNotMatch(html, /<meta name="keywords"/i);
      const faq = html.match(/<section class="faq-section"[^>]*>([\s\S]*?)<\/section>/)?.[1];
      assert.ok(faq, 'FAQ must be available in static HTML');
      assert.equal((faq.match(/<details>/g) ?? []).length, 4);
      for (const topic of ['Formats', 'Privacy', 'Quality', 'Setup']) {
        assert.ok(faq.includes(copy[`faq${topic}Q`]), `${language.id}: FAQ question ${topic}`);
        assert.ok(faq.includes(copy[`faq${topic}A`]), `${language.id}: FAQ answer ${topic}`);
      }
      assert.ok(faq.includes('data-install-guide'));
      assert.equal((html.match(/data-language="/g) ?? []).length, 8);
      assert.equal((html.match(/aria-current="page"/g) ?? []).length, 1);
      assert.equal((html.match(/<link rel="alternate" hreflang=/g) ?? []).length, 8);
      assert.ok(html.includes(catalogs[language.id].installTitle));
      assert.ok(html.includes('brew install ffmpeg'));
      const schema = JSON.parse(html.match(/id="software-schema"[^>]*>([\s\S]*?)<\/script>/)[1]);
      assert.deepEqual(schema.inLanguage, languages.map(l => l.locale));
      assert.equal(schema.url, siteURL + localePath(language.id));
      assert.equal(schema.description, catalogs[language.id].pageDescription);
      assert.equal(schema.applicationCategory, 'MultimediaApplication');
      assert.equal(schema.mainEntityOfPage, schema.url);
      assert.equal(schema.softwareRequirements, 'FFmpeg; ffprobe');
      assert.equal(schema.image, `${siteURL}assets/mp4flow-app-icon.png`);
      assert.equal(schema.screenshot.contentUrl, `${siteURL}assets/mp4flow-v150-queue-${language.id}.jpg`);
      assert.equal(schema.screenshot.isBasedOn.license, 'https://creativecommons.org/licenses/by/3.0/');
      assert.equal(schema.screenshot.inLanguage, language.locale);
      assert.equal(schema.screenshot.caption, copy.stageAlt);
      assert.ok(!('aggregateRating' in schema) && !('review' in schema), 'do not invent ratings for rich results');
      assert.doesNotMatch(html, /"@type":"FAQPage"|"@type":"VideoObject"/);
      assert.deepEqual(schema.featureList, ['toolOneTitle', 'mergeTitle', 'exportTitle', 'recoveryTitle', 'toolTwoTitle', 'toolThreeTitle', 'toolFourTitle', 'aspectTitle', 'brightenTitle', 'denoiseTitle'].map(key => catalogs[language.id][key]));
      const features = html.match(/<section class="tools-section"[\s\S]*?<section class="workflow"/)[0];
      const headings = [...features.matchAll(/<h3[^>]*>([\s\S]*?)<\/h3>/g)].map(match => match[1].replace(/<[^>]+>/g, '').replace(/&amp;|&lt;|&gt;|&quot;|&#39;/g, entity => ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'" })[entity]));
      for (const key of ['toolOneTitle', 'mergeTitle', 'recoveryTitle', 'toolTwoTitle', 'cropRotateTitle', 'aspectTitle', 'adjustTitle', 'exportTitle']) {
        assert.equal(headings.filter(title => title === copy[key]).length, 1, `${language.id}: ${key} has one introduction`);
      }
      assert.equal((features.match(/<h3[ >]/g) ?? []).length, 8, 'each feature group is introduced once');
      assert.doesNotMatch(html, /data-tour-tab|data-tour-panel|class="tour-|href="[^"]+\.jpg"/);
      assert.ok(!('tourLabel' in copy) && !('tourOpen' in copy) && !('tourHint' in copy), 'remove obsolete screenshot UI copy');
      assert.ok(html.includes('id="merge-clips"'));
      assert.ok(html.includes('id="image-adjustments"'));
      assert.ok(html.includes('id="light-denoise"'));
      assert.ok(html.includes(catalogs[language.id].adjustNote));
      assert.equal(schema.offers.price, '0');
      const image = html.match(/id="hero-app-screen" src="([^"]+)"/)[1];
      assert.ok(image.endsWith(`mp4flow-v150-queue-${language.id}.jpg`));
      const bytes = await readFile(path.resolve(pageDir, image));
      assert.equal(bytes.subarray(0, 3).toString('hex'), 'ffd8ff', 'valid JPEG capture');
      shots.add(bytes.toString('base64'));
      for (const state of ['crop', 'aspect', 'adjust', 'trim', 'export']) {
        assert.ok(features.includes(`id="demo-${state}"`), 'preserve existing shared feature links');
        assert.ok(features.includes(`mp4flow-v150-${state}-${language.id}.jpg`));
      }
      assert.equal((features.match(/loading="lazy"/g) ?? []).length, 5);
      assert.equal((html.match(/https:\/\/mango.blender.org\/">Tears of Steel/g) ?? []).length, 1);
      assert.ok(html.includes('https://creativecommons.org/licenses/by/3.0/'));
      // Every local navigation target, file and SVG fragment must resolve.
      for (const [, ref] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
        if (/^https?:/.test(ref)) continue;
        const [pathname, hash] = ref.split('#');
        if (!pathname) {
          assert.ok(html.includes(`id="${hash}"`), `missing anchor ${ref}`);
          continue;
        }
        const file = path.resolve(pageDir, pathname.split('?')[0]);
        assert.ok(file.startsWith(output + path.sep) || file === output);
        assert.ok(await stat(file), `missing resource ${ref}`);
        if (hash && pathname.includes('tabler-icons.svg')) assert.ok(sprite.includes(`id="${hash}"`));
      }
    });
  }
  assert.equal(shots.size, 7, 'each locale needs its own screenshot');
  assert.equal(titles.size, 7, 'localized search titles must be distinct');
  assert.equal(descriptions.size, 7, 'localized search descriptions must be distinct');
  await t.test('English is the static default and the old English URL remains valid', async () => {
    const english = await readFile(path.join(output, 'index.html'), 'utf8');
    const chinese = await readFile(path.join(output, 'zh/index.html'), 'utf8');
    const legacyEnglish = await readFile(path.join(output, 'en/index.html'), 'utf8');
    assert.ok(english.includes('<html data-language="en" data-root="./" lang="en">'));
    assert.ok(english.includes(`<title>${catalogs.en.pageTitle}</title>`));
    assert.ok(english.includes('hreflang="zh-CN" href="https://ixiehao.github.io/MP4Flow/zh/"'));
    assert.ok(chinese.includes('<html data-language="zh" data-root="../" lang="zh-CN">'));
    assert.ok(chinese.includes('rel="canonical" href="https://ixiehao.github.io/MP4Flow/zh/"'));
    assert.ok(legacyEnglish.includes('<html data-language="en" data-root="../" lang="en">'));
    assert.ok(legacyEnglish.includes('rel="canonical" href="https://ixiehao.github.io/MP4Flow/"'));
    assert.ok(legacyEnglish.includes('id="hero-app-screen" src="../assets/mp4flow-v150-queue-en.jpg"'));
    assert.ok(legacyEnglish.includes('href="../zh/" lang="zh-CN"'));
    const readme = await readFile(new URL('../../README.md', import.meta.url), 'utf8');
    const chineseReadme = await readFile(new URL('../../README.zh-CN.md', import.meta.url), 'utf8');
    assert.ok(readme.includes('[Website](https://ixiehao.github.io/MP4Flow/)'));
    assert.ok(chineseReadme.includes('[官方网站](https://ixiehao.github.io/MP4Flow/zh/)'));
  });
  const sitemap = await readFile(path.join(output, 'sitemap.xml'), 'utf8');
  assert.equal((sitemap.match(/<loc>/g) ?? []).length, 7);
  assert.equal((sitemap.match(/xhtml:link/g) ?? []).length, 56);
  assert.doesNotMatch(sitemap, /https:\/\/ixiehao.github.io\/MP4Flow\/en\//);
  assert.match(sitemap, /<loc>https:\/\/ixiehao.github.io\/MP4Flow\/zh\/<\/loc>/);
  await assert.rejects(stat(path.join(output, 'locales')));
  await assert.rejects(stat(path.join(output, 'Scripts')));
});

test('42 localized captures match their provenance and actual JPEG dimensions', async () => {
  const { screenshots, film, appVersion } = JSON.parse(await readFile(new URL('../../website/screenshots.json', import.meta.url)));
  assert.equal(appVersion, '1.5.0');
  assert.equal(film.license, 'CC BY 3.0');
  assert.deepEqual(Object.keys(screenshots).sort(), ['adjust', 'aspect', 'crop', 'export', 'queue', 'trim']);
  const dimensions = bytes => {
    for (let offset = 2; offset + 8 < bytes.length;) {
      assert.equal(bytes[offset++], 0xff);
      const marker = bytes[offset++];
      const length = bytes.readUInt16BE(offset);
      if ([0xc0, 0xc1, 0xc2].includes(marker)) return { width: bytes.readUInt16BE(offset + 5), height: bytes.readUInt16BE(offset + 3) };
      offset += length;
    }
    throw new Error('Missing JPEG frame header');
  };
  for (const [kind, localized] of Object.entries(screenshots)) {
    const hashes = new Set();
    for (const { id } of languages) {
      const shot = localized[id];
      assert.equal(shot.src, `assets/mp4flow-v150-${kind}-${id}.jpg`);
      const bytes = await readFile(new URL('../../website/' + shot.src, import.meta.url));
      const hash = createHash('sha256').update(bytes).digest('hex');
      assert.equal(hash, shot.sha256);
      assert.deepEqual(dimensions(bytes), { width: shot.width, height: shot.height });
      assert.ok(bytes.length < 550 * 1024, 'keep each capture lightweight');
      hashes.add(hash);
    }
    assert.equal(hashes.size, 7, kind + ': do not substitute another language’s capture');
  }
});

test('builder refuses output paths outside its dedicated build directories', async () => {
  await assert.rejects(buildSite('/tmp/unrelated-content'), /Output must be/);
});

test('README derivatives are lossless transparent WebP files tied to the original captures', async () => {
  const { screenshots, format } = JSON.parse(await readFile(new URL('../../docs/assets/readme/screenshots.json', import.meta.url)));
  const originals = JSON.parse(await readFile(new URL('../../website/screenshots.json', import.meta.url))).screenshots;
  assert.equal(format, 'lossless WebP');
  assert.deepEqual(Object.keys(screenshots).sort(), Object.keys(originals).sort());
  for (const [kind, localized] of Object.entries(screenshots)) {
    assert.deepEqual(Object.keys(localized).sort(), languages.map(x => x.id).sort());
    for (const { id } of languages) {
      const shot = localized[id];
      assert.equal(shot.src, `mp4flow-v150-${kind}-${id}.webp`);
      assert.equal(shot.source, 'website/' + originals[kind][id].src);
      assert.equal(shot.sourceSHA256, originals[kind][id].sha256);
      assert.equal(shot.width, originals[kind][id].width);
      assert.equal(shot.height, originals[kind][id].height);
      const bytes = await readFile(new URL('../../docs/assets/readme/' + shot.src, import.meta.url));
      assert.equal(bytes.toString('ascii', 0, 4), 'RIFF');
      assert.equal(bytes.toString('ascii', 8, 12), 'WEBP');
      assert.equal(createHash('sha256').update(bytes).digest('hex'), shot.sha256);
      let frame;
      for (let offset = 12; offset + 8 <= bytes.length;) {
        const size = bytes.readUInt32LE(offset + 4);
        if (bytes.toString('ascii', offset, offset + 4) === 'VP8L') {
          assert.equal(bytes[offset + 8], 0x2f);
          frame = bytes.readUInt32LE(offset + 9);
          break;
        }
        offset += 8 + size + (size & 1);
      }
      assert.notEqual(frame, undefined, 'use lossless image data');
      assert.equal((frame & 0x3fff) + 1, shot.width);
      assert.equal(((frame >>> 14) & 0x3fff) + 1, shot.height);
      assert.equal((frame >>> 28) & 1, 1, 'corners must use transparency');
      assert.ok(bytes.length < shot.pngBytes, 'prefer the smaller lossless web format');
    }
  }
});

test('web navigation uses lightweight, unchanged icons embedded in the App artwork', async () => {
  const appIcon = await readFile(new URL('../../AppResources/AppIcon.icns', import.meta.url));
  for (const size of [128, 256]) {
    const icon = await readFile(new URL(`../../website/assets/mp4flow-icon-${size}.png`, import.meta.url));
    assert.equal(icon.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
    assert.equal(icon.readUInt32BE(16), size);
    assert.equal(icon.readUInt32BE(20), size);
    assert.ok(appIcon.includes(icon), 'reuse original App artwork without regeneration');
    assert.ok(icon.length < (size === 128 ? 32 : 96) * 1024, 'keep small UI assets lightweight');
  }
  const template = await readFile(new URL('../../website/index.html', import.meta.url), 'utf8');
  assert.equal((template.match(/class="wordmark-icon" src="assets\/mp4flow-icon-128.png"/g) ?? []).length, 2);
});

test('new adjustment icon uses the exact App Tabler Outline paths', async () => {
  const sprite = await readFile(new URL('../../website/assets/tabler-icons.svg', import.meta.url), 'utf8');
  const source = await readFile(new URL('../../Sources/FastConvert/Resources/TablerOutline/sun.svg', import.meta.url), 'utf8');
  const symbol = sprite.match(/<symbol id="sun"[^>]*>([\s\S]*?)<\/symbol>/)?.[1];
  assert.ok(symbol);
  assert.deepEqual([...symbol.matchAll(/<path\s+d="([^"]+)"/g)].map(match => match[1]), [...source.matchAll(/<path\s+d="([^"]+)"/g)].map(match => match[1]));
});

test('seven READMEs cover all ten features and use current App action names', async () => {
  const catalogs = await readCatalogs();
  for (const language of languages) {
    const suffix = language.id === 'en' ? '' : `.${language.id === 'zh' ? 'zh-CN' : language.id}`;
    const readme = await readFile(new URL(`../../README${suffix}.md`, import.meta.url), 'utf8');
    const resource = language.id === 'zh' ? 'zh-Hans' : language.id;
    const app = await readFile(new URL(`../../AppResources/${resource}.lproj/Localizable.strings`, import.meta.url), 'utf8');
    const label = key => app.match(new RegExp(`"${key}"\\s*=\\s*"([^"]+)";`))[1];
    for (const key of ['toolOneTitle', 'mergeTitle', 'exportTitle', 'recoveryTitle', 'toolTwoTitle', 'toolThreeTitle', 'toolFourTitle', 'aspectTitle', 'brightenTitle', 'denoiseTitle']) {
      assert.ok(readme.includes(`| **${catalogs[language.id][key]}** |`), `${language.id}: ${key}`);
    }
    for (const key of ['画面编辑', '画面调整', '应用编辑', '开始转换']) assert.ok(readme.includes(`**${label(key)}**`), `${language.id}: ${key}`);
    assert.ok(!readme.includes(`**${label('裁切与比例')} →`), language.id);
    assert.match(readme, /HDR/);
    assert.ok((readme.match(/https:\/\/github\.com\/ixiehao\/MP4Flow\/releases\/latest/g) ?? []).length >= 2, language.id);
    assert.doesNotMatch(readme, /releases\/download\/v\d/);
    for (const kind of ['queue', 'trim', 'crop', 'aspect', 'adjust', 'export']) assert.ok(readme.includes(`docs/assets/readme/mp4flow-v150-${kind}-${language.id}.webp`));
    assert.match(readme, /https:\/\/mango\.blender\.org\//);
    assert.match(readme, /https:\/\/creativecommons\.org\/licenses\/by\/3\.0\//);
    assert.doesNotMatch(readme, /mp4flow-v130/);
  }
});
