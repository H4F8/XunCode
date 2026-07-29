import * as monaco from 'monaco-editor';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { WebLinksAddon } from 'xterm-addon-web-links';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

const i18n = {
  ru: {
    nav_editor: 'Редактор',
    nav_marketplace: 'Маркетплейс',
    nav_terminal: 'Терминал',
    nav_settings: 'Настройки',
    marketplace_title: 'Маркетплейс плагинов',
    filter_all: 'Все',
    filter_desktop: 'Desktop',
    filter_android: 'Android',
    settings_title: 'Настройки',
    settings_appearance: 'Внешний вид',
    settings_language: 'Язык / Language',
    settings_theme: 'Тема',
    settings_font_size: 'Размер шрифта редактора',
    settings_links: 'Ссылки',
    settings_about: 'О приложении',
    settings_about_text: 'Кроссплатформенный редактор кода с плагинами и терминалом.',
  },
  en: {
    nav_editor: 'Editor',
    nav_marketplace: 'Marketplace',
    nav_terminal: 'Terminal',
    nav_settings: 'Settings',
    marketplace_title: 'Plugin Marketplace',
    filter_all: 'All',
    filter_desktop: 'Desktop',
    filter_android: 'Android',
    settings_title: 'Settings',
    settings_appearance: 'Appearance',
    settings_language: 'Language / Язык',
    settings_theme: 'Theme',
    settings_font_size: 'Editor font size',
    settings_links: 'Links',
    settings_about: 'About',
    settings_about_text: 'Cross-platform code editor with plugins and terminal.',
  },
};

let currentLang = localStorage.getItem('xuncode:language') || 'ru';
let currentTheme = localStorage.getItem('xuncode:theme') || 'dark';
let fontSize = parseInt(localStorage.getItem('xuncode:fontSize') || '14', 10);

const state = {
  tabs: [],
  activeTab: null,
  editor: null,
  terminal: null,
  filter: 'all',
};

function applyTranslations() {
  const t = i18n[currentLang];
  document.documentElement.lang = currentLang;
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.dataset.i18n;
    if (t[key]) el.textContent = t[key];
  });
}

function applyTheme() {
  document.documentElement.dataset.theme = currentTheme;
  monaco.editor.setTheme(currentTheme === 'dark' ? 'vs-dark' : 'vs');
}

function saveSettings() {
  localStorage.setItem('xuncode:language', currentLang);
  localStorage.setItem('xuncode:theme', currentTheme);
  localStorage.setItem('xuncode:fontSize', String(fontSize));
}

function initNavigation() {
  document.querySelectorAll('.nav-item').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.nav-item').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      const view = btn.dataset.view;
      document.querySelectorAll('.view').forEach((v) => v.classList.remove('active'));
      document.getElementById(`view-${view}`).classList.add('active');
      if (view === 'terminal' && state.terminal) {
        setTimeout(() => state.terminal.fitAddon.fit(), 10);
      }
    });
  });
}

function initEditor() {
  const container = document.getElementById('editor-container');
  state.editor = monaco.editor.create(container, {
    value: '// Welcome to XunCode Desktop\n',
    language: 'javascript',
    theme: currentTheme === 'dark' ? 'vs-dark' : 'vs',
    fontSize,
    fontFamily: 'JetBrains Mono, Fira Code, monospace',
    automaticLayout: true,
    minimap: { enabled: true },
    scrollBeyondLastLine: false,
    roundedSelection: false,
    padding: { top: 16 },
  });
}

function initTerminal() {
  const container = document.getElementById('terminal-container');
  const term = new Terminal({
    fontSize: 13,
    fontFamily: 'JetBrains Mono, Fira Code, monospace',
    theme: {
      background: '#0d1117',
      foreground: '#e6edf3',
      cursor: '#58a6ff',
      selectionBackground: '#264f78',
    },
    cursorBlink: true,
  });

  const fitAddon = new FitAddon();
  term.loadAddon(fitAddon);
  term.loadAddon(new WebLinksAddon());
  term.open(container);
  fitAddon.fit();

  term.onData(async (data) => {
    try {
      await invoke('pty_write', { data });
    } catch (e) {
      term.writeln(`\r\n[write error] ${e}`);
    }
  });

  state.terminal = { term, fitAddon };

  (async () => {
    try {
      const { cols, rows } = fitAddon.proposeDimensions();
      await invoke('pty_create', { cols, rows });
      term.writeln('\x1b[1;32mXunCode Terminal\x1b[0m');
      listen('pty:data', (event) => {
        term.write(event.payload);
      });
    } catch (e) {
      term.writeln(`\r\n[pty error] ${e}`);
    }
  })();

  window.addEventListener('resize', () => {
    fitAddon.fit();
    const { cols, rows } = fitAddon.proposeDimensions();
    invoke('pty_resize', { cols, rows }).catch(() => {});
  });
}

