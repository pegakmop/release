const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { execSync } = require('child_process');
const os = require('os');

const GITHUB_USER = process.env.GITHUB_REPOSITORY?.split('/')[0] || 'pegakmop';
const GITHUB_REPO = process.env.GITHUB_REPOSITORY?.split('/')[1] || 'release';
const repoBaseUrl = `https://${GITHUB_USER.toLowerCase()}.github.io/${GITHUB_REPO}`;
const rootDirs = ['keenetic'];
const isGitHubCI = process.env.GITHUB_ACTIONS === 'true';
const repoRoot = isGitHubCI ? path.resolve(process.cwd()) : __dirname;

/* ================= STYLE (как на главной) ================= */
const embeddedCSS = `
:root{
  --bg:#0b0f14; --fg:#e6edf3; --muted:#9aa4ae;
  --stroke:rgba(255,255,255,.12);
  --neon:#00d5ff; --neon-2:#6effa2; --violet:#a493ff;
  --shadow:0 10px 30px rgba(0,0,0,.35);
}
*{box-sizing:border-box}
html,body{margin:0;min-height:100%}
body{
  font-family: ui-sans-serif, system-ui, -apple-system, "Inter", "Segoe UI", Roboto, Arial, sans-serif;
  background:var(--bg); color:var(--fg);
  display:flex; justify-content:center; padding:24px 14px 40px;
  overflow-x:hidden;
}
.aurora{
  position:fixed; inset:0; z-index:-2; overflow:hidden;
  background:
    radial-gradient(1200px 600px at 10% 10%, rgba(0,213,255,.20), transparent 60%),
    radial-gradient(1000px 600px at 85% 20%, rgba(110,255,162,.18), transparent 60%),
    radial-gradient(900px 500px at 50% 90%, rgba(164,147,255,.16), transparent 60%),
    linear-gradient(180deg,#06080b,#0b0f14 55%,#0b0f14);
}
.aurora::before{
  content:""; position:absolute; inset:-20%;
  background:
    conic-gradient(from 0deg at 30% 30%, rgba(0,213,255,.18), transparent 40%),
    conic-gradient(from 180deg at 70% 60%, rgba(110,255,162,.16), transparent 50%);
  filter:blur(70px); mix-blend-mode:screen;
  animation:drift 18s linear infinite alternate;
}
@keyframes drift{to{transform:translate3d(6%,-4%,0) rotate(10deg)}}
.wrap{width:min(900px,100%)}
.card{
  background:linear-gradient(180deg,rgba(255,255,255,.07),rgba(255,255,255,.03));
  border:1px solid var(--stroke); border-radius:20px;
  box-shadow:var(--shadow); backdrop-filter:blur(14px) saturate(1.1);
  overflow:hidden; animation:enter .6s ease both;
}
@keyframes enter{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
.content{padding:clamp(18px,4vw,36px)}
h1{
  margin:0 0 6px; font-weight:800; font-size:clamp(22px,5vw,34px); line-height:1.1;
  background:linear-gradient(90deg,var(--neon),var(--neon-2) 55%,#c2b6ff);
  -webkit-background-clip:text; background-clip:text; color:transparent;
  word-break:break-all;
}
.crumbs{font-size:14px;color:var(--muted);margin-bottom:16px;word-break:break-all}
.crumbs a{color:var(--neon);text-decoration:none}
.crumbs a:hover{text-decoration:underline}
.search{
  width:100%; margin:4px 0 14px; padding:12px 14px; font-size:16px;
  color:var(--fg); background:rgba(8,12,16,.6);
  border:1px solid var(--stroke); border-radius:12px; outline:none;
}
.search:focus{border-color:var(--neon);box-shadow:0 0 0 3px rgba(0,213,255,.15)}
.list{display:flex;flex-direction:column;gap:6px}
.item{
  display:flex; align-items:center; gap:12px; padding:11px 14px;
  border:1px solid transparent; border-radius:12px;
  background:rgba(255,255,255,.03);
  color:var(--fg); text-decoration:none;
  transition:background .15s,border-color .15s,transform .12s;
}
.item:hover{background:rgba(0,213,255,.08);border-color:rgba(0,213,255,.35);transform:translateX(2px)}
.item .ico{flex:0 0 auto;font-size:18px}
.item .name{
  flex:1; min-width:0; word-break:break-all;
  font:600 14px/1.35 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  color:#b6f7ff;
}
.item.dir .name{color:var(--neon-2)}
.item .size{flex:0 0 auto;font-size:12px;color:var(--muted);white-space:nowrap}
.empty{display:none;color:var(--muted);padding:12px 4px}
.tablewrap{overflow-x:auto;border:1px solid var(--stroke);border-radius:14px}
table{width:100%;border-collapse:collapse;font-size:14px;min-width:560px}
th,td{text-align:left;padding:10px 12px;border-bottom:1px solid var(--stroke);vertical-align:top}
th{color:var(--muted);font-weight:600;background:rgba(255,255,255,.04);white-space:nowrap}
tr:last-child td{border-bottom:0}
td a{color:var(--neon);text-decoration:none;font-weight:700}
td a:hover{text-decoration:underline}
td.ver{font-family:ui-monospace,Menlo,monospace;color:var(--neon-2);white-space:nowrap}
td.desc{color:var(--muted)}
footer{
  padding:14px 22px; color:var(--muted); font-size:13px;
  border-top:1px solid var(--stroke);
  display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap;
}
footer a{color:var(--neon);text-decoration:none}
@media (prefers-reduced-motion:reduce){.aurora::before,.card{animation:none}}
`;

