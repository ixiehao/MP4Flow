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
