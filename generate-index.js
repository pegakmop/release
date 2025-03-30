const fs = require('fs');
const path = require('path');

// Настройки
const repoBaseUrl = 'https://ground-zerro.github.io/release';
const rootDirs = [
  'keenetic'
];

const isGitHubCI = process.env.GITHUB_ACTIONS === 'true';
const repoRoot = isGitHubCI ? path.resolve(process.cwd()) : __dirname;

function formatSize(bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  while (bytes >= 1024 && i < units.length - 1) {
    bytes /= 1024;
    i++;
  }
  return `${bytes.toFixed(1)} ${units[i]}`;
}

function generateIndexForDir(currentPath, rootDirAbs, rootDirRel) {
  const entries = fs.readdirSync(currentPath, { withFileTypes: true });

  const relativePathFromRoot = path.relative(rootDirAbs, currentPath).replace(/\\/g, '/'); // подкаталоги
  const fullPathFromRepo = path.posix.join(rootDirRel, relativePathFromRoot); // весь путь от корня репы
  const folderUrl = `/${fullPathFromRepo}/`.replace(/\/+$/, '/');
  const baseHref = `${repoBaseUrl}/${fullPathFromRepo}/`.replace(/\/+$/, '/');

  // Вычисляем "один уровень выше"
  const parentPath = fullPathFromRepo.split('/').slice(0, -1).join('/');
  const parentUrl = parentPath ? `${repoBaseUrl}/${parentPath}/` : `${repoBaseUrl}/`;

  const files = entries
    .filter(entry => entry.isFile() && entry.name !== 'index.html')
    .map(entry => ({
      name: entry.name,
      size: formatSize(fs.statSync(path.join(currentPath, entry.name)).size)
    }))
    .sort((a, b) => a.name.localeCompare(b.name));

  const dirs = entries
    .filter(entry => entry.isDirectory())
    .map(entry => ({
      name: entry.name + '/',
      size: '-'
    }))
    .sort((a, b) => a.name.localeCompare(b.name));

  const rows = [
    { name: '..', size: '', href: parentUrl },
    ...dirs.map(d => ({ ...d, href: `${baseHref}${encodeURIComponent(d.name)}` })),
    ...files.map(f => ({ ...f, href: `${baseHref}${encodeURIComponent(f.name)}` }))
  ];

  let html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Index of ${folderUrl}</title>
  <style>
    body { font-family: monospace; padding: 2em; background: #fafafa; color: #333; }
    table { width: 100%; max-width: 800px; border-collapse: collapse; }
    td { padding: 0.3em 0.6em; border-bottom: 1px solid #ddd; }
    td.size { text-align: right; color: #666; white-space: nowrap; }
    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }
    h1 { margin-bottom: 1em; }
  </style>
</head>
<body>
  <h1>Index of ${folderUrl}</h1>
  <table>
`;

  for (const row of rows) {
    html += `    <tr><td><a href="${row.href}">${row.name}</a></td><td class="size">${row.size}</td></tr>\n`;
  }

  html += `  </table>\n</body>\n</html>`;

  fs.writeFileSync(path.join(currentPath, 'index.html'), html, 'utf-8');
  console.log(`✔ index.html created in ${folderUrl}`);
}

function walkAndGenerate(currentDir, rootDirAbs, rootDirRel) {
  generateIndexForDir(currentDir, rootDirAbs, rootDirRel);

  const entries = fs.readdirSync(currentDir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isDirectory()) {
      walkAndGenerate(path.join(currentDir, entry.name), rootDirAbs, rootDirRel);
    }
  }
}

for (const rootDirRel of rootDirs) {
  const rootDirAbs = path.join(repoRoot, rootDirRel);
  if (fs.existsSync(rootDirAbs)) {
    walkAndGenerate(rootDirAbs, rootDirAbs, rootDirRel);
  } else {
    console.warn(`⚠ Directory not found: ${rootDirRel}`);
  }
}