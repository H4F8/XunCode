import { monaco, detectLanguage } from './lib/monaco.js';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { WebLinksAddon } from 'xterm-addon-web-links';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { openTextFile, saveTextFile } from './lib/files.js';
import { getSettings, setSetting, defaults } from './lib/settings.js';
import { i18n } from './lib/i18n.js';

const state = {
  tabs: [],
  activeTab: null,
  editor: null,
  terminal: null,
  filter: 'all',
  settings: { ...defaults },
};

function t(key, vars = {}) {
  const str = i18n[state.settings.language]?.[key] ?? i18n.en[key] ?? key;
  return Object.entries(vars).reduce(
    (s, [k, v]) => s.replace(`%${k}`, v),
    str,
  );
}

function applyTranslations() {
  document.documentElement.lang = state.settings.language;
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.dataset.i18n;
    if (key) el.textContent = t(key);
  });
}

function applyTheme() {
  document.documentElement.dataset.theme = state.settings.theme;
  monaco.editor.setTheme(state.settings.theme === 'dark' ? 'vs-dark' : 'vs');
}

function updateStatus(message, details = {}) {
  const status = document.getElementById('status-message');
  const lang = document.getElementById('status-lang');
  const pos = document.getElementById('status-position');
  if (status) status.textContent = message ?? t('status_ready');
  if (lang) lang.textContent = state.activeTab?.language ?? 'plain';
  if (pos) pos.textContent = t('status_line_col', { L: details.line ?? 1, C: details.column ?? 1 });
}

async function saveSettings() {
  for (const [key, value] of Object.entries(state.settings)) {
    await setSetting(key, value);
  }
}

function createTab({ name = 'untitled', content = '', path = null, language = 'plaintext' } = {}) {
  const model = monaco.editor.createModel(content, language);
  const tab = {
    id: crypto.randomUUID(),
    name,
    path,
    language,
    model,
    dirty: false,
  };
  tab.disposable = model.onDidChangeContent(() => {
    tab.dirty = true;
    renderTabs();
  });
  state.tabs.push(tab);
  state.activeTab = tab;
  state.editor.setModel(model);
  renderTabs();
  updateStatus(t('status_ready'));
  return tab;
}

function closeTab(tab) {
  const idx = state.tabs.indexOf(tab);
  if (idx === -1) return;
  tab.disposable?.dispose();
  tab.model.dispose();
  state.tabs.splice(idx, 1);
  if (state.activeTab === tab) {
    state.activeTab = state.tabs[Math.min(idx, state.tabs.length - 1)] || null;
    state.editor.setModel(state.activeTab?.model || monaco.editor.createModel('', 'plaintext'));
  }
  renderTabs();
}

function renderTabs() {
  const tabBar = document.getElementById('tab-bar');
  tabBar.innerHTML = '';
  state.tabs.forEach((tab) => {
    const el = document.createElement('div');
    el.className = `tab ${tab === state.activeTab ? 'active' : ''}`;
    el.innerHTML = `<span>${tab.dirty ? '• ' : ''}${tab.name}</span><button class="tab-close">×</button>`;
    el.addEventListener('click', (e) => {
      if (e.target.classList.contains('tab-close')) {
        closeTab(tab);
      } else {
        state.activeTab = tab;
        state.editor.setModel(tab.model);
        renderTabs();
      }
    });
    tabBar.appendChild(el);
  });
}

async function openFile() {
  try {
    const file = await openTextFile();
    if (!file) return;
    const language = detectLanguage(file.name);
    createTab({ name: file.name, content: file.content, path: file.path, language });
    updateStatus(`Opened ${file.name}`);
  } catch (e) {
    updateStatus(`Open error: ${e.message}`);
  }
}

async function saveActiveFile() {
  if (!state.activeTab) return;
  try {
    const content = state.activeTab.model.getValue();
    const path = await saveTextFile(state.activeTab.path, content);
    if (path) {
      state.activeTab.path = path;
      state.activeTab.name = path.split('/').pop() || path.split('\\').pop() || state.activeTab.name;
      state.activeTab.dirty = false;
      renderTabs();
      updateStatus(`Saved ${state.activeTab.name}`);
    }
  } catch (e) {
    updateState(`Save error: ${e.message}`);
  }
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
    value: '',
    language: 'javascript',
    theme: state.settings.theme === 'dark' ? 'vs-dark' : 'vs',
    fontSize: state.settings.fontSize,
    fontFamily: state.settings.fontFamily,
    wordWrap: state.settings.wordWrap,
    minimap: { enabled: state.settings.minimap },
    automaticLayout: true,
    scrollBeyondLastLine: false,
    roundedSelection: false,
    padding: { top: 16 },
  });

  state.editor.onDidChangeCursorPosition((e) => {
    updateStatus(undefined, { line: e.position.lineNumber, column: e.position.column });
  });

  createTab({ name: 'untitled-1.js', content: '// Welcome to XunCode Desktop\n', language: 'javascript' });
}

