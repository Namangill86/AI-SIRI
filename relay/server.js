'use strict';
/**
 * SiriAI relay: zero-dependency message + file hub for your own devices.
 * Auth: one shared secret (room token, 16+ chars). Set ROOM_TOKEN to lock the server to your token only.
 * Transport: HTTPS + Server-Sent Events (works through every proxy/tunnel).
 */
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const PORT = +process.env.PORT || 8787;
const ROOM_TOKEN = process.env.ROOM_TOKEN || '';
const MAX_BYTES = (+process.env.MAX_MB || 100) * 1024 * 1024;
const FILE_TTL = (+process.env.FILE_TTL_HOURS || 24) * 3600 * 1000;
const RATE = +process.env.RATE_PER_MIN || 600;
const DIR = process.env.DATA_DIR || path.join(os.tmpdir(), 'siriai-relay');
fs.rmSync(DIR, { recursive: true, force: true });
fs.mkdirSync(DIR, { recursive: true });

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, x-room-token, authorization',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
};
const rooms = new Map();
const hits = new Map();

const sha = t => crypto.createHash('sha256').update(t).digest('hex').slice(0, 24);
const eq = (a, b) => { const A = Buffer.from(a), B = Buffer.from(b); return A.length === B.length && crypto.timingSafeEqual(A, B); };
const clean = (s, star) => (star && s === '*') ? '*' : String(s).replace(/[^\w.-]/g, '').slice(0, 32);
const cleanName = s => path.basename(String(s)).replace(/[\x00-\x1f<>:"/\\|?*]+/g, '_').slice(0, 120) || 'file';

function limited(key, max) {
  const now = Date.now();
  let h = hits.get(key);
  if (!h || h.t < now) { h = { t: now + 60000, n: 0 }; hits.set(key, h); }
  return ++h.n > max;
}
function tokenOf(req, url) {
  const h = req.headers['x-room-token'] || (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  return h || url.searchParams.get('t') || '';
}
function getRoom(token) {
  if (!token || token.length < 16) return null;
  if (ROOM_TOKEN && !eq(token, ROOM_TOKEN)) return null;
  const id = sha(token);
  let r = rooms.get(id);
  if (!r) { r = { clients: new Map(), log: [], seq: 0, files: new Map(), pending: new Map() }; rooms.set(id, r); }
  return r;
}
function json(res, code, obj) {
  if (res.headersSent) return;
  const b = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(b), ...CORS });
  res.end(b);
}
function readBody(req, limit) {
  return new Promise((ok, fail) => {
    const c = []; let n = 0;
    req.on('data', d => { n += d.length; if (n > limit) { fail(Object.assign(new Error('too large'), { code: 413 })); req.destroy(); return; } c.push(d); });
    req.on('end', () => ok(Buffer.concat(c)));
    req.on('error', fail);
  });
}
const sse = (res, event, data) => res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
const online = (r, dev) => (r.clients.get(dev)?.size || 0) > 0;
const devices = r => [...r.clients].filter(([, s]) => s.size).map(([d]) => d);
const forMe = (m, dev) => m.to === '*' ? m.from !== dev : m.to === dev;

function presence(r) {
  const d = devices(r);
  for (const set of r.clients.values()) for (const res of set) sse(res, 'presence', { devices: d });
}
function deliver(r, msg) {
  msg.mid = crypto.randomUUID(); msg.ts = Date.now(); msg.id = ++r.seq;
  r.log.push(msg); if (r.log.length > 300) r.log.shift();
  for (const [dev, set] of r.clients) if (forMe(msg, dev)) for (const res of set) sse(res, 'msg', msg);
  return msg;
}

const FIELDS = ['text', 'reqId', 'name', 'args', 'title', 'body', 'app', 'result', 'fileId', 'size', 'mime', 'state'];
function buildMsg(b, from) {
  const m = { from: clean(b.from || from || 'unknown'), to: clean(b.to || '*', true), type: String(b.type || 'msg').slice(0, 32) };
  for (const k of FIELDS) if (b[k] !== undefined) m[k] = typeof b[k] === 'string' ? b[k].slice(0, 50000) : b[k];
  return m;
}

function events(req, res, url, r) {
  const dev = clean(url.searchParams.get('device') || '');
  if (!dev) return json(res, 400, { error: 'device required' });
  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache, no-transform', 'Connection': 'keep-alive', 'X-Accel-Buffering': 'no', ...CORS });
  res.write('retry: 3000\n\n');
  let set = r.clients.get(dev);
  if (!set) { set = new Set(); r.clients.set(dev, set); }
  set.add(res);
  const since = +url.searchParams.get('since') || 0;
  if (since) for (const m of r.log) if (m.ts > since && forMe(m, dev)) sse(res, 'msg', m);
  presence(r);
  const hb = setInterval(() => res.write(': hb\n\n'), 15000);
  res.on('close', () => { clearInterval(hb); set.delete(res); presence(r); });
}

async function upload(req, res, url, r) {
  const name = cleanName(url.searchParams.get('name') || 'file');
  const mime = (url.searchParams.get('mime') || 'application/octet-stream').slice(0, 100);
  const from = clean(url.searchParams.get('from') || 'unknown');
  const to = clean(url.searchParams.get('to') || '*', true);
  if ((+req.headers['content-length'] || 0) > MAX_BYTES) return json(res, 413, { error: 'file too large' });
  const id = crypto.randomUUID();
  const fp = path.join(DIR, id);
  const out = fs.createWriteStream(fp);
  let n = 0, dead = false;
  req.on('data', d => {
    n += d.length;
    if (n > MAX_BYTES && !dead) { dead = true; out.destroy(); fs.rm(fp, () => {}); json(res, 413, { error: 'file too large' }); req.destroy(); }
  });
  req.pipe(out);
  out.on('finish', () => {
    if (dead) return;
    r.files.set(id, { id, name, mime, size: n, path: fp, ts: Date.now() });
    deliver(r, { from, to, type: 'file', fileId: id, name, mime, size: n });
    json(res, 200, { id, name, size: n });
  });
  out.on('error', () => json(res, 500, { error: 'write failed' }));
}

function download(res, url, r, id) {
  const f = r.files.get(id);
  if (!f) return json(res, 404, { error: 'not found or expired' });
  const inline = url.searchParams.get('inline') === '1' && /^image\/(png|jpe?g|gif|webp)$/.test(f.mime);
  res.writeHead(200, {
    'Content-Type': inline ? f.mime : 'application/octet-stream',
    'Content-Disposition': `${inline ? 'inline' : 'attachment'}; filename*=UTF-8''${encodeURIComponent(f.name)}`,
    'Content-Length': f.size, 'X-Content-Type-Options': 'nosniff', 'Cache-Control': 'private, max-age=3600', ...CORS
  });
  fs.createReadStream(f.path).pipe(res);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    if (req.method === 'OPTIONS') { res.writeHead(204, CORS); return res.end(); }
    if (url.pathname === '/' || url.pathname === '/health') return json(res, 200, { ok: true, name: 'siriai-relay' });
    const ip = (req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket.remoteAddress;
    if (limited(ip, RATE)) return json(res, 429, { error: 'slow down' });
    const r = getRoom(tokenOf(req, url));
    if (!r) { limited('bad:' + ip, 1e9); return json(res, (hits.get('bad:' + ip)?.n || 0) > 30 ? 429 : 401, { error: 'bad token' }); }

    const p = url.pathname;
    if (p === '/events' && req.method === 'GET') return events(req, res, url, r);
    if (p === '/upload' && req.method === 'POST') return upload(req, res, url, r);
    if (p.startsWith('/file/') && req.method === 'GET') return download(res, url, r, p.slice(6));
    if (p === '/who') return json(res, 200, { devices: devices(r) });

    if (p === '/send' && req.method === 'POST') {
      const b = JSON.parse((await readBody(req, 256e3)).toString() || '{}');
      const m = buildMsg(b);
      if (m.type === 'chat_reply' && m.reqId && r.pending.has(m.reqId)) {
        const pe = r.pending.get(m.reqId);
        clearTimeout(pe.timer); r.pending.delete(m.reqId);
        json(pe.res, 200, { reply: m.text || '' });
      }
      deliver(r, m);
      return json(res, 200, { ok: true });
    }

    // One-shot request/response for Shortcuts and the native app: ask a device's AI and wait for the answer.
    if (p === '/ask' && req.method === 'POST') {
      const b = JSON.parse((await readBody(req, 256e3)).toString() || '{}');
      const to = clean(b.to || 'laptop');
      if (!online(r, to)) return json(res, 503, { error: to + ' is offline' });
      const reqId = crypto.randomUUID();
      const timer = setTimeout(() => { r.pending.delete(reqId); json(res, 504, { error: 'timed out waiting for ' + to }); }, 90000);
      r.pending.set(reqId, { res, timer });
      res.on('close', () => { clearTimeout(timer); r.pending.delete(reqId); });
      deliver(r, { from: clean(b.from || 'shortcut'), to, type: 'chat', reqId, text: String(b.text || '').slice(0, 20000) });
      return;
    }

    // Simple notification push (iOS Shortcuts automations can call this).
    if (p === '/n') {
      let b = {};
      if (req.method === 'POST') { try { b = JSON.parse((await readBody(req, 64e3)).toString() || '{}'); } catch { b = {}; } }
      const g = k => b[k] ?? url.searchParams.get(k) ?? '';
      deliver(r, { from: 'shortcut', to: clean(g('to') || '*', true), type: 'notify', title: String(g('title')).slice(0, 200), body: String(g('body')).slice(0, 2000), app: String(g('app')).slice(0, 60) });
      return json(res, 200, { ok: true });
    }
    json(res, 404, { error: 'not found' });
  } catch (e) {
    json(res, e.code === 413 ? 413 : 400, { error: e.message });
  }
});
server.requestTimeout = 0;

setInterval(() => {
  const now = Date.now();
  for (const r of rooms.values()) {
    for (const [id, f] of r.files) if (now - f.ts > FILE_TTL) { fs.rm(f.path, () => {}); r.files.delete(id); }
    r.log = r.log.filter(m => now - m.ts < 3600e3);
  }
  for (const [k, h] of hits) if (h.t < now) hits.delete(k);
}, 600000).unref();

server.listen(PORT, () => console.log(`SiriAI relay listening on :${PORT}${ROOM_TOKEN ? ' (locked to ROOM_TOKEN)' : ' (open: any 16+ char token creates a room)'}`));
