import fs from 'fs';
import path from 'path';

const dist = 'dist';
if (fs.existsSync(dist)) fs.rmSync(dist, { recursive: true });
fs.mkdirSync(dist, { recursive: true });

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

fs.copyFileSync('index.html', path.join(dist, 'index.html'));
copyDir('src', path.join(dist, 'src'));

console.log('Frontend assets copied to dist/');
