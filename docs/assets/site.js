'use strict';

const dependencyCommands = {
  debian: 'sudo apt-get update\nsudo apt-get install git build-essential clang pkg-config libgc-dev ldc dub python3',
  fedora: 'sudo dnf install git gcc clang pkgconf-pkg-config gc-devel ldc dub python3',
  arch: 'sudo pacman -S --needed git gcc clang pkgconf gc ldc dub python',
};
const distro = document.querySelector('#distro');
distro.addEventListener('change', () => {
  document.querySelector('#deps-code').textContent = dependencyCommands[distro.value];
});

const normalize = text => text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const rows = [...document.querySelectorAll('.feature-row')];
document.querySelector('#feature-search').addEventListener('input', event => {
  const query = normalize(event.target.value.trim());
  let visible = 0;
  for (const row of rows) {
    row.hidden = !normalize(row.textContent).includes(query);
    if (!row.hidden) visible++;
  }
  document.querySelector('#features-empty').hidden = visible > 0;
});

for (const button of document.querySelectorAll('[data-copy]')) {
  button.addEventListener('click', async () => {
    const text = document.getElementById(button.dataset.copy).textContent;
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = 'Copiado';
      document.querySelector('#copy-status').textContent = 'Código copiado.';
      setTimeout(() => { button.textContent = 'Copiar'; }, 1800);
    } catch {
      const range = document.createRange();
      range.selectNodeContents(document.getElementById(button.dataset.copy));
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      document.querySelector('#copy-status').textContent = 'Selecionei o código. Use o comando de copiar do seu navegador.';
    }
  });
}
