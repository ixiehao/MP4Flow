import { readFileSync, readdirSync } from 'node:fs';

const languages = readdirSync(new URL('./website/locales/', import.meta.url)).filter(name => name.endsWith('.json')).map(name => name.slice(0, -5));
export default {
  ...{
  "prefix": "/MP4Flow/",
  "url": "https://ixiehao.github.io/MP4Flow/",
  "directory": "_site",
  "build": "node Scripts/build-website.mjs",
  "breakpoints": [
    520,
    640,
    760,
    960
  ],
  "cards": ".feature-card,.feature-summary",
  "uniform": [
    ".feature-grid > .feature-card"
  ],
  "picker": ".language-picker",
  "menu": ".language-links",
  "languageAttribute": "data-language",
  "faq": ".faq-list details"
},
  grids: [{"selector": ".feature-grid", "columns": [[640, 1], [10000, 2]]}],
  scriptsDirectory: 'Scripts',
  languages
};
