import { readFile } from 'node:fs/promises';

export const tutorialContent = JSON.parse(await readFile(new URL('tutorials.json', import.meta.url), 'utf8'));
export const guidePath = (slug, id) => (id === 'en' ? '' : `${id}/`) + `guides/${slug}/`;
const escape = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

export function renderGuideCards(language, prefix) {
  const ui = tutorialContent.locales[language];
  if (!ui) return '';
  const cards = Object.entries(tutorialContent.guides).map(([slug, story]) => `
    <article class="guide-card">
      <h3><a href="${prefix}${guidePath(slug, language)}">${escape(story[language].title)}</a></h3>
      <p>${escape(story[language].description)}</p>
    </article>`).join('');
  return `<section id="guides" class="guide-section" aria-labelledby="guides-title">
    <h2 id="guides-title">${escape(ui.heading)}</h2>
    <div class="guide-grid">${cards}</div>
  </section>`;
}

export function renderGuide({ slug, language, languages, siteURL, styles, siteCopy, media }) {
  const ui = tutorialContent.locales[language.id];
  const guide = tutorialContent.guides[slug];
  const story = guide[language.id];
  const route = guidePath(slug, language.id);
  const canonical = siteURL + route;
  const prefix = '../'.repeat(route.split('/').length - 1);
  const home = prefix + (language.id === 'en' ? '' : language.id + '/');
  const editions = languages.filter(({ id }) => id in tutorialContent.locales);
  const editionsMeta = editions.map(edition => `<link rel="alternate" hreflang="${edition.locale}" href="${siteURL}${guidePath(slug, edition.id)}" />`).join('\n    ');
  const editionLinks = editions.map(edition => `<a href="${prefix}${guidePath(slug, edition.id)}" lang="${edition.locale}" hreflang="${edition.locale}"${edition.id === language.id ? ' aria-current="page"' : ''}>${edition.name}</a>`).join('');
  const title = `${story.title} | MP4Flow`;
  const shareImage = siteURL + media.src;
  const schema = { '@context': 'https://schema.org', '@type': 'Article', headline: story.title, description: story.description, url: canonical, inLanguage: language.locale, image: shareImage };
  const illustration = `<figure class="guide-figure">
    <img src="${prefix}${media.src}" width="${media.width}" height="${media.height}" alt="${escape(story.alt)}" decoding="async" />
    <figcaption>${escape(story.caption)} <a href="${prefix}${media.src}">${escape(ui.image)}</a></figcaption>
  </figure>`;
  const illustrationIndex = slug === 'mkv-to-mp4' ? 2 : 1;
  const steps = story.steps.map(([heading, body], index) => `
      <li><h2>${escape(heading)}</h2><p>${escape(body)}</p>${index === illustrationIndex ? illustration : ''}</li>`).join('');
  const more = Object.entries(tutorialContent.guides).filter(([id]) => id !== slug).map(([id, guide]) =>
    `<li><a href="${prefix}${guidePath(id, language.id)}">${escape(guide[language.id].title)}</a></li>`).join('');
  return `<!doctype html>
<html lang="${language.locale}">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escape(title)}</title>
    <meta name="description" content="${escape(story.description)}" />
    <link rel="canonical" href="${canonical}" />
    ${editionsMeta}
    <link rel="alternate" hreflang="x-default" href="${siteURL}${guidePath(slug, 'en')}" />
    <link rel="alternate" type="text/markdown" href="${canonical}index.md" />
    <link rel="describedby" type="text/plain" href="${siteURL}llms.txt" />
    <meta property="og:type" content="article" />
    <meta property="og:site_name" content="MP4Flow" />
    <meta property="og:url" content="${canonical}" />
    <meta property="og:locale" content="${language.og}" />
    <meta property="og:title" content="${escape(title)}" />
    <meta property="og:description" content="${escape(story.description)}" />
    <meta property="og:image" content="${shareImage}" />
    <meta property="og:image:alt" content="${escape(story.alt)}" />
    <link rel="icon" sizes="128x128" type="image/png" href="${prefix}assets/mp4flow-icon-128.png" />
    <link rel="stylesheet" href="${prefix}styles.css?v=${styles}" />
    <script type="application/ld+json">${JSON.stringify(schema).replace(/</g, '\\u003c')}</script>
  </head>
  <body>
    <a class="skip-link" href="#main">${escape(siteCopy.skipToContent)}</a>
    <header class="site-header guide-header">
      <a class="wordmark" href="${home}" aria-label="${escape(siteCopy.homeLabel)}">
        <img class="wordmark-icon" src="${prefix}assets/mp4flow-icon-128.png" width="128" height="128" alt="" />
        <span class="wordmark-name">MP4<span>Flow</span></span>
      </a>
      <nav class="guide-languages" aria-label="${escape(siteCopy.languagePickerLabel)}">${editionLinks}</nav>
    </header>
    <main class="guide-page" id="main" tabindex="-1">
      <article aria-labelledby="guide-title">
        <header class="guide-intro">
          <a class="guide-back" href="${home}#guides">← ${escape(ui.heading)}</a>
          <h1 id="guide-title">${escape(story.title)}</h1>
          <p>${escape(story.description)}</p>
        </header>
        <section class="guide-prepare" aria-labelledby="guide-prepare">
          <h2 id="guide-prepare">${escape(ui.prepare)}</h2>
          <p>${escape(ui.setup)}</p>
          <div class="guide-actions">
            <a href="${home}#download">${escape(ui.install)}</a>
            <a href="${prefix}assets/tutorials/${guide.sample}" download>${escape(ui.sample.replace('{file}', guide.sample))}</a>
          </div>
        </section>
        <ol class="guide-steps">${steps}</ol>
        <section class="guide-result" aria-labelledby="guide-result">
          <h2 id="guide-result">${escape(ui.verify)}</h2>
          <p>${escape(story.result)}</p>
        </section>
      </article>
      <aside class="guide-more" aria-labelledby="guide-more">
        <h2 id="guide-more">${escape(ui.more)}</h2>
        <ul>${more}</ul>
      </aside>
    </main>
  </body>
</html>
`;
}
