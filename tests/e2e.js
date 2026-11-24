'use strict';
// End-to-end test: relay + laptop agent + mock Anthropic API + simulated phone. No internet needed.
const { spawn } = require('child_process');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const TOKEN = 'test-token-0123456789abcdef';
const RELAY = 'http://127.0.0.1:18787';
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'siriai-'));
const share = path.join(tmp, 'share');
fs.mkdirSync(share, { recursive: true });
fs.writeFileSync(path.join(share, 'hello.txt'), 'hello from laptop');
fs.writeFileSync(path.join(tmp, 'config.json'), JSON.stringify({ relay: RELAY, token: TOKEN, apiKey: 'x', device: 'laptop', apiBase: 'http://127.0.0.1:18788', shareDir: share }));

let pass = 0, fail = 0;
const ok = (c, m) => { c ? (pass++, console.log('  ✓', m)) : (fail++, console.log('  ✗', m)); };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const H = { 'x-room-token': TOKEN, 'content-type': 'application/json' };
const post = (p, b) => fetch(RELAY + p, { method: 'POST', headers: H, body: JSON.stringify(b) });

const mock = http.createServer((req, res) => {
  let b = ''; req.on('data', d => b += d);
  req.on('end', () => {
    const j = JSON.parse(b); const last = j.messages[j.messages.length - 1];
    const tool = (name, input) => ({ stop_reason: 'tool_use', content: [{ type: 'tool_use', id: 'tu1', name, input }] });
    let out;
    if (Array.isArray(last.content) && last.content[0]?.type === 'tool_result') out = { stop_reason: 'end_turn', content: [{ type: 'text', text: 'tool said: ' + String(last.content[0].content).slice(0, 500) }] };
    else if (String(last.content).includes('sysinfo')) out = tool('system_info', {});
    else if (String(last.content).includes('sendfile')) out = tool('send_file', { path: 'hello.txt' });
    else if (String(last.content).includes('escape')) out = tool('read_file', { path: '../../etc/passwd' });
    else out = { stop_reason: 'end_turn', content: [{ type: 'text', text: 'echo: ' + last.content }] };
    res.setHeader('content-type', 'application/json'); res.end(JSON.stringify(out));
  });
});

async function sseClient(device, onMsg) {
  const res = await fetch(`${RELAY}/events?device=${device}`, { headers: { 'x-room-token': TOKEN } });
  (async () => {
    const dec = new TextDecoder(); let buf = '';
    for await (const c of res.body) {
      buf += dec.decode(c, { stream: true }); let i;
      while ((i = buf.indexOf('\n\n')) >= 0) {
        const blk = buf.slice(0, i); buf = buf.slice(i + 2);
        const ev = /event: (\w+)/.exec(blk)?.[1]; const d = /data: (.*)/.exec(blk)?.[1];
        if (ev === 'msg' && d) onMsg(JSON.parse(d));
      }
    }
  })().catch(() => {});
}

(async () => {
  mock.listen(18788);
  const relay = spawn('node', ['relay/server.js'], { env: { ...process.env, PORT: '18787', ROOM_TOKEN: TOKEN }, stdio: 'ignore' });
  await sleep(500);
  const agent = spawn('node', ['agent/agent.js'], { env: { ...process.env, SIRIAI_CONFIG: path.join(tmp, 'config.json') }, stdio: 'ignore' });
  await sleep(1500);
  try {
    console.log('auth');
    ok((await fetch(RELAY + '/events?device=x', { headers: { 'x-room-token': 'wrong-token-wrong-token' } })).status === 401, 'wrong token rejected');
    ok((await fetch(RELAY + '/health')).ok, 'health endpoint open');
    ok(JSON.stringify(await (await fetch(RELAY + '/who', { headers: H })).json()).includes('laptop'), 'agent is online');

    console.log('ask (shortcut-style request/response)');
    let r = await (await post('/ask', { text: 'hi there', from: 'shortcut' })).json();
    ok(r.reply === 'echo: hi there', 'AI reply returned: ' + r.reply);
    r = await (await post('/ask', { text: 'run sysinfo please', from: 'shortcut' })).json();
    ok(/tool said: .*mem_total_gb/.test(r.reply), 'AI tool loop works (system_info)');
    r = await (await post('/ask', { text: 'escape the folder', from: 'shortcut' })).json();
    ok(/outside the shared folders/.test(r.reply), 'path traversal blocked');

    console.log('phone <-> laptop');
    const phone = []; await sseClient('iphone', m => phone.push(m)); await sleep(300);
    await post('/send', { from: 'iphone', to: 'laptop', type: 'chat', reqId: 'r1', text: 'sendfile now' });
    await sleep(1500);
    const fileMsg = phone.find(m => m.type === 'file');
    ok(!!fileMsg && fileMsg.name === 'hello.txt', 'laptop sent file to phone');
    if (fileMsg) {
      const dl = await fetch(`${RELAY}/file/${fileMsg.fileId}`, { headers: H });
      ok((await dl.text()) === 'hello from laptop', 'phone downloaded identical file');
    }
    ok(phone.some(m => m.type === 'chat_reply' && m.reqId === 'r1'), 'chat_reply routed to phone');

    const up = await fetch(`${RELAY}/upload?name=photo.jpg&mime=image/jpeg&from=iphone&to=laptop`, { method: 'POST', headers: { 'x-room-token': TOKEN }, body: Buffer.from('FAKEJPEGDATA') });
    ok(up.ok, 'phone uploaded a photo');
    await sleep(1200);
    ok(fs.existsSync(path.join(share, 'Received', 'photo.jpg')) && fs.readFileSync(path.join(share, 'Received', 'photo.jpg'), 'utf8') === 'FAKEJPEGDATA', 'laptop saved the photo in Received/');

    await post('/send', { from: 'iphone', to: 'laptop', type: 'cmd', reqId: 'c1', name: 'list_files', args: {} });
    await sleep(800);
    ok(phone.some(m => m.type === 'cmd_result' && /hello\.txt/.test(m.result)), 'direct command works (list_files)');

    console.log('notifications');
    ok((await post('/n', { title: 'Test', body: 'Hello', app: 'Messages' })).ok, 'notification endpoint accepts a Shortcuts-style POST');
    await sleep(300);
    ok(phone.some(m => m.type === 'notify' && m.title === 'Test'), 'notification delivered to phone');

    console.log('offline');
    agent.kill(); await sleep(500);
    ok((await post('/ask', { text: 'x', to: 'laptop' })).status === 503, '/ask returns 503 when laptop is offline');
  } catch (e) { fail++; console.log('  ✗ exception', e); }
  relay.kill(); mock.close();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
