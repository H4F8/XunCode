import { load } from '@tauri-apps/plugin-store';

let store;
async function getStore() {
  if (!store) store = await load('settings.json', { autoSave: true });
  return store;
}

export const defaults = {
  language: 'ru',
  theme: 'dark',
  fontSize: 14,
  fontFamily: 'JetBrains Mono, Fira Code, monospace',
  wordWrap: 'on',
  minimap: true,
};

export async function getSetting(key) {
  const s = await getStore();
  const value = await s.get(key);
  return value !== null && value !== undefined ? value : defaults[key];
}

export async function setSetting(key, value) {
  const s = await getStore();
  await s.set(key, value);
}

export async function getSettings() {
  const s = await getStore();
  const result = {};
  for (const key of Object.keys(defaults)) {
    const value = await s.get(key);
    result[key] = value !== null && value !== undefined ? value : defaults[key];
  }
  return result;
}