const searchScript = `
(function(){
  var q=document.getElementById('q'); if(!q) return;
  var rows=[].slice.call(document.querySelectorAll('[data-s]'));
  var empty=document.getElementById('empty');
  q.addEventListener('input',function(){
    var v=q.value.trim().toLowerCase(), n=0;
    rows.forEach(function(r){
      var ok=!v||r.getAttribute('data-s').indexOf(v)>-1;
      r.style.display=ok?'':'none'; if(ok) n++;
    });
    empty.style.display=n?'none':'block';
  });
})();
`;

function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function pageShell({ title, heading, crumbsHtml, bodyHtml }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>${esc(title)}</title>
<style>${embeddedCSS}</style>
</head>
<body>
<div class="aurora" aria-hidden="true"></div>
<div class="wrap">
  <section class="card">
    <div class="content">
      <h1>${esc(heading)}</h1>
      <div class="crumbs">${crumbsHtml}</div>
      ${bodyHtml}
    </div>
    <footer>
      <div>© Pegakmop — clean builds, no nonsense.</div>
      <div><a href="${repoBaseUrl}/">← Release Zone</a></div>
    </footer>
  </section>
</div>
<script>${searchScript}</script>
</body>
</html>`;
}

function buildCrumbs(fullPathFromRepo) {
  const parts = fullPathFromRepo.split('/').filter(Boolean);
  let acc = '';
  const links = [`<a href="${repoBaseUrl}/">release</a>`];
  for (const p of parts) {
    acc += `${p}/`;
    links.push(`<a href="${repoBaseUrl}/${acc}">${esc(p)}</a>`);
  }
  return links.join(' / ');
}

function iconFor(name) {
  if (name.endsWith('/')) return '📁';
  if (name.endsWith('.ipk')) return '📦';
  if (name.endsWith('.sh')) return '📜';
  if (name.endsWith('.html')) return '🌐';
  if (name.endsWith('.gz')) return '🗜️';
  return '📄';
}

/* ================= HELPERS ================= */
function compareVersions(v1, v2) {
  const split = v => v.split(/[.\-+_~:]/).map(x => (/^\d+$/.test(x) ? parseInt(x, 10) : x));
  const a = split(v1), b = split(v2);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i] ?? 0, y = b[i] ?? 0;
    if (x === y) continue;
    if (typeof x === 'number' && typeof y === 'number') return x - y;
    return String(x).localeCompare(String(y));
  }
  return 0;
}

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
    const controlTar = execSync(`tar -xOf "${ipkPath}" ./control.tar.gz 2>/dev/null || tar -xOf "${ipkPath}" control.tar.gz`);
    fs.writeFileSync(path.join(tmpDir, 'control.tar.gz'), controlTar);
    execSync(`tar -xzf control.tar.gz`, { cwd: tmpDir });
    const controlPath = fs.existsSync(path.join(tmpDir, 'control'))
      ? path.join(tmpDir, 'control')
      : path.join(tmpDir, './control');
    const controlContent = fs.readFileSync(controlPath).toString();
    return parseControlFields(controlContent);
  } catch (e) {
    console.error(`⚠️ Failed to parse .ipk: ${ipkPath}`);
    return null;
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

/* ================= Packages / Packages.gz / Packages.html ================= */
function generatePackagesFiles(dir, relPath) {
  const entries = fs.readdirSync(dir);
  const ipkFiles = entries.filter(f => f.endsWith('.ipk'));
  if (ipkFiles.length === 0) return;

  const packageEntries = [];

  for (const file of ipkFiles) {
    const ipkPath = path.join(dir, file);
    const control = extractControlFromIpk(ipkPath);
    if (!control || !control.Package || !control.Version || !control.Architecture) continue;

    packageEntries.push({
      name: control.Package,
      version: control.Version,
      arch: control.Architecture,
      filename: file,
      size: fs.statSync(ipkPath).size,
      control
    });
  }

  // Только самые новые версии
  const latestMap = {};
  for (const entry of packageEntries) {
    const key = `${entry.name}_${entry.arch}`;
    if (!latestMap[key] || compareVersions(entry.version, latestMap[key].version) > 0) {
      latestMap[key] = entry;
    }
  }

  const finalPackages = Object.values(latestMap);
  const packages = [];
  for (const entry of finalPackages) {
    const control = entry.control;
    const block = [
      `Package: ${control.Package}`,
      `Version: ${control.Version}`,
      `Depends: ${control.Depends || ''}`,
      `Section: ${control.Section || 'net'}`,
      `Architecture: ${control.Architecture}`,
      `Installed-Size: ${control['Installed-Size'] || '0'}`,
      `Filename: ${entry.filename}`,
      `Size: ${entry.size}`,
      `Maintainer: ${control.Maintainer || 'unknown'}`,
      `Description: ${control.Description || ''}`,
      ''
    ].join('\n');
    packages.push(block);
  }

  const allText = packages.join('\n');
  fs.writeFileSync(path.join(dir, 'Packages'), allText);
  fs.writeFileSync(path.join(dir, 'Packages.gz'), zlib.gzipSync(allText));

  let rows = '';
  for (const block of packages) {
    const data = parseControlFields(block);
    rows += `<tr data-s="${esc((data.Package + ' ' + (data.Description || '')).toLowerCase())}">` +
      `<td><a href="${encodeURI(data.Filename)}">${esc(data.Package)}</a></td>` +
      `<td class="ver">${esc(data.Version)}</td>` +
      `<td>${esc(data.Section || '')}</td>` +
      `<td class="desc">${esc(data.Description || '')}</td></tr>\n`;
  }

  const body = `
<input id="q" class="search" type="search" placeholder="🔍 Search packages…" autocomplete="off">
<div class="tablewrap"><table>
<thead><tr><th>Name</th><th>Version</th><th>Section</th><th>Description</th></tr></thead>
<tbody>${rows}</tbody>
</table></div>
<div id="empty" class="empty">Nothing found</div>`;

  const html = pageShell({
    title: `Packages in /${relPath}`,
    heading: '📦 Packages',
    crumbsHtml: buildCrumbs(relPath) + ` · <a href="./">index</a>`,
    bodyHtml: body
  });
  fs.writeFileSync(path.join(dir, 'Packages.html'), html);
}

/* ================= index.html ================= */
function generateIndexForDir(currentPath, rootDirAbs, rootDirRel) {
  generatePackagesFiles(currentPath, path.posix.join(rootDirRel, path.relative(rootDirAbs, currentPath).replace(/\\/g, '/')));

  const entries = fs.readdirSync(currentPath, { withFileTypes: true });
  const relativePathFromRoot = path.relative(rootDirAbs, currentPath).replace(/\\/g, '/');
  const fullPathFromRepo = path.posix.join(rootDirRel, relativePathFromRoot);
  const folderUrl = `/${fullPathFromRepo}/`.replace(/\/+/g, '/');
  const baseHref = `${repoBaseUrl}/${fullPathFromRepo}/`.replace(/\\+/g, '/').replace(/([^:]\/)\/+/g, '$1');

  const files = entries.filter(e => e.isFile() && e.name !== 'index.html')
    .map(e => ({ name: e.name, size: formatSize(fs.statSync(path.join(currentPath, e.name)).size) }))
    .sort((a, b) => a.name.localeCompare(b.name));

  const dirs = entries.filter(e => e.isDirectory())
    .map(e => ({ name: e.name + '/', size: '' }))
    .sort((a, b) => a.name.localeCompare(b.name));

  const parentPath = fullPathFromRepo.split('/').slice(0, -1).join('/');
  const parentUrl = parentPath ? `${repoBaseUrl}/${parentPath}/` : `${repoBaseUrl}/`;

  const row = (r, cls) =>
    `<a class="item ${cls}" data-s="${esc(r.name.toLowerCase())}" href="${r.href}">` +
    `<span class="ico">${iconFor(r.name)}</span>` +
    `<span class="name">${esc(r.name)}</span>` +
    `<span class="size">${esc(r.size)}</span></a>\n`;

  let list = `<a class="item dir" href="${parentUrl}"><span class="ico">⬆️</span><span class="name">..</span><span class="size"></span></a>\n`;
  for (const d of dirs) list += row({ ...d, href: `${baseHref}${encodeURI(d.name)}` }, 'dir');
  for (const f of files) list += row({ ...f, href: `${baseHref}${encodeURI(f.name)}` }, 'file');

  const body = `
<input id="q" class="search" type="search" placeholder="🔍 Filter files…" autocomplete="off">
<div class="list">${list}</div>
<div id="empty" class="empty">Nothing found</div>`;

  const html = pageShell({
    title: `Index of ${folderUrl}`,
    heading: `Index of ${folderUrl}`,
    crumbsHtml: buildCrumbs(fullPathFromRepo),
    bodyHtml: body
  });
  fs.writeFileSync(path.join(currentPath, 'index.html'), html, 'utf-8');
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
