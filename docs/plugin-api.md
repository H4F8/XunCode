# Plugin API Reference — XunCode (Android)

XunCode plugins are JavaScript files that run inside the Monaco Editor WebView sandbox. Each plugin calls `XuncodePlugin.register()` and receives a `ctx` object with full access to the editor, UI, hooks, storage, and HTTP.

> **Primary namespace is `xuncode`.** `window.vscode` and `XuncodePlugin.register()` remain available as aliases for backward compatibility; existing plugins keep working unchanged.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Plugin Manifest](#plugin-manifest)
- [ctx.editor](#ctxeditor)
- [ctx.ui](#ctxui)
- [ctx.hooks](#ctxhooks)
- [ctx.storage](#ctxstorage)
- [ctx.http](#ctxhttp)
- [ctx.terminal](#ctxterminal)
- [ctx.fs](#ctxfs)
- [Lifecycle](#lifecycle)
- [Developer Mode](#developer-mode)
- [Hosting Your Plugin](#hosting-your-plugin)
- [Publishing to Marketplace](#publishing-to-marketplace)
- [Full Examples](#full-examples)
- [Limitations & Sandbox](#limitations--sandbox)
- [Changelog](#changelog)

---

## Quick Start

```js
XuncodePlugin.register({
  id: 'my-org.my-plugin',
  name: 'My Plugin',
  version: '1.0.0',
  description: 'Does something awesome',
  author: 'your-github-handle',

  activate(ctx) {
    ctx.ui.showMessage('My Plugin loaded!');

    ctx.editor.addCommand({
      id: 'my-plugin.hello',
      label: 'My Plugin: Say Hello',
      run() {
        const sel = ctx.editor.getSelection();
        ctx.ui.showMessage(sel ? `Selected: ${sel}` : 'No selection');
      }
    });
  },

  deactivate() {
    // cleanup listeners, timers, etc.
  }
});
```

---

## Plugin Manifest

Fields passed to `XuncodePlugin.register()`:

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | ✅ | Unique ID in `org.name` format, e.g. `acme.formatter` |
| `name` | string | ✅ | Display name shown in marketplace |
| `version` | string | ✅ | Semver string, e.g. `1.0.0` |
| `description` | string | ✅ | Short description (1–2 sentences) |
| `author` | string | ✅ | Author name or GitHub handle |
| `activate(ctx)` | function | ✅ | Entry point — called when plugin loads |
| `deactivate()` | function | ❌ | Called when plugin is removed |

---

## ctx.editor

Interact with the Monaco Editor instance.

### `ctx.editor.getValue() → string`
Returns the full text content of the current editor buffer.

```js
const code = ctx.editor.getValue();
console.log('File has', code.split('\n').length, 'lines');
```

### `ctx.editor.setValue(text: string)`
Replaces the entire editor content. Adds to undo history.

```js
ctx.editor.setValue('// rewritten\n' + ctx.editor.getValue());
```

### `ctx.editor.getSelection() → string`
Returns the currently selected text, or empty string if nothing selected.

### `ctx.editor.replaceSelection(text: string)`
Replaces the current selection with `text`. If nothing is selected, inserts at cursor.

```js
const sel = ctx.editor.getSelection();
if (sel) ctx.editor.replaceSelection(sel.toUpperCase());
```

### `ctx.editor.getCursorPosition() → { lineNumber, column }`
Returns the current cursor position.

```js
const pos = ctx.editor.getCursorPosition();
ctx.ui.showMessage(`Line ${pos.lineNumber}, Col ${pos.column}`);
```

### `ctx.editor.getLanguage() → string`
Returns the current language ID, e.g. `"javascript"`, `"python"`, `"dart"`.

**All supported language IDs:**
`javascript` `typescript` `python` `kotlin` `java` `dart` `go` `rust`
`c` `cpp` `csharp` `html` `css` `scss` `json` `yaml` `markdown`
`shell` `xml` `php` `ruby` `swift` `sql` `r` `lua` `plaintext`

### `ctx.editor.setLanguage(lang: string)`
Changes the syntax highlighting language.

```js
ctx.editor.setLanguage('typescript');
```

### `ctx.editor.addCommand(cmd: object)`
Registers a command that appears in the editor command palette.

```js
ctx.editor.addCommand({
  id: 'my-plugin.run',        // must be unique
  label: 'My Plugin: Run',    // shown in command palette
  keybinding: null,           // optional: Monaco KeyCode name
  run() {
    // called when command is triggered
  }
});
```

### `ctx.editor.onDidChangeContent(fn: function)`
Fires `fn(newContent: string)` on every content change (every keystroke). Use sparingly.

```js
ctx.editor.onDidChangeContent((content) => {
  // debounce this in production!
});
```

### `ctx.editor.format()`
Triggers Monaco's built-in document formatter.

---

## ctx.ui

Show messages and interact with the app UI.

### `ctx.ui.showMessage(text: string)`
Shows a snackbar notification (dark, bottom of screen). Auto-dismisses after 3s.

### `ctx.ui.showError(text: string)`
Shows an error snackbar (red). Auto-dismisses after 4s.

### `ctx.ui.addStatusBarItem(item: object)`
Adds a clickable item to the bottom status bar.

```js
ctx.ui.addStatusBarItem({
  id: 'my-plugin.status',
  text: 'My Plugin',
  tooltip: 'Click to run',
  onClick() {
    ctx.ui.showMessage('Status bar clicked!');
  }
});
```

> **Note:** Status bar items are removed automatically when the plugin is deactivated.

---

## ctx.hooks

React to editor and app lifecycle events.

### `ctx.hooks.onFileSave(fn: function)`
Called with `fn(uri: string, content: string)` whenever the user saves.

```js
ctx.hooks.onFileSave((uri, content) => {
  console.log('Saved:', uri, '—', content.length, 'chars');
});
```

### `ctx.hooks.onFileOpen(fn: function)`
Called with `fn(uri: string, content: string, filename: string)` when a file is opened.

```js
ctx.hooks.onFileOpen((uri, content, filename) => {
  if (filename.endsWith('.py')) {
    ctx.ui.showMessage('Python file opened');
  }
});
```

### `ctx.hooks.onEditorReady(fn: function)`
Called once when Monaco has fully initialized. Use for setup that requires the editor to be ready.

```js
ctx.hooks.onEditorReady(() => {
  ctx.editor.setValue('// Welcome!\n');
});
```

---

## ctx.storage

Persistent key-value storage scoped to your plugin ID. Backed by `localStorage` — survives app restarts.

### `ctx.storage.get(key: string) → string | null`
### `ctx.storage.set(key: string, value: string)`
### `ctx.storage.remove(key: string)`

```js
// Store and retrieve settings
let apiKey = ctx.storage.get('api-key');
if (!apiKey) {
  apiKey = prompt('Enter API key:');
  ctx.storage.set('api-key', apiKey);
}

// Store JSON
ctx.storage.set('config', JSON.stringify({ theme: 'dark', size: 14 }));
const config = JSON.parse(ctx.storage.get('config') || '{}');
```

> **Tip:** Prefix your keys with your plugin ID to avoid collisions: `my-plugin.api-key`

---

## ctx.http

Make HTTP requests from your plugin. All requests automatically route through Tor SOCKS5 proxy when the user has Tor enabled in settings.

### `ctx.http.get(url: string, headers?: object) → Promise<string>`
### `ctx.http.post(url: string, body: string, headers?: object) → Promise<string>`

```js
// GET request
const raw = await ctx.http.get('https://api.github.com/repos/owner/repo');
const repo = JSON.parse(raw);

// POST with JSON body and auth header
const response = await ctx.http.post(
  'https://api.anthropic.com/v1/messages',
  JSON.stringify({
    model: 'claude-sonnet-4-6',
    max_tokens: 1024,
    messages: [{ role: 'user', content: 'Hello' }]
  }),
  {
    'x-api-key': ctx.storage.get('anthropic-key'),
    'anthropic-version': '2023-06-01',
    'content-type': 'application/json'
  }
);
const data = JSON.parse(response);
```

> **Note:** The target server must allow CORS (`Access-Control-Allow-Origin: *`) or requests will fail.

---

## ctx.terminal

Interact with the built-in terminal (proot + Alpine). Requires the user to have Alpine installed.

> **Warning:** Terminal API is asynchronous. All methods return `Promise<void>`.

### `ctx.terminal.write(text: string)`
Send text to the active terminal. Supports ANSI escape codes.

```js
await ctx.terminal.write('ls -la\n');
```

### `ctx.terminal.clear()`
Clear the terminal screen (sends `\x1Bc`).

```js
await ctx.terminal.clear();
```

### `ctx.terminal.onOutput(fn: function)`
Listen to terminal output. `fn(data: string)` receives raw output chunks.

```js
ctx.terminal.onOutput((data) => {
  console.log('term:', data);
});
```

> **Note:** Only one listener per plugin is supported. Registering a new listener replaces the previous one.

---

## ctx.fs

Limited file-system access through the app's sandbox. All paths are relative to the app project directory (`/sdcard/XunCode/Projects/` inside proot, or the external app directory on Android).

### `ctx.fs.read(path: string) → Promise<string>`
Read a file as UTF-8 text. Returns empty string if the file does not exist.

```js
const content = await ctx.fs.read('README.md');
console.log(content);
```

### `ctx.fs.write(path: string, content: string) → Promise<void>`
Write text to a file. Creates parent directories automatically.

```js
await ctx.fs.write('notes.txt', 'Hello from plugin!\n');
```

### `ctx.fs.readdir(path: string) → Promise<string[]>`
List files and directories at the given path. Returns an array of names (not full paths). Returns `[]` if the directory does not exist.

```js
const files = await ctx.fs.readdir('src');
console.log('Files:', files.join(', '));
```

> **Limitations:** `ctx.fs` cannot access files outside the app project directory. No `rename`, `delete`, or `mkdir` — use `ctx.terminal.write()` with shell commands if needed.

---

## Lifecycle

```
App starts
  └─ Plugin JS loaded from URL
       └─ XuncodePlugin.register() called
            └─ activate(ctx) called
                 ├─ Register commands
                 ├─ Register hooks
                 └─ Plugin is running

User removes plugin
  └─ deactivate() called
       └─ Clean up timers, listeners, etc.
```

**Best practices:**
- Keep `activate()` fast — don't do heavy work synchronously
- Always implement `deactivate()` if you set up timers or global listeners
- Debounce `onDidChangeContent` — it fires on every keystroke

---

## Developer Mode

Enable **Developer Mode** in Settings to test plugins without publishing.

1. Settings → Developer Mode → ON
2. Settings → Developer → **Load Local Plugin**
3. Paste your plugin JS code into the text area
4. Tap **Run** — plugin executes immediately in the editor sandbox
5. Errors appear in the developer console output below

**Tips for development:**
- Use `console.log()` — output appears in the developer console
- You can reload the plugin by pasting and running again
- Test with different file types to verify language detection
- Test `ctx.http` calls with a real API before publishing

---

## Hosting Your Plugin

Your plugin must be hosted at a publicly accessible URL that serves the JS file with CORS headers.

### Option 1: GitHub Raw (easiest)

1. Create a public GitHub repo
2. Add your `plugin.js` file
3. Use the raw URL: `https://raw.githubusercontent.com/user/repo/main/plugin.js`

> GitHub raw URLs already have CORS headers — no extra config needed.

### Option 2: Vercel (recommended for production)

1. Create a Next.js or static project
2. Put your plugin in `public/plugin.js`
3. Add `vercel.json` for CORS:

```json
{
  "headers": [
    {
      "source": "/plugin.js",
      "headers": [
        { "key": "Access-Control-Allow-Origin", "value": "*" }
      ]
    }
  ]
}
```

4. Deploy: `vercel --prod`
5. Your plugin URL: `https://your-project.vercel.app/plugin.js`

### Option 3: jsDelivr CDN

If your plugin is on GitHub, jsDelivr serves it with CORS automatically:
`https://cdn.jsdelivr.net/gh/user/repo@main/plugin.js`

---

## Publishing to Marketplace

Once your plugin is hosted and tested:

1. Go to **[xuncode-market.vercel.app/submit](https://xuncode-market.vercel.app/submit)**
2. Fill in the submission form:
   - Plugin name, description, version
   - Author name / GitHub handle
   - Category: `AI / Assistant` | `Formatter` | `Language Support` | `Theme` | `Git` | `Utility`
   - Tags (comma-separated)
   - Install URL (the raw JS URL)
   - GitHub repo URL (optional but recommended)
   - Contact email (not shown publicly)
3. Submit — the maintainer reviews your plugin
4. On approval: plugin goes live in the in-app Marketplace
5. On rejection: you receive an email with the reason

**Review criteria:**
- Plugin must work as described
- No malicious code (network requests to unknown endpoints, data exfiltration)
- Must use `XuncodePlugin.register()` correctly
- Description must be accurate
- File size under 500KB

---

## Full Examples

### Word Counter

```js
XuncodePlugin.register({
  id: 'example.word-counter',
  name: 'Word Counter',
  version: '1.0.0',
  description: 'Counts words and shows stats',
  author: 'example',

  activate(ctx) {
    function getStats() {
      const text = ctx.editor.getValue();
      const words = text.trim().split(/\s+/).filter(Boolean).length;
      const chars = text.length;
      const lines = text.split('\n').length;
      return { words, chars, lines };
    }

    ctx.editor.addCommand({
      id: 'word-counter.show',
      label: 'Word Counter: Show Stats',
      run() {
        const s = getStats();
        ctx.ui.showMessage(`${s.words} words · ${s.chars} chars · ${s.lines} lines`);
      }
    });

    ctx.hooks.onFileSave(() => {
      const s = getStats();
      ctx.ui.showMessage(`Saved — ${s.words} words`);
    });
  }
});
```

### Auto Header

```js
XuncodePlugin.register({
  id: 'example.auto-header',
  name: 'Auto Header',
  version: '1.0.0',
  description: 'Inserts a file header comment on save',
  author: 'example',

  activate(ctx) {
    ctx.editor.addCommand({
      id: 'auto-header.insert',
      label: 'Auto Header: Insert',
      run() {
        const lang = ctx.editor.getLanguage();
        const date = new Date().toISOString().split('T')[0];
        const author = ctx.storage.get('auto-header.author') || 'Unknown';
        const isPy = lang === 'python' || lang === 'r';
        const prefix = isPy ? '#' : '//';
        const header = `${prefix} Author: ${author}\n${prefix} Date: ${date}\n${prefix} Language: ${lang}\n\n`;
        ctx.editor.setValue(header + ctx.editor.getValue());
      }
    });
  }
});
```

### AI Code Review (uses Anthropic API)

```js
XuncodePlugin.register({
  id: 'example.ai-review',
  name: 'AI Code Review',
  version: '1.0.0',
  description: 'Reviews selected code using Claude',
  author: 'example',

  activate(ctx) {
    ctx.editor.addCommand({
      id: 'ai-review.review',
      label: 'AI: Review Selected Code',
      async run() {
        let key = ctx.storage.get('ai-review.key');
        if (!key) {
          key = prompt('Anthropic API key:');
          if (!key) return;
          ctx.storage.set('ai-review.key', key);
        }

        const code = ctx.editor.getSelection() || ctx.editor.getValue();
        const lang = ctx.editor.getLanguage();
        ctx.ui.showMessage('Reviewing…');

        try {
          const raw = await ctx.http.post(
            'https://api.anthropic.com/v1/messages',
            JSON.stringify({
              model: 'claude-sonnet-4-6',
              max_tokens: 1024,
              messages: [{
                role: 'user',
                content: `Review this ${lang} code for bugs, style issues, and improvements. Be concise:\n\n\`\`\`${lang}\n${code}\n\`\`\``
              }]
            }),
            {
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json'
            }
          );
          const result = JSON.parse(raw);
          const review = result.content[0].text;
          // Insert review as a comment block above the code
          const lines = review.split('\n').map(l => `// ${l}`).join('\n');
          ctx.editor.setValue(lines + '\n\n' + ctx.editor.getValue());
          ctx.ui.showMessage('Review inserted above your code');
        } catch (e) {
          ctx.ui.showError('Error: ' + e.message);
        }
      }
    });
  }
});
```

---

## Limitations & Sandbox

Plugins run inside the Monaco WebView sandbox. The following are **not available**:

| Not available | Reason |
|---|---|
| `require()` / `import` | No Node.js, no module system |
| `fs`, `path`, `os` | No filesystem access |
| `fetch()` directly | Use `ctx.http` instead (Tor-aware) |
| DOM manipulation outside editor | Sandboxed WebView |
| Native Android APIs | Use the Flutter bridge via `ctx.http` |
| `localStorage` directly | Use `ctx.storage` (scoped to plugin) |
| Plugins > 500KB | Hard limit enforced by marketplace |

**What IS available:**
- Full ES2020+ JavaScript
- `console.log/warn/error` (visible in Developer Mode)
- `JSON`, `Math`, `Date`, `Promise`, `async/await`
- `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`
- All `ctx.*` APIs listed in this document

---

## Support & Community

- GitHub: [@H4F8](https://github.com/H4F8) — open issues and PRs here
- Dev channel: [t.me/XunKal1Dev](https://t.me/XunKal1Dev) — direct line to the maintainer
- Community channel: [t.me/GodPassTGK](https://t.me/GodPassTGK) — announcements and discussion

---

## Changelog

### v1.0.0
- Initial plugin API release
- `ctx.editor`: getValue, setValue, getSelection, replaceSelection, getCursorPosition, getLanguage, setLanguage, addCommand, onDidChangeContent, format
- `ctx.ui`: showMessage, showError, addStatusBarItem
- `ctx.hooks`: onFileSave, onFileOpen, onEditorReady
- `ctx.storage`: get, set, remove
- `ctx.http`: get, post (Tor-aware)
