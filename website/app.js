// Every language is already rendered in HTML. JavaScript only enhances controls.
const languageLinks = document.querySelectorAll('.language-picker a[data-language]');
const requested = new URLSearchParams(window.location.search).get('lang');

// Keep previously shared ?lang= links working without replacing explicit routes
// with a language inferred from the browser or a stale saved preference.
// Use the generated links as the single source of truth for locale routes.
const requestedLink = [...languageLinks].find(link => link.dataset.language === requested);
if (requestedLink) {
  const target = new URL(requestedLink.href);
  target.search = window.location.search;
  target.searchParams.delete('lang');
  target.hash = window.location.hash;
  window.location.replace(target.href);
}

const picker = document.querySelector('.language-picker');
const summary = picker.querySelector('summary');
languageLinks.forEach(link => {
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
