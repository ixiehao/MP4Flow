import { test, expect, languages } from './support.mjs';
import { guidePath, tutorialContent } from '../website/tutorials.mjs';

for (const language of languages.filter(id => id in tutorialContent.locales)) {
  for (const viewport of [{ width: 320, height: 568 }, { width: 1280, height: 900 }]) {
    test.describe(`${language} guides at ${viewport.width}px`, () => {
      test.use({ javaScriptEnabled: false, viewport, isMobile: viewport.width < 500, hasTouch: viewport.width < 500 });
      test('localized tutorials, sample media and language links work without JavaScript', async ({ page }) => {
        const home = language === 'en' ? './' : language + '/';
        for (const [slug, guide] of Object.entries(tutorialContent.guides)) {
          expect((await page.goto(home)).status()).toBe(200);
          await page.locator('#guides').getByRole('link', { name: guide[language].title }).click();
          const route = guidePath(slug, language);
          expect(page.url()).toMatch(new RegExp(`/${route}$`));
          await expect(page.getByRole('heading', { level: 1 })).toHaveText(guide[language].title);
          await expect(page.locator('.guide-steps > li')).toHaveCount(3);
          await expect(page.locator('.guide-result p')).toHaveText(guide[language].result);
          const layout = await page.evaluate(() => ({ width: innerWidth, scrollWidth: document.documentElement.scrollWidth }));
          expect(layout).toEqual({ width: viewport.width, scrollWidth: viewport.width });
          const sample = page.locator('main a[download]');
          const sampleURL = new URL(await sample.getAttribute('href'), page.url()).href;
          expect((await page.request.head(sampleURL)).status()).toBe(200);
          const picture = page.getByRole('img', { name: guide[language].alt });
          await expect(picture).toBeVisible();
          const dimensions = await picture.evaluate(image => ({
            width: image.naturalWidth, height: image.naturalHeight, rendered: image.getBoundingClientRect().width,
            bounds: image.closest('article').getBoundingClientRect().width
          }));
          expect(dimensions.width).toBe(guide[language].media.width);
          expect(dimensions.height).toBe(guide[language].media.height);
          expect(dimensions.rendered).toBeLessThanOrEqual(dimensions.bounds);
          const original = await page.locator('.guide-figure a').getAttribute('href');
          expect(original).toEqual(await picture.getAttribute('src'));
          expect((await page.request.head(new URL(original, page.url()).href)).status()).toBe(200);
          const other = language === 'ja' ? 'zh' : 'ja';
          await page.locator(`.guide-languages a[lang="${other === 'zh' ? 'zh-CN' : other}"]`).click();
          await expect(page.getByRole('heading', { level: 1 })).toHaveText(guide[other].title);
        }
      });
    });
  }
}