function initTabs() {
  const tabBar = document.getElementById('tab-bar');

  function render() {
    tabBar.innerHTML = '';
    state.tabs.forEach((tab, idx) => {
      const el = document.createElement('div');
      el.className = `tab ${tab === state.activeTab ? 'active' : ''}`;
      el.innerHTML = `<span>${tab.name}</span><button class="tab-close">×</button>`;
      el.addEventListener('click', (e) => {
        if (e.target.classList.contains('tab-close')) {
          state.tabs.splice(idx, 1);
          if (state.activeTab === tab) state.activeTab = state.tabs[0] || null;
          if (state.activeTab) state.editor.setModel(state.activeTab.model);
          render();
        } else {
          state.activeTab = tab;
          state.editor.setModel(tab.model);
          render();
        }
      });
      tabBar.appendChild(el);
    });
  }

  document.getElementById('new-file-btn').addEventListener('click', () => {
    const model = monaco.editor.createModel('', 'javascript');
    const tab = { name: `untitled-${state.tabs.length + 1}.js`, model };
    state.tabs.push(tab);
    state.activeTab = tab;
    state.editor.setModel(model);
    render();
  });

  render();
}

const mockPlugins = [
  { id: 'prettier', name: 'Prettier', desc: 'Форматирование кода.', platforms: ['desktop', 'android'], author: 'XunCode' },
  { id: 'eslint', name: 'ESLint', desc: 'Линтинг JavaScript и TypeScript.', platforms: ['desktop'], author: 'XunCode' },
  { id: 'dart-tools', name: 'Dart Tools', desc: 'Поддержка Dart и Flutter.', platforms: ['android'], author: 'XunCode' },
  { id: 'git-graph', name: 'Git Graph', desc: 'Визуализация git истории.', platforms: ['desktop'], author: 'XunCode' },
  { id: 'theme-ocean', name: 'Ocean Theme', desc: 'Темная тема в синих тонах.', platforms: ['desktop', 'android'], author: 'XunCode' },
];

function renderMarketplace() {
  const grid = document.getElementById('marketplace-grid');
  grid.innerHTML = '';

  const filtered = mockPlugins.filter((p) => {
    if (state.filter === 'all') return true;
    return p.platforms.includes(state.filter);
  });

  filtered.forEach((p) => {
    const card = document.createElement('div');
    card.className = 'plugin-card';
    card.innerHTML = `
      <h3>${p.name}</h3>
      <p>${p.desc}</p>
      <div class="meta">
        ${p.platforms.map((pl) => `<span class="tag">${pl}</span>`).join('')}
        <span class="tag">@${p.author}</span>
      </div>
      <button>Install</button>
    `;
    grid.appendChild(card);
  });
}

function initMarketplace() {
  document.querySelectorAll('.filter-chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.filter-chip').forEach((c) => c.classList.remove('active'));
      chip.classList.add('active');
      state.filter = chip.dataset.filter;
      renderMarketplace();
    });
  });
  renderMarketplace();
}

function initSettings() {
  const langSelect = document.getElementById('setting-language');
  const themeSelect = document.getElementById('setting-theme');
  const fontInput = document.getElementById('setting-font-size');

  langSelect.value = currentLang;
  themeSelect.value = currentTheme;
  fontInput.value = fontSize;

  langSelect.addEventListener('change', () => {
    currentLang = langSelect.value;
    applyTranslations();
    saveSettings();
  });

  themeSelect.addEventListener('change', () => {
    currentTheme = themeSelect.value;
    applyTheme();
    saveSettings();
  });

  fontInput.addEventListener('change', () => {
    fontSize = parseInt(fontInput.value, 10) || 14;
    if (state.editor) state.editor.updateOptions({ fontSize });
    saveSettings();
  });
}

function initUI() {
  applyTranslations();
  applyTheme();
  initNavigation();
  initEditor();
  initTerminal();
  initTabs();
  initMarketplace();
  initSettings();
}

initUI();
