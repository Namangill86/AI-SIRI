#!/usr/bin/env node
'use strict';
/**
 * SiriAI laptop agent (zero dependencies, Node 18+).
 * Connects out to your relay, so no ports need opening. Your phone talks to the AI running here;
 * the AI can open apps, move files, take screenshots, control media, and message your phone.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const readline = require('readline');
const { execFile, spawn } = require('child_process');
const { Readable } = require('stream');
const { pipeline } = require('stream/promises');

const P = process.platform;
const CFG_PATH = process.env.SIRIAI_CONFIG || path.join(__dirname, 'config.json');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toLocaleTimeString(), ...a);
const clip = (s, n = 4000) => { s = String(s ?? ''); return s.length > n ? s.slice(0, n) + '…[truncated]' : s; };

const defaults = {
  device: 'laptop', model: 'claude-sonnet-5-5', apiBase: 'https://api.anthropic.com',
  shareDir: path.join(os.homedir(), 'SiriAI-Share'), allowedDirs: [], allowShell: false, ntfyTopic: ''
};
let cfg;
let rl;
const prompt = q => { rl = rl || readline.createInterface({ input: process.stdin, output: process.stdout }); return new Promise(r => rl.question(q, a => r(a.trim()))); };
const confirm = (q, ms = 60000) => Promise.race([prompt(q + ' [y/N] ').then(a => /^y/i.test(a)), sleep(ms).then(() => false)]);

async function loadConfig() {
  let c = {};
  if (fs.existsSync(CFG_PATH)) c = JSON.parse(fs.readFileSync(CFG_PATH, 'utf8'));
  else {
    console.log('First-time setup. Answers are saved to config.json (keep it private).\n');
    c.relay = await prompt('Relay URL (https://your-relay.onrender.com or http://localhost:8787): ');
    c.token = await prompt('Room token (blank = generate one): ');
    if (!c.token) { c.token = crypto.randomBytes(24).toString('base64url'); console.log('\nYour room token. Enter the SAME token on your phone:\n  ' + c.token + '\n'); }
    c.apiKey = await prompt('Anthropic API key: ');
    c.device = (await prompt('Name for this laptop [laptop]: ')) || 'laptop';
    c.ntfyTopic = await prompt('ntfy.sh topic for real iPhone push (optional, blank to skip): ');
    fs.writeFileSync(CFG_PATH, JSON.stringify(c, null, 2), { mode: 0o600 });
    console.log('Saved ' + CFG_PATH + '\n');
  }
  cfg = { ...defaults, ...c };
  cfg.relay = String(cfg.relay || '').replace(/\/+$/, '');
  if (!cfg.relay || String(cfg.token || '').length < 16) throw new Error('config.json needs "relay" and a "token" of 16+ characters');
  for (const d of ['Received', 'Screenshots']) fs.mkdirSync(path.join(cfg.shareDir, d), { recursive: true });
}

/* ---------------- relay helpers ---------------- */
async function relay(pathq, { method = 'POST', json, body, headers = {} } = {}) {
  const res = await fetch(cfg.relay + pathq, {
    method, body: json ? JSON.stringify(json) : body,
    headers: { 'x-room-token': cfg.token, ...(json ? { 'content-type': 'application/json' } : {}), ...headers }
  });
  if (!res.ok) throw new Error(`relay ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return res;
}
const send = (to, type, extra = {}) => relay('/send', { json: { from: cfg.device, to, type, ...extra } }).catch(e => log('send failed:', e.message));

const MIME = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp', '.pdf': 'application/pdf', '.txt': 'text/plain', '.mp4': 'video/mp4', '.zip': 'application/zip' };
async function uploadFile(full, to) {
  const buf = await fs.promises.readFile(full);
  const q = new URLSearchParams({ name: path.basename(full), mime: MIME[path.extname(full).toLowerCase()] || 'application/octet-stream', from: cfg.device, to });
  return (await relay('/upload?' + q, { body: buf, headers: { 'content-type': 'application/octet-stream' } })).json();
}
async function downloadFile(msg) {
  const res = await relay('/file/' + encodeURIComponent(msg.fileId), { method: 'GET' });
  const dir = path.join(cfg.shareDir, 'Received');
  let dest = path.join(dir, path.basename(String(msg.name || 'file')).replace(/[<>:"/\\|?*\x00-\x1f]/g, '_'));
  if (fs.existsSync(dest)) dest = path.join(dir, Date.now() + '-' + path.basename(dest));
  await pipeline(Readable.fromWeb(res.body), fs.createWriteStream(dest));
  return dest;
}

/* ---------------- OS helpers ---------------- */
function run(file, args, { env = {}, timeout = 30000 } = {}) {
  return new Promise(resolve => {
    const p = execFile(file, args, { env: { ...process.env, ...env }, timeout, windowsHide: true, maxBuffer: 4e6 },
      (err, so, se) => resolve({ ok: !err, out: String(so || '').trim(), err: String(se || err?.message || '').trim() }));
    p.on('error', () => {});
    p.stdin?.end();
  });
}
const ps = (script, env) => run('powershell', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script], { env });

function safePath(p) {
  const real = x => { let cur = path.resolve(x), rest = ''; while (!fs.existsSync(cur)) { rest = path.join(path.basename(cur), rest); cur = path.dirname(cur); } return path.join(fs.realpathSync(cur), rest); };
  const full = real(path.resolve(cfg.shareDir, String(p || '.')));
  for (const root of [cfg.shareDir, ...cfg.allowedDirs].map(real)) {
    const rel = path.relative(root, full);
    if (rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel))) return full;
  }
  throw new Error('Path is outside the shared folders (' + cfg.shareDir + ').');
}

async function localNotify(title, body) {
  title = clip(title || 'SiriAI', 100); body = clip(body || '', 300);
  const env = { SA_TITLE: title, SA_BODY: body };
  if (P === 'win32') {
    const child = spawn('powershell', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command',
      "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; $n=New-Object System.Windows.Forms.NotifyIcon; $n.Icon=[System.Drawing.SystemIcons]::Information; $n.Visible=$true; $n.ShowBalloonTip(6000,$env:SA_TITLE,$env:SA_BODY,'None'); Start-Sleep 7; $n.Dispose()"],
      { env: { ...process.env, ...env }, stdio: 'ignore', detached: true, windowsHide: true });
    child.on('error', () => {}); child.unref();
  } else if (P === 'darwin') {
    run('osascript', ['-e', 'display notification (system attribute "SA_BODY") with title (system attribute "SA_TITLE")'], { env });
  } else run('notify-send', [title, body]);
}

async function notifyPhone(title, body) {
  const out = [];
  await send('*', 'notify', { title, body, app: 'laptop' }); out.push('sent to connected devices');
  if (cfg.ntfyTopic) {
    try {
      const r = await fetch('https://ntfy.sh', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ topic: cfg.ntfyTopic, title, message: body }) });
      out.push(r.ok ? 'push sent via ntfy' : 'ntfy error ' + r.status);
    } catch (e) { out.push('ntfy failed: ' + e.message); }
  }
  return out.join('; ');
}

/* ---------------- tools the AI (and the phone) can use ---------------- */
const T = {};
const S = d => ({ type: 'string', description: d });
function tool(name, description, props, required, fn) {
  T[name] = { def: { name, description, input_schema: { type: 'object', properties: props, required } }, fn };
}
const WIN_OPEN = `$n=$env:SA_NAME; $a=Get-StartApps | Where-Object { $_.Name -like "*$n*" } | Select-Object -First 1; if($a){ Start-Process "shell:AppsFolder\\$($a.AppID)"; "Opened $($a.Name)" } else { try { Start-Process $n -ErrorAction Stop; "Opened $n" } catch { "Could not find an app called $n" } }`;

tool('open_app', 'Open an application on the laptop by name (e.g. Chrome, Spotify, Notepad, WhatsApp).', { name: S('App name') }, ['name'], async ({ name }) => {
  if (P === 'win32') return (await ps(WIN_OPEN, { SA_NAME: String(name) })).out || 'Done.';
  if (P === 'darwin') { const r = await run('open', ['-a', String(name)]); return r.ok ? 'Opened ' + name : 'Could not open: ' + r.err; }
  const c = spawn(String(name), [], { detached: true, stdio: 'ignore' }); c.on('error', () => {}); c.unref(); return 'Tried to launch ' + name;
});
tool('list_apps', 'List installed apps (Start menu) on the laptop.', {}, [], async () => {
  if (P === 'win32') return clip((await ps('Get-StartApps | Select-Object -First 150 -ExpandProperty Name')).out);
  if (P === 'darwin') return clip((await run('ls', ['/Applications'])).out);
  return 'Not supported on this OS.';
});
tool('open_url', 'Open a website or app link in the laptop browser/app.', { url: S('URL or app link') }, ['url'], async ({ url }) => {
  url = String(url);
  if (!/^[a-z][a-z0-9+.-]*:/i.test(url) || /^(file|javascript|data|vbscript):/i.test(url)) return 'Refused: only http(s), mailto and app links are allowed.';
  if (P === 'win32') await ps('Start-Process $env:SA_URL', { SA_URL: url });
  else await run(P === 'darwin' ? 'open' : 'xdg-open', [url]);
  return 'Opened ' + url;
});
tool('list_files', 'List files in the shared folder (or a sub-folder).', { path: S('Sub-folder, default is the shared folder root') }, [], async ({ path: p }) => {
  const dir = safePath(p || '.');
  const rows = fs.readdirSync(dir, { withFileTypes: true }).slice(0, 100).map(e => e.isDirectory() ? e.name + '/' : `${e.name} (${fs.statSync(path.join(dir, e.name)).size} bytes)`);
  return rows.join('\n') || '(empty) in ' + dir;
});
tool('read_file', 'Read a text file from the shared folder.', { path: S('File path') }, ['path'], async ({ path: p }) => clip(fs.readFileSync(safePath(p), 'utf8'), 20000));
tool('write_file', 'Create or overwrite a text file in the shared folder.', { path: S('File path'), content: S('Text content') }, ['path', 'content'], async ({ path: p, content }) => {
  const f = safePath(p); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, String(content)); return 'Saved ' + f;
});
tool('send_file', 'Send a file from the shared folder to the phone (or another device).', { path: S('File path'), to: S('Device name, default: whoever asked') }, ['path'], async ({ path: p, to }, ctx) => {
  const f = safePath(p);
  const target = to || (ctx.from && ctx.from !== 'shortcut' ? ctx.from : '*');
  const r = await uploadFile(f, target);
  return `Sent ${path.basename(f)} (${r.size} bytes) to ${target}.`;
});
tool('screenshot', 'Take a screenshot of the laptop screen. Optionally send it to a device.', { send_to: S('Device name to send it to') }, [], async ({ send_to }) => {
  const out = path.join(cfg.shareDir, 'Screenshots', 'shot-' + Date.now() + '.png');
  let ok = false;
  if (P === 'win32') ok = (await ps("Add-Type -AssemblyName System.Windows.Forms,System.Drawing; $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location,[System.Drawing.Point]::Empty,$b.Size); $bmp.Save($env:SA_OUT,[System.Drawing.Imaging.ImageFormat]::Png)", { SA_OUT: out })).ok;
  else if (P === 'darwin') ok = (await run('screencapture', ['-x', out])).ok;
  else ok = (await run('scrot', [out])).ok;
  if (!ok || !fs.existsSync(out)) return 'Screenshot failed.';
  if (send_to) { await uploadFile(out, send_to); return 'Screenshot taken and sent to ' + send_to + '.'; }
  return 'Screenshot saved at ' + out;
});
tool('get_clipboard', 'Read the laptop clipboard text.', {}, [], async () => {
  const r = P === 'win32' ? await ps('Get-Clipboard -Raw') : P === 'darwin' ? await run('pbpaste', []) : await run('xclip', ['-o', '-selection', 'clipboard']);
  return clip(r.out || '(empty)');
});
tool('set_clipboard', 'Put text on the laptop clipboard.', { text: S('Text') }, ['text'], async ({ text }) => {
  if (P === 'win32') await ps('Set-Clipboard -Value $env:SA_TEXT', { SA_TEXT: String(text) });
  else if (P === 'darwin') { const c = spawn('pbcopy'); c.stdin.end(String(text)); }
  else { const c = spawn('xclip', ['-selection', 'clipboard']); c.on('error', () => {}); c.stdin.end(String(text)); }
  return 'Copied.';
});
const KEYS = { up: 175, down: 174, mute: 173, playpause: 179, next: 176, prev: 177 };
tool('media_key', 'Press a media key on the laptop: up, down, mute, playpause, next, prev (volume keys can repeat).', { action: S('up|down|mute|playpause|next|prev'), times: { type: 'number', description: 'Repeat count, default 1' } }, ['action'], async ({ action, times }) => {
  if (P !== 'win32') return 'Media keys are only supported on Windows in this version.';
  const code = KEYS[action]; if (!code) return 'Unknown action.';
  const n = Math.min(Math.max(+times || 1, 1), 25);
  await ps(`1..${n} | ForEach-Object { (New-Object -ComObject WScript.Shell).SendKeys([char]${code}) }`);
  return `Pressed ${action} x${n}.`;
});
tool('type_text', 'Type text into whatever window currently has focus on the laptop.', { text: S('Text to type') }, ['text'], async ({ text }) => {
  if (P !== 'win32') return 'Typing is only supported on Windows in this version.';
  await ps("$t=$env:SA_TEXT -replace '([+^%~(){}\\[\\]])','{$1}'; (New-Object -ComObject WScript.Shell).SendKeys($t)", { SA_TEXT: String(text) });
  return 'Typed.';
});
tool('lock_screen', 'Lock the laptop screen.', {}, [], async () => {
  if (P === 'win32') await run('rundll32.exe', ['user32.dll,LockWorkStation']);
  else if (P === 'darwin') await run('pmset', ['displaysleepnow']);
  else return 'Not supported on this OS.';
  return 'Locked.';
});
tool('system_info', 'Battery, memory, uptime and basic info about the laptop.', {}, [], async () => {
  const info = { host: os.hostname(), os: `${os.type()} ${os.release()}`, uptime_hours: +(os.uptime() / 3600).toFixed(1), cpu: os.cpus()[0]?.model, mem_free_gb: +(os.freemem() / 1e9).toFixed(1), mem_total_gb: +(os.totalmem() / 1e9).toFixed(1) };
  if (P === 'win32') { const b = await ps('(Get-CimInstance Win32_Battery | Select-Object -First 1).EstimatedChargeRemaining'); if (b.out) info.battery_percent = +b.out; }
  return JSON.stringify(info);
});
tool('show_notification', 'Show a desktop notification on the laptop.', { title: S('Title'), body: S('Body') }, ['title'], async ({ title, body }) => { await localNotify(title, body); return 'Shown.'; });
tool('notify_phone', 'Send a notification to the phone (real push if ntfy is configured).', { title: S('Title'), body: S('Body') }, ['title'], async ({ title, body }) => notifyPhone(title, body || ''));
tool('set_timer', 'After N minutes, notify the laptop and the phone (agent must stay running).', { minutes: { type: 'number' }, message: S('Message') }, ['minutes', 'message'], async ({ minutes, message }) => {
  const m = Math.min(Math.max(+minutes || 1, 0.05), 24 * 60);
  setTimeout(() => { localNotify('SiriAI timer', message); notifyPhone('SiriAI timer', message); }, m * 60000);
  return `Timer set for ${m} minutes.`;
});
tool('run_command', 'Run a shell command on the laptop. Disabled unless allowShell is true; each command needs approval at the laptop.', { command: S('Command') }, ['command'], async ({ command }, ctx) => {
  if (!cfg.allowShell) return 'Shell access is disabled. Set "allowShell": true in agent/config.json to enable it.';
  if (!(await confirm(`\nCommand from ${ctx.from}: ${command}\nRun it?`))) return 'The user did not approve the command.';
  const r = P === 'win32' ? await ps(String(command)) : await run('/bin/sh', ['-c', String(command)]);
  return clip(`${r.ok ? 'OK' : 'FAILED'}\n${r.out}\n${r.err}`);
});

async function callTool(name, args, ctx) {
  const t = T[name];
  if (!t) return 'Unknown tool.';
  try { return clip(await t.fn(args || {}, ctx)); } catch (e) { return 'Error: ' + e.message; }
}

/* ---------------- AI ---------------- */
const histories = new Map();
const systemPrompt = () => `You are SiriAI, an assistant running on the user's laptop (${os.hostname()}, ${P}). The user talks to you from their iPhone or from the laptop; replies appear in a small chat, so be concise. Use your tools to open apps, manage files in the shared folder (${cfg.shareDir}), send files to the phone, take screenshots, control media, type text and send notifications. Ask before doing anything destructive or sensitive. You cannot read notifications from other apps or control the iPhone itself; say so if asked. Current time: ${new Date().toString()}.`;

async function ai(from, text) {
  if (!cfg.apiKey) return 'The laptop agent has no Anthropic API key. Add "apiKey" to agent/config.json.';
  const hist = histories.get(from) || [];
  const messages = [...hist, { role: 'user', content: text }];
  const tools = Object.values(T).map(t => t.def);
  let final = '';
  for (let i = 0; i < 8; i++) {
    const r = await fetch(cfg.apiBase.replace(/\/+$/, '') + '/v1/messages', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': cfg.apiKey, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({ model: cfg.model, max_tokens: 1024, system: systemPrompt(), tools, messages })
    });
    if (!r.ok) return 'AI error ' + r.status + ': ' + (await r.text()).slice(0, 200);
    const j = await r.json();
    messages.push({ role: 'assistant', content: j.content });
    final = j.content.filter(b => b.type === 'text').map(b => b.text).join('\n');
    if (j.stop_reason !== 'tool_use') break;
    const results = [];
    for (const b of j.content) if (b.type === 'tool_use') {
      log('tool:', b.name, JSON.stringify(b.input).slice(0, 120));
      results.push({ type: 'tool_result', tool_use_id: b.id, content: await callTool(b.name, b.input, { from }) });
    }
    messages.push({ role: 'user', content: results });
  }
  hist.push({ role: 'user', content: text }, { role: 'assistant', content: final || 'Done.' });
  histories.set(from, hist.slice(-20));
  return final || 'Done.';
}

/* ---------------- message handling ---------------- */
let chain = Promise.resolve();
const enqueue = fn => { chain = chain.then(fn).catch(e => log('error:', e.message)); };
const seen = new Set();

async function onMessage(m) {
  if (seen.has(m.mid)) return; seen.add(m.mid); if (seen.size > 1000) seen.delete(seen.values().next().value);
  if (m.ts) lastTs = Math.max(lastTs, m.ts);
  switch (m.type) {
    case 'chat':
      log(`chat from ${m.from}:`, clip(m.text, 120));
      enqueue(async () => send(m.from, 'chat_reply', { reqId: m.reqId, text: clip(await ai(m.from, String(m.text || '')), 18000) }));
      break;
    case 'cmd':
      log(`cmd from ${m.from}:`, m.name);
      enqueue(async () => {
        const args = { ...(m.args || {}) };
        if (m.name === 'screenshot' && !args.send_to) args.send_to = m.from;
        send(m.from, 'cmd_result', { reqId: m.reqId, name: m.name, result: await callTool(m.name, args, { from: m.from }) });
      });
      break;
    case 'file':
      enqueue(async () => {
        const dest = await downloadFile(m);
        log(`received ${m.name} from ${m.from} -> ${dest}`);
        localNotify('File received', `${m.name} from ${m.from}`);
        send(m.from, 'file_saved', { name: m.name, text: 'Saved on laptop: ' + dest });
      });
      break;
    case 'notify':
      log(`notification from ${m.from}:`, m.title, '-', m.body);
      localNotify(m.title || 'Notification', m.body || '');
      break;
  }
}

/* ---------------- connection ---------------- */
let lastTs = 0;
async function connect() {
  let backoff = 1000;
  for (;;) {
    try {
      const q = new URLSearchParams({ device: cfg.device }); if (lastTs) q.set('since', String(lastTs));
      const res = await fetch(`${cfg.relay}/events?${q}`, { headers: { 'x-room-token': cfg.token, accept: 'text/event-stream' } });
      if (!res.ok) throw new Error('HTTP ' + res.status + (res.status === 401 ? ' (wrong room token)' : ''));
      log('connected to relay as', cfg.device); backoff = 1000;
      const dec = new TextDecoder(); let buf = '';
      for await (const chunk of res.body) {
        buf += dec.decode(chunk, { stream: true });
        let i;
        while ((i = buf.indexOf('\n\n')) >= 0) {
          const block = buf.slice(0, i); buf = buf.slice(i + 2);
          let ev = 'message', data = '';
          for (const line of block.split('\n')) { if (line.startsWith('event:')) ev = line.slice(6).trim(); else if (line.startsWith('data:')) data += line.slice(5).trim(); }
          if (ev === 'msg' && data) { try { onMessage(JSON.parse(data)); } catch (e) { log('bad message:', e.message); } }
          else if (ev === 'presence' && data) { try { log('online:', JSON.parse(data).devices.join(', ')); } catch {} }
        }
      }
      log('disconnected, retrying…');
    } catch (e) { log('relay connection problem:', e.message); }
    await sleep(backoff); backoff = Math.min(backoff * 2, 30000);
  }
}

(async () => {
  await loadConfig();
  console.log(`\nSiriAI laptop agent "${cfg.device}"\n  relay:      ${cfg.relay}\n  shared dir: ${cfg.shareDir}\n  shell:      ${cfg.allowShell ? 'ENABLED (asks approval each time)' : 'disabled'}\n  phone push: ${cfg.ntfyTopic ? 'ntfy topic set' : 'off'}\n`);
  await connect();
})().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