function initTerminal() {
  const container = document.getElementById('terminal-container');
  const term = new Terminal({
    fontSize: 13,
    fontFamily: state.settings.fontFamily,
    theme: {
      background: '#050505',
      foreground: '#f0f0f5',
      cursor: '#6c5ce7',
      selectionBackground: '#6c5ce733',
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

const mockPlugins = [
  { id: 'prettier', name: 'Prettier', desc: 'Форматирование кода.', platforms: ['desktop', 'android'], author: 'XunCode', rating: 4.8, downloads: 12400 },
  { id: 'eslint', name: 'ESLint', desc: 'Линтинг JavaScript и TypeScript.', platforms: ['desktop'], author: 'XunCode', rating: 4.6, downloads: 9800 },
  { id: 'dart-tools', name: 'Dart Tools', desc: 'Поддержка Dart и Flutter.', platforms: ['android'], author: 'XunCode', rating: 4.5, downloads: 5400 },
  { id: 'git-graph', name: 'Git Graph', desc: 'Визуализация git истории.', platforms: ['desktop'], author: 'XunCode', rating: 4.7, downloads: 11200 },
  { id: 'theme-ocean', name: 'Ocean Theme', desc: 'Темная тема в синих тонах.', platforms: ['desktop', 'android'], author: 'XunCode', rating: 4.4, downloads: 7600 },
];

function renderMarketplace() {
  const grid = document.getElementById('marketplace-grid');
  grid.innerHTML = '';

  const filtered = mockPlugins.filter((p) => {
    if (state.filter === 'all') return true;
    return p.platforms.includes(state.filter) || p.platforms.includes('all');
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
  const wrapSelect = document.getElementById('setting-word-wrap');
  const minimapCheck = document.getElementById('setting-minimap');

  langSelect.value = state.settings.language;
  themeSelect.value = state.settings.theme;
  fontInput.value = state.settings.fontSize;
  wrapSelect.value = state.settings.wordWrap;
  minimapCheck.checked = state.settings.minimap;

  langSelect.addEventListener('change', async () => {
    state.settings.language = langSelect.value;
    applyTranslations();
    await saveSettings();
  });

  themeSelect.addEventListener('change', async () => {
    state.settings.theme = themeSelect.value;
    applyTheme();
    await saveSettings();
  });

  fontInput.addEventListener('change', async () => {
    state.settings.fontSize = parseInt(fontInput.value, 10) || 14;
    state.editor?.updateOptions({ fontSize: state.settings.fontSize });
    await saveSettings();
  });

  wrapSelect.addEventListener('change', async () => {
    state.settings.wordWrap = wrapSelect.value;
    state.editor?.updateOptions({ wordWrap: state.settings.wordWrap });
    await saveSettings();
  });

  minimapCheck.addEventListener('change', async () => {
    state.settings.minimap = minimapCheck.checked;
    state.editor?.updateOptions({ minimap: { enabled: state.settings.minimap } });
    await saveSettings();
  });
}

function initKeyboardShortcuts() {
  window.addEventListener('keydown', async (e) => {
    const ctrl = e.ctrlKey || e.metaKey;
    if (ctrl && e.key === 'o') {
      e.preventDefault();
      await openFile();
    } else if (ctrl && e.key === 's') {
      e.preventDefault();
      await saveActiveFile();
    } else if (ctrl && e.key === 'n') {
      e.preventDefault();
      createTab();
    }
  });
}

async function initUI() {
  state.settings = await getSettings();
  applyTranslations();
  applyTheme();
  initNavigation();
  initEditor();
  initTerminal();
  initMarketplace();
  initSettings();
  initKeyboardShortcuts();

  document.getElementById('new-file-btn').addEventListener('click', () => createTab());
  document.getElementById('open-file-btn').addEventListener('click', openFile);
  document.getElementById('save-file-btn').addEventListener('click', saveActiveFile);

  updateStatus(t('status_ready'));
}

initUI();
