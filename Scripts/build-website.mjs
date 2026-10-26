import { readFile, writeFile, mkdir, cp, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import os from 'node:os';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const siteURL = 'https://ixiehao.github.io/MP4Flow/';
export const languages = [
  { id: 'en', locale: 'en', name: 'English', og: 'en_US' },
  { id: 'zh', locale: 'zh-CN', name: '简体中文', og: 'zh_CN' },
  { id: 'fr', locale: 'fr', name: 'Français', og: 'fr_FR' },
  { id: 'ru', locale: 'ru', name: 'Русский', og: 'ru_RU' },
  { id: 'es', locale: 'es', name: 'Español', og: 'es_ES' },
  { id: 'ja', locale: 'ja', name: '日本語', og: 'ja_JP' },
  { id: 'ko', locale: 'ko', name: '한국어', og: 'ko_KR' }
];
export const localePath = id => id === 'zh' ? '' : `${id}/`;
const escape = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

export async function readCatalogs() {
  const catalogs = {};
  for (const language of languages) {
    const catalog = JSON.parse(await readFile(path.join(root, `website/locales/${language.id}.json`), 'utf8'));
    if (Object.values(catalog).some(value => typeof value !== 'string' || !value.trim() || /[<>]/.test(value))) {
      throw new Error(`${language.id}: translations must be nonempty plain text`);
    }
    catalogs[language.id] = catalog;
  }
  const keys = Object.keys(catalogs.en).sort().join('|');
  for (const [id, catalog] of Object.entries(catalogs)) {
    if (Object.keys(catalog).sort().join('|') !== keys) throw new Error(`${id}: translation keys differ`);
  }
  return catalogs;
}

export function renderPage(template, language, copy) {
  const url = siteURL + localePath(language.id);
  const prefix = language.id === 'zh' ? './' : '../';
  const alternates = languages.map(l => `<link rel="alternate" hreflang="${l.locale}" href="${siteURL}${localePath(l.id)}" />`).join('\n    ');
  const schema = {
    '@context': 'https://schema.org', '@type': 'SoftwareApplication', '@id': `${siteURL}#software`,
    name: 'MP4Flow', applicationCategory: 'UtilitiesApplication', operatingSystem: 'macOS 13 or later',
    description: copy.pageDescription, url, downloadUrl: 'https://github.com/ixiehao/MP4Flow/releases/latest',
    codeRepository: 'https://github.com/ixiehao/MP4Flow', license: 'https://github.com/ixiehao/MP4Flow/blob/main/LICENSE',
    isAccessibleForFree: true, inLanguage: languages.map(l => l.locale),
    author: { '@type': 'Person', name: 'ixiehao', url: 'https://github.com/ixiehao' },
    featureList: ['toolOneTitle', 'toolTwoTitle', 'toolThreeTitle', 'toolFourTitle'].map(key => copy[key]),
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' }
  };
  const meta = (kind, name, value) => `<meta ${kind}="${name}" content="${escape(value)}" />`;
  const head = [
    '<meta charset="UTF-8" />', '<meta name="viewport" content="width=device-width, initial-scale=1" />',
    '<meta name="theme-color" content="#f9fbff" />', '<meta name="author" content="ixiehao" />',
    '<meta name="robots" content="index,follow,max-image-preview:large" />',
    `<title>${escape(copy.pageTitle)}</title>`, meta('name', 'description', copy.pageDescription),
    `<link rel="canonical" href="${url}" />`, alternates,
    `<link rel="alternate" hreflang="x-default" href="${siteURL}" />`,
    meta('property', 'og:type', 'website'), meta('property', 'og:site_name', 'MP4Flow'),
    meta('property', 'og:url', url), meta('property', 'og:locale', language.og),
    ...languages.filter(l => l.id !== language.id).map(l => meta('property', 'og:locale:alternate', l.og)),
    meta('property', 'og:title', copy.pageTitle), meta('property', 'og:description', copy.pageDescription),
    meta('property', 'og:image', `${siteURL}assets/social-preview.jpg?v=2`),
    meta('property', 'og:image:width', '1280'), meta('property', 'og:image:height', '640'),
    meta('property', 'og:image:alt', copy.socialImageAlt), meta('name', 'twitter:card', 'summary_large_image'),
    meta('name', 'twitter:title', copy.pageTitle), meta('name', 'twitter:description', copy.pageDescription),
    meta('name', 'twitter:image', `${siteURL}assets/social-preview.jpg?v=2`), meta('name', 'twitter:image:alt', copy.socialImageAlt),
    '<link rel="icon" type="image/png" href="assets/mp4flow-app-icon.png" />',
    '<link rel="apple-touch-icon" href="assets/mp4flow-app-icon.png" />',
    '<link rel="stylesheet" href="styles.css?v=20261026-i18n" />',
    `<script id="software-schema" type="application/ld+json">${JSON.stringify(schema).replace(/</g, '\\u003c')}</script>`
  ].join('\n    ');
  const languageLinks = languages.map(l => `<a href="${prefix}${localePath(l.id)}" lang="${l.locale}" hreflang="${l.locale}" data-language="${l.id}"${l.id === language.id ? ' aria-current="page"' : ''}>${l.name}</a>`).join('\n          ');
  const values = { ...copy, head, languageLinks, locale: language.locale, language: language.id, languageName: language.name,
    privacyURL: `https://github.com/ixiehao/MP4Flow/blob/main/PRIVACY${language.id === 'ja' ? '.ja' : ''}.md` };
  let result = template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
    if (!(key in values)) throw new Error(`Missing template value: ${key}`);
    return ['head', 'languageLinks'].includes(key) ? values[key] : escape(values[key]).replace(/\n/g, '<br />');
  });
  result = result.replace('<html lang=', `<html data-language="${language.id}" data-root="${prefix}" lang=`);
  result = result.replace(/(href|src)="(assets\/|styles\.css|app\.js)/g, `$1="${prefix}$2`);
  return result;
}

export async function buildSite(output = path.join(root, '_site')) {
  output = path.resolve(output);
  const isTestOutput = output.startsWith(path.join(os.tmpdir(), 'mp4flow-website-test-'));
  if (output !== path.join(root, '_site') && !isTestOutput) throw new Error('Output must be _site or an isolated test directory');
  const catalogs = await readCatalogs();
  const template = await readFile(path.join(root, 'website/index.html'), 'utf8');
  // Validate every localized screenshot before replacing an existing build.
  for (const { id } of languages) await readFile(path.join(root, `website/assets/mp4flow-v130-${id}.jpg`));
  await rm(output, { recursive: true, force: true });
  await mkdir(output, { recursive: true });
  await cp(path.join(root, 'website/assets'), path.join(output, 'assets'), { recursive: true });
  for (const name of ['app.js', 'styles.css', 'robots.txt']) await cp(path.join(root, 'website', name), path.join(output, name));
  for (const language of languages) {
    const dir = path.join(output, localePath(language.id));
    await mkdir(dir, { recursive: true });
    await writeFile(path.join(dir, 'index.html'), renderPage(template, language, catalogs[language.id]));
  }
  const alternates = [...languages.map(l => ({ locale: l.locale, url: siteURL + localePath(l.id) })), { locale: 'x-default', url: siteURL }];
  const sitemap = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${languages.map(l => `  <url><loc>${siteURL}${localePath(l.id)}</loc>\n${alternates.map(a => `    <xhtml:link rel="alternate" hreflang="${a.locale}" href="${a.url}" />`).join('\n')}\n  </url>`).join('\n')}\n</urlset>\n`;
  await writeFile(path.join(output, 'sitemap.xml'), sitemap);
  return output;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(`Built seven language pages: ${await buildSite()}`);
}
