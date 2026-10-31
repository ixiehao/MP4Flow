import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm, stat } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { buildSite, languages, localePath, readCatalogs, siteURL } from '../build-website.mjs';

test('seven static pages are complete, crawlable and use matching real screenshots', async t => {
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
      assert.equal(schema.screenshot.contentUrl, `${siteURL}assets/mp4flow-v130-${language.id}.jpg`);
      assert.equal(schema.screenshot.inLanguage, language.locale);
      assert.equal(schema.screenshot.caption, copy.stageAlt);
      assert.ok(!('aggregateRating' in schema) && !('review' in schema), 'do not invent ratings for rich results');
      assert.doesNotMatch(html, /"@type":"FAQPage"|"@type":"VideoObject"/);
      assert.deepEqual(schema.featureList, ['toolOneTitle', 'mergeTitle', 'toolTwoTitle', 'toolThreeTitle', 'toolFourTitle', 'aspectTitle', 'brightenTitle', 'denoiseTitle'].map(key => catalogs[language.id][key]));
      assert.equal((html.match(/<article class="tool-card /g) ?? []).length, 8);
      const [conversion, editing] = html.split('<div class="tool-group" role="group" aria-labelledby="edit-group-title">');
      assert.equal((conversion.match(/<article class="tool-card /g) ?? []).length, 2);
      assert.equal((editing.match(/<article class="tool-card /g) ?? []).length, 6);
      assert.ok(html.includes('id="merge-clips"'));
      assert.ok(html.includes('id="image-adjustments"'));
      assert.ok(html.includes('id="light-denoise"'));
      assert.ok(html.includes(catalogs[language.id].adjustNote));
      assert.equal(schema.offers.price, '0');
      const image = html.match(/id="hero-app-screen" src="([^"]+)"/)[1];
      assert.ok(image.endsWith(`mp4flow-v130-${language.id}.jpg`));
      const bytes = await readFile(path.resolve(pageDir, image));
      assert.equal(bytes.subarray(0, 3).toString('hex'), 'ffd8ff', 'valid JPEG capture');
      shots.add(bytes.toString('base64'));
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
  const sitemap = await readFile(path.join(output, 'sitemap.xml'), 'utf8');
  assert.equal((sitemap.match(/<loc>/g) ?? []).length, 7);
  assert.equal((sitemap.match(/xhtml:link/g) ?? []).length, 56);
  await assert.rejects(stat(path.join(output, 'locales')));
  await assert.rejects(stat(path.join(output, 'Scripts')));
});

test('builder refuses output paths outside its dedicated build directories', async () => {
  await assert.rejects(buildSite('/tmp/unrelated-content'), /Output must be/);
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

test('seven READMEs cover all eight features and use current App action names', async () => {
  const catalogs = await readCatalogs();
  for (const language of languages) {
    const suffix = language.id === 'en' ? '' : `.${language.id === 'zh' ? 'zh-CN' : language.id}`;
    const readme = await readFile(new URL(`../../README${suffix}.md`, import.meta.url), 'utf8');
    const resource = language.id === 'zh' ? 'zh-Hans' : language.id;
    const app = await readFile(new URL(`../../AppResources/${resource}.lproj/Localizable.strings`, import.meta.url), 'utf8');
    const label = key => app.match(new RegExp(`"${key}"\\s*=\\s*"([^"]+)";`))[1];
    for (const key of ['toolOneTitle', 'mergeTitle', 'toolTwoTitle', 'toolThreeTitle', 'toolFourTitle', 'aspectTitle', 'brightenTitle', 'denoiseTitle']) {
      assert.ok(readme.includes(`| **${catalogs[language.id][key]}** |`), `${language.id}: ${key}`);
    }
    for (const key of ['画面编辑', '画面调整', '应用编辑', '开始转换']) assert.ok(readme.includes(`**${label(key)}**`), `${language.id}: ${key}`);
    assert.ok(!readme.includes(`**${label('裁切与比例')} →`), language.id);
    assert.match(readme, /HDR/);
    assert.ok((readme.match(/https:\/\/github\.com\/ixiehao\/MP4Flow\/releases\/latest/g) ?? []).length >= 2, language.id);
    assert.doesNotMatch(readme, /releases\/download\/v\d/);
  }
});
