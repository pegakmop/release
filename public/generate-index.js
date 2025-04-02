const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { execSync } = require('child_process');
const os = require('os');

const GITHUB_USER = process.env.GITHUB_REPOSITORY?.split('/')[0] || 'ground-zerro';
const GITHUB_REPO = process.env.GITHUB_REPOSITORY?.split('/')[1] || 'release';
const repoBaseUrl = `https://${GITHUB_USER.toLowerCase()}.github.io/${GITHUB_REPO}`;
const rootDirs = ['keenetic'];
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

function parseControlFields(content) {
  const result = {};
  content.split('\n').forEach(line => {
    const [key, ...rest] = line.split(':');
    if (key && rest.length) {
      result[key.trim()] = rest.join(':').trim();
    }
  });
  return result;
}

function extractControlFromIpk(ipkPath) {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ipk-'));
  try {
    const controlTar = execSync(`tar -xOf "${ipkPath}" control.tar.gz`);
    fs.writeFileSync(path.join(tmpDir, 'control.tar.gz'), controlTar);
    execSync(`tar -xzf control.tar.gz`, { cwd: tmpDir });
    const controlContent = fs.readFileSync(path.join(tmpDir, 'control')).toString();
    return parseControlFields(controlContent);
  } catch (e) {
    console.error(`⚠️ Failed to parse .ipk: ${ipkPath}`);
    return null;
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

function generatePackagesFiles(dir, relPath) {
  const entries = fs.readdirSync(dir);
  const ipkFiles = entries.filter(f => f.endsWith('.ipk'));
  if (ipkFiles.length === 0) return;

  // Оставляем только последнюю версию каждого пакета
  const versionMap = {};
  for (const file of ipkFiles) {
    const match = file.match(/^(.*?)_([^-_]+-[^-_]+)\.ipk$/);
    if (!match) continue;
    const name = match[1];
    const version = match[2];
    if (!versionMap[name] || version > versionMap[name].version) {
      versionMap[name] = { file, version };
    }
  }
  const latestIpkFiles = Object.values(versionMap).map(obj => obj.file);

  const packages = [];
  for (const file of latestIpkFiles) {
    const ipkPath = path.join(dir, file);
    const control = extractControlFromIpk(ipkPath);
    if (!control) continue;

    const stats = fs.statSync(ipkPath);
    const entry = [
      `Package: ${control.Package}`,
      `Version: ${control.Version}`,
      `Architecture: ${control.Architecture}`,
      `Maintainer: ${control.Maintainer || 'unknown'}`,
      `Depends: ${control.Depends || ''}`,
      `Section: ${control.Section || 'base'}`,
      `Priority: ${control.Priority || 'optional'}`,
      `Filename: ${file}`,
      `Size: ${stats.size}`,
      `Description: ${control.Description || ''}`,
      ''
    ].join('\n');
    packages.push(entry);
  }

  const allText = packages.join('\n');
  fs.writeFileSync(path.join(dir, 'Packages'), allText);
  fs.writeFileSync(path.join(dir, 'Packages.gz'), zlib.gzipSync(allText));

  // Создаём HTML в стиле Entware
  const htmlRows = packages.map(pkg => {
    const lines = pkg.split('\n');
    const name = (lines.find(l => l.startsWith('Filename:')) || '').split(':')[1]?.trim() || '';
    const ver = (lines.find(l => l.startsWith('Version:')) || '').split(':')[1]?.trim() || '';
    const sec = (lines.find(l => l.startsWith('Section:')) || '').split(':')[1]?.trim() || '';
    const desc = (lines.find(l => l.startsWith('Description:')) || '').split(':')[1]?.trim() || '';
    return `<tr><td class="name"><a href="${name}">${name}</a></td><td class="version">${ver}</td><td class="section">${sec}</td><td class="description">${desc}</td></tr>`;
  }).join('\n');

  const html = `<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<!-- Designed and coded by Entware team -->
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=us-ascii">
  <title>Packages list</title>
  <link rel="stylesheet" type="text/css" href="/css/packages.css">
</head>
<script type="text/javascript" src="/js/list.min.js"></script>
<body>
<div id="packages">
You may sort table by clicking any column headers and/or use <input class="search" placeholder="Search" /> field.
<table>
<thead>
<tr>
<th class="sort" data-sort="name">Name</th>
<th class="sort" data-sort="version">Version</th>
<th class="sort" data-sort="section">Section</th>
<th class="sort">Description</th>
</tr>
</thead>
<tbody class="list">
${htmlRows}
</tbody>
</table>
</div>
<script type="text/javascript">
  var options = { valueNames: [ 'name', 'version', 'section', 'description' ] };
  var userList = new List('packages', options);
</script>
</body>
</html>`;
  fs.writeFileSync(path.join(dir, 'Packages.html'), html);
  console.log(`📦 Packages.{gz,html} created in ${relPath}`);
}

function generateIndexForDir(currentPath, rootDirAbs, rootDirRel) {
  generatePackagesFiles(currentPath, path.posix.join(rootDirRel, path.relative(rootDirAbs, currentPath).replace(/\\/g, '/')));

  const entries = fs.readdirSync(currentPath, { withFileTypes: true });
  const relativePathFromRoot = path.relative(rootDirAbs, currentPath).replace(/\\/g, '/');
  const fullPathFromRepo = path.posix.join(rootDirRel, relativePathFromRoot);
  const folderUrl = `/${fullPathFromRepo}/`.replace(/\/+/g, '/');
  const baseHref = `${repoBaseUrl}/${fullPathFromRepo}/`
    .replace(/\\\\+/g, '/')
    .replace(/([^:]\/)\/+/g, '$1');

  const files = entries.filter(e => e.isFile() && e.name !== 'index.html')
    .map(e => ({ name: e.name, size: formatSize(fs.statSync(path.join(currentPath, e.name)).size) }))
    .sort((a, b) => a.name.localeCompare(b.name));

  const dirs = entries.filter(e => e.isDirectory())
    .map(e => ({ name: e.name + '/', size: '-' }))
    .sort((a, b) => a.name.localeCompare(b.name));

  const parentPath = fullPathFromRepo.split('/').slice(0, -1).join('/');
  const parentUrl = parentPath ? `${repoBaseUrl}/${parentPath}/` : `${repoBaseUrl}/`;

  const rows = [
    { name: '..', size: '', href: parentUrl },
    ...dirs.map(d => ({ ...d, href: `${baseHref}${encodeURI(d.name)}` })),
    ...files.map(f => ({ ...f, href: `${baseHref}${encodeURI(f.name)}` }))
  ];

  let html = `<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8">
<title>Index of ${folderUrl}</title>
<style>
body { font-family: monospace; padding: 2em; background: #fafafa; color: #333; }
table { width: 100%; max-width: 800px; border-collapse: collapse; }
td { padding: 0.3em 0.6em; border-bottom: 1px solid #ddd; }
td.size { text-align: right; color: #666; white-space: nowrap; }
a { color: #0366d6; text-decoration: none; }
a:hover { text-decoration: underline; }
h1 { margin-bottom: 1em; }
</style></head><body>
<h1>Index of ${folderUrl}</h1>
<table>`;

  for (const row of rows) {
    html += `<tr><td><a href="${row.href}">${row.name}</a></td><td class="size">${row.size}</td></tr>\n`;
  }

  html += '</table></body></html>';
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
