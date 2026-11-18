// Embedded by build-guide.mjs; the delivered HTML has no external dependencies.
(() => {
  'use strict';
  const storeKey = 'ticket_lab6_guide_checked_v2';
  const sections = [...document.querySelectorAll('section[data-step]')];
  const boxes = [...document.querySelectorAll('.stepcheckbox')];
  const navs = [...document.querySelectorAll('.navitem')];
  const toast = document.querySelector('#toast');
  let toastTimer;
  function notify(text) {
    clearTimeout(toastTimer);
    toast.textContent = text;
    toast.classList.add('show');
    toastTimer = setTimeout(() => toast.classList.remove('show'), 2300);
  }
  let saved = {};
  try {
    const value = JSON.parse(localStorage.getItem(storeKey) || '{}');
    if (value && typeof value === 'object' && !Array.isArray(value)) saved = value;
  } catch { /* Offline/private mode can disallow localStorage. */ }
  function refresh() {
    const completed = new Set(boxes.filter(box => box.checked).map(box => box.dataset.key));
    const percent = Math.round(completed.size / sections.length * 100);
    document.querySelector('#progressvalue').textContent = `${completed.size} из ${sections.length} · ${percent}%`;
    document.querySelector('#progressbar').style.width = percent + '%';
    document.querySelector('#progress').setAttribute('aria-valuenow', String(percent));
    navs.forEach(link => link.classList.toggle('done', completed.has(link.hash.slice(1))));
  }
  boxes.forEach(box => {
    box.checked = saved[box.dataset.key] === true;
    box.addEventListener('change', () => {
      saved[box.dataset.key] = box.checked;
      try { localStorage.setItem(storeKey, JSON.stringify(saved)); } catch { /* State still works for this visit. */ }
      refresh();
    });
  });
  refresh();

  async function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      try { await navigator.clipboard.writeText(text); return true; } catch { /* Try local-file fallback. */ }
    }
    const previousFocus = document.activeElement;
    const box = document.createElement('textarea');
    box.value = text;
    box.setAttribute('readonly', '');
    box.style.cssText = 'position:fixed;left:0;top:0;opacity:0;pointer-events:none';
    document.body.append(box);
    box.focus();
    box.select();
    let copied = false;
    try { copied = document.execCommand('copy'); } catch { /* Manual selection below. */ }
    box.remove();
    previousFocus?.focus({preventScroll: true});
    return copied;
  }
  document.querySelectorAll('button.copy').forEach(button => button.addEventListener('click', async () => {
    const code = button.closest('.command').querySelector('pre code');
    const copied = await copyText(code.textContent);
    button.classList.toggle('copied', copied);
    button.textContent = copied ? 'Скопировано ✓' : 'Выделено — Ctrl+C';
    if (!copied) {
      const selection = window.getSelection(), range = document.createRange();
      range.selectNodeContents(code);
      selection.removeAllRanges();
      selection.addRange(range);
    }
    notify(copied ? 'Команда скопирована. Выполните её в указанной оболочке.' : 'Браузер запретил копирование. Нажмите Ctrl+C для выделенной команды.');
    setTimeout(() => { button.classList.remove('copied'); button.textContent = 'Копировать'; }, 1800);
  }));

  const normalize = text => text.toLocaleLowerCase('ru').replaceAll('ё', 'е');
  const search = document.querySelector('#search');
  const searchable = new Map(sections.map(section => [section.id, normalize(section.textContent)]));
  search.addEventListener('input', () => {
    const query = normalize(search.value.trim());
    let visible = 0;
    navs.forEach(link => {
      const matches = !query || searchable.get(link.hash.slice(1)).includes(query);
      link.hidden = !matches;
      if (matches) visible++;
    });
    document.querySelector('#noresults').style.display = visible ? 'none' : 'block';
  });
  search.addEventListener('keydown', event => {
    if (event.key === 'Escape') { search.value = ''; search.dispatchEvent(new Event('input')); }
  });
  document.querySelector('#resetprogress').addEventListener('click', () => {
    boxes.forEach(box => { box.checked = false; });
    saved = {};
    try { localStorage.removeItem(storeKey); } catch { /* No persistent storage. */ }
    refresh();
    notify('Отметки Спринта 6 сброшены. Данные проекта не изменялись.');
  });
  document.querySelector('#print').addEventListener('click', () => window.print());
  document.querySelector('#allSteps').addEventListener('click', () => {
    search.value = '';
    search.dispatchEvent(new Event('input'));
    document.querySelector('#step-1').scrollIntoView({behavior: 'smooth'});
  });
  const menu = document.querySelector('#mobilemenu');
  const sidebar = document.querySelector('.sidebar');
  menu.addEventListener('click', () => {
    const opened = sidebar.classList.toggle('open');
    menu.setAttribute('aria-expanded', String(opened));
    menu.textContent = opened ? 'Закрыть' : 'Этапы';
  });
  navs.forEach(link => link.addEventListener('click', () => {
    sidebar.classList.remove('open');
    menu.setAttribute('aria-expanded', 'false');
    menu.textContent = 'Этапы';
  }));
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      const seen = entries.filter(entry => entry.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
      if (!seen.length) return;
      navs.forEach(link => {
        const active = link.hash === '#' + seen[0].target.id;
        link.classList.toggle('active', active);
        if (active) link.setAttribute('aria-current', 'step');
        else link.removeAttribute('aria-current');
      });
    }, {rootMargin: '-5% 0px -72% 0px', threshold: 0});
    sections.forEach(section => observer.observe(section));
  }
})();
