// Every language is already rendered in HTML. JavaScript only enhances controls.
const languages = ['en', 'zh', 'fr', 'ru', 'es', 'ja', 'ko'];
const root = new URL(document.documentElement.dataset.root, window.location.href);
const requested = new URLSearchParams(window.location.search).get('lang');

// Keep previously shared ?lang= links working without replacing explicit routes
// with a language inferred from the browser or a stale saved preference.
if (languages.includes(requested)) {
  const target = new URL(requested === 'zh' ? './' : `${requested}/`, root);
  target.search = window.location.search;
  target.searchParams.delete('lang');
  target.hash = window.location.hash;
  window.location.replace(target.href);
}

const picker = document.querySelector('.language-picker');
const summary = picker.querySelector('summary');
picker.querySelectorAll('a[data-language]').forEach(link => {
  link.addEventListener('click', () => {
    const target = new URL(link.href);
    target.search = window.location.search;
    target.searchParams.delete('lang');
    target.hash = window.location.hash;
    link.href = target.href;
    picker.open = false;
  });
});
document.addEventListener('click', event => {
  if (!picker.contains(event.target)) picker.open = false;
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && picker.open) {
    picker.open = false;
    summary.focus();
  }
});

// The HTML remains a linked screenshot gallery without JavaScript. Enhance it
// into one stable-height, keyboard-accessible view of real application windows.
document.querySelectorAll('[data-product-tour]').forEach(tour => {
  tour.classList.add('is-enhanced');
  const tabs = [...tour.querySelectorAll('[data-tour-tab]')];
  const panels = [...tour.querySelectorAll('[data-tour-panel]')];
  const tablist = tour.querySelector('.tour-tabs');
  tablist.setAttribute('role', 'tablist');
  const verticalLayout = window.matchMedia('(min-width: 861px)');
  const updateOrientation = () => tablist.setAttribute('aria-orientation', verticalLayout.matches ? 'vertical' : 'horizontal');
  updateOrientation();
  verticalLayout.addEventListener('change', updateOrientation);
  tabs.forEach(tab => {
    tab.id = `tour-tab-${tab.dataset.tourTab}`;
    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-controls', `demo-${tab.dataset.tourTab}`);
  });
  panels.forEach(panel => {
    panel.setAttribute('role', 'tabpanel');
    panel.setAttribute('aria-labelledby', `tour-tab-${panel.dataset.tourPanel}`);
    panel.tabIndex = 0;
  });
  function select(id, updateURL = false) {
    if (!tabs.some(tab => tab.dataset.tourTab === id)) return;
    tabs.forEach(tab => {
      const selected = tab.dataset.tourTab === id;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
    });
    panels.forEach(panel => { panel.hidden = panel.dataset.tourPanel !== id; });
    if (updateURL) history.replaceState(null, '', `#demo-${id}`);
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', event => {
      event.preventDefault();
      select(tab.dataset.tourTab, true);
    });
    tab.addEventListener('keydown', event => {
      const nextKey = verticalLayout.matches ? 'ArrowDown' : 'ArrowRight';
      const previousKey = verticalLayout.matches ? 'ArrowUp' : 'ArrowLeft';
      const next = { [nextKey]: (index + 1) % tabs.length, [previousKey]: (index + tabs.length - 1) % tabs.length, Home: 0, End: tabs.length - 1 }[event.key];
      if (next !== undefined) {
        event.preventDefault();
        select(tabs[next].dataset.tourTab, true);
        tabs[next].focus();
      } else if (event.key === ' ') {
        event.preventDefault();
        select(tab.dataset.tourTab, true);
      }
    });
  });
  const selectFragment = () => select(location.hash.slice(1).replace(/^demo-/, ''));
  select('crop');
  selectFragment();
  window.addEventListener('hashchange', selectFragment);
});

const dialog = document.querySelector('#install-dialog');
let trigger;
document.querySelectorAll('[data-install-guide]').forEach(button => {
  button.addEventListener('click', () => {
    trigger = button;
    dialog.showModal();
  });
});
document.querySelector('#install-dialog-close').addEventListener('click', () => dialog.close());
dialog.addEventListener('close', () => trigger?.focus());
dialog.addEventListener('click', event => {
  if (event.target !== dialog) return;
  const bounds = dialog.getBoundingClientRect();
  if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
});
