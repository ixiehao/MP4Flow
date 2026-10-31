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
  for (const language of languages) {
    await t.test(language.id, async () => {
      const pageDir = path.join(output, localePath(language.id));
      const html = await readFile(path.join(pageDir, 'index.html'), 'utf8');
      assert.ok(html.includes(`lang="${language.locale}"`));
      assert.ok(html.includes(`<link rel="canonical" href="${siteURL}${localePath(language.id)}"`));
      assert.doesNotMatch(html, /\{\{|undefined|语言菜单中 English/);
      assert.equal((html.match(/<h1\b/g) ?? []).length, 1);
      assert.equal((html.match(/data-language="/g) ?? []).length, 8);
      assert.equal((html.match(/aria-current="page"/g) ?? []).length, 1);
      assert.equal((html.match(/<link rel="alternate" hreflang=/g) ?? []).length, 8);
      assert.ok(html.includes(catalogs[language.id].installTitle));
      assert.ok(html.includes('brew install ffmpeg'));
      const schema = JSON.parse(html.match(/id="software-schema"[^>]*>([\s\S]*?)<\/script>/)[1]);
      assert.deepEqual(schema.inLanguage, languages.map(l => l.locale));
      assert.equal(schema.url, siteURL + localePath(language.id));
      assert.equal(schema.description, catalogs[language.id].pageDescription);
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
  const sitemap = await readFile(path.join(output, 'sitemap.xml'), 'utf8');
  assert.equal((sitemap.match(/<loc>/g) ?? []).length, 7);
  assert.equal((sitemap.match(/xhtml:link/g) ?? []).length, 56);
  await assert.rejects(stat(path.join(output, 'locales')));
  await assert.rejects(stat(path.join(output, 'Scripts')));
});

test('builder refuses output paths outside its dedicated build directories', async () => {
  await assert.rejects(buildSite('/tmp/unrelated-content'), /Output must be/);
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
