'use strict';

const search = document.querySelector('#guide-search');
const status = document.querySelector('#guide-status');
const chapters = [...document.querySelectorAll('.guide-chapter')];
const normalize = (text) =>
  text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
const contents = new Map(chapters.map((chapter) => [chapter, normalize(chapter.textContent)]));
const update = () => {
  const query = normalize(search.value.trim());
  let visible = 0;
  for (const chapter of chapters) {
    chapter.hidden =
      !contents.get(chapter).includes(query) ||
      (status.value && chapter.dataset.status !== status.value);
    if (!chapter.hidden) visible++;
  }
  document.querySelector('#guide-count').textContent = `${visible} de ${chapters.length} capítulos`;
  document.querySelector('#guide-empty').hidden = visible > 0;
};
search.addEventListener('input', update);
status.addEventListener('change', update);
for (const link of document.querySelectorAll('.section-nav a')) {
  link.addEventListener('click', () => {
    search.value = '';
    status.value = '';
    update();
  });
}
