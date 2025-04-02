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

// Встроенный CSS
const embeddedCSS = `
body { font-family: sans-serif; background: #f8f8f8; color: #222; padding: 20px; }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
th { background: #f0f0f0; cursor: pointer; }
.search { margin: 10px 0; padding: 5px; width: 200px; }
a { color: #0366d6; text-decoration: none; }
a:hover { text-decoration: underline; }
`;

// Встроенный JS (list.min.js)
const embeddedJS = `
/*! list.js v1.5.0 (c) 2017 Jonny Strömberg MIT license */
var List=function(t){function e(t,e){var n,r,i;return function(){var s=this,o=arguments,a=function(){n=null,e||t.apply(r,i)};clearTimeout(n),n=setTimeout(a,e),e&&!n&&(r=this,i=o,n=setTimeout(a,e))}}function n(t){return"[object Array]"===Object.prototype.toString.call(t)}function r(t){return void 0!==t&&null!==t&&t!==!1}function i(t,e){for(var n in e)t[n]=e[n];return t}function s(t){return t.replace(/^\s+|\s+$/g,"")}function o(t,e){return t===e}function a(t,e){return t.localeCompare(e)}function u(t,e){return e-t}function c(t,e){return t-e}function l(t){var e=t.getAttribute("data-sort")||t.innerText,n=t.getAttribute("data-sort-method"),r=t.getAttribute("data-sort-order")||"asc";return{value:s(e),order:r,sortFunction:n}}function f(t,e){return{value:t,order:"asc",sortFunction:null}}function d(t){return function(e,n){var r=t.value,i=n.value;if(t.sortFunction===a||t.sortFunction==="string")return t.order==="asc"?a(r,i):a(i,r);if(t.sortFunction==="number"||typeof r=="number")return t.order==="asc"?c(r,i):c(i,r);return t.order==="asc"?o(r,i):o(i,r)}}function h(t){return function(e,n){return t.indexOf(e.value)<t.indexOf(n.value)?-1:1}}return function s(t,e){function o(){d=!0,f()}function a(){d=!1}function u(t,e){if(!e)return t;var n=e.split(" ");return t.filter(function(t){for(var e=0;e<n.length;e++)if(t.indexOf(n[e])===-1)return!1;return!0})}function c(t,e,n){if(!e)return t;var r=s(e),i=r.toLowerCase().split(" ");return t.filter(function(t){var e=n(t);return i.every(function(n){return e.indexOf(n)!==-1})})}function l(t){return t.toString().toLowerCase()}function f(){g.render()}var d=!1,h=[],m=[],g={};return g.listClass="list",g.searchClass="search",g.sortClass="sort",g.valueNames=[],g.page=200,g.plugins=[],g.listContainer=null,g.searchColumns=[],i(g,e),g.list=t instanceof HTMLElement?t:document.querySelector(t),g.list||(console.error("List container not found"),null),g.listContainer=g.list.querySelector("tbody")||g.list,g.searchInput=g.list.querySelector("."+g.searchClass),g.sortButtons=g.list.querySelectorAll("."+g.sortClass),g.searchInput&&(g.searchInput.addEventListener("input",e(function(){g.search(g.searchInput.value)},100)),g.searchColumns=["name","version","section","description"]),g.sortButtons.forEach(function(t){t.addEventListener("click",function(){var e=t.getAttribute("data-sort"),n=t.getAttribute("data-order")||"asc";g.sort(e,{order:n})})}),g.search=function(t){m=h.slice(),m=c(m,t,function(t){return l(Object.values(t).join(" "))}),g.render()},g.sort=function(t,e){e=e||{};var n=e.order||"asc";m.sort(function(e,r){var i=e[t],s=r[t];return n==="asc"?a(i,s):a(s,i)}),g.render()},g.render=function(){var t=m.slice(0,g.page);g.listContainer.innerHTML="",t.forEach(function(t){g.listContainer.appendChild(t.el)})},g.add=function(t){var e=document.createElement("tr");Object.keys(t).forEach(function(n){var r=document.createElement("td");r.className=n,r.textContent=t[n],e.appendChild(r)}),t.el=e,h.push(t),m.push(t)},g.clear=function(){h=[],m=[],g.listContainer.innerHTML=""},o(),g}};
`;

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

  // Группировка по имени пакета, выбор только последней версии
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

  // Генерация Packages и Packages.gz
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

  // Packages.html с таблицей
  let html = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Packages in /${relPath}</title>
<style>${embeddedCSS}</style>
</head>
<body>
<div id="packages">
<p>You may sort table by clicking any column headers and/or use <input class="search" placeholder="Search" /></p>
<table>
<thead>
<tr><th class="sort" data-sort="name">Name</th>
<th class="sort" data-sort="version">Version</th>
<th class="sort" data-sort="section">Section</th>
<th class="sort">Description</th></tr>
</thead>
<tbody class="list">
`;

  for (const pkg of packages) {
    const lines = pkg.split('\n');
    const pkgData = {};
    lines.forEach(line => {
      const [key, ...rest] = line.split(':');
      if (key && rest.length) {
        pkgData[key.trim()] = rest.join(':').trim();
      }
    });
    if (!pkgData.Package || !pkgData.Version) continue;
    html += `<tr><td class="name"><a href="${pkgData.Filename}">${pkgData.Package}</a></td>
<td class="version">${pkgData.Version}</td>
<td class="section">${pkgData.Section || ''}</td>
<td class="description">${pkgData.Description || ''}</td></tr>\n`;
  }

  html += `</tbody></table></div><script>${embeddedJS}</script></body></html>`;
  fs.writeFileSync(path.join(dir, 'Packages.html'), html);
  console.log(`📦 Packages.{gz,html} created in ${relPath}`);
}

function generateIndexForDir(currentPath, rootDirAbs, rootDirRel) {
  generatePackagesFiles(currentPath, path.posix.join(rootDirRel, path.relative(rootDirAbs, currentPath).replace(/\\/g, '/')));

  const entries = fs.readdirSync(currentPath, { withFileTypes: true });
  const relativePathFromRoot = path.relative(rootDirAbs, currentPath).replace(/\\/g, '/');
  const fullPathFromRepo = path.posix.join(rootDirRel, relativePathFromRoot);
  const folderUrl = `/${fullPathFromRepo}/`.replace(/\/+/g, '/');
  const baseHref = `${repoBaseUrl}/${fullPathFromRepo}/`.replace(/\\\\+/g, '/').replace(/([^:]\/)\/+/g, '$1');

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
