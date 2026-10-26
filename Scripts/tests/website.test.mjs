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
      assert.equal(schema.featureList.length, 4);
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
