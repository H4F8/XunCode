// Minimal plugin example. The runtime calls `exports.activate(xuncode)` once
// the host is ready. The `xuncode` object is the API surface — see the bundled
// docs (Settings → Plugins → Документация по плагинам) for the full reference.

exports.activate = (xuncode) => {
  xuncode.commands.registerCommand('hello.say', () => {
    xuncode.ui.showMessage('Hello from plugin!');
  });

  xuncode.hooks.onSave((path) => {
    xuncode.ui.showMessage('Saved: ' + path);
  });
};
