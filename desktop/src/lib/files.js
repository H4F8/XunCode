import { open, save } from '@tauri-apps/plugin-dialog';
import { readTextFile, writeTextFile } from '@tauri-apps/plugin-fs';

export async function openTextFile() {
  const path = await open({
    multiple: false,
    directory: false,
    filters: [
      { name: 'All files', extensions: ['*'] },
      { name: 'Code', extensions: ['js', 'ts', 'jsx', 'tsx', 'html', 'css', 'scss', 'json', 'py', 'rs', 'go', 'c', 'cpp', 'java', 'kt', 'dart', 'md'] },
    ],
  });
  if (!path) return null;
  const content = await readTextFile(path);
  return { path, content, name: path.split('/').pop() || path.split('\\').pop() };
}

export async function saveTextFile(path, content) {
  if (!path) {
    path = await save({
      filters: [{ name: 'All files', extensions: ['*'] }],
    });
  }
  if (!path) return null;
  await writeTextFile(path, content);
  return path;
}
