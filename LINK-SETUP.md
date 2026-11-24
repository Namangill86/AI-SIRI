# SiriAI Link: laptop <-> iPhone over the internet

```
 iPhone (app / Siri / Shortcuts / hub web page)
        |  HTTPS
     [ relay ]  <-- your own tiny server (Render free tier, or your laptop + a tunnel)
        |  HTTPS (the laptop connects OUT, no open ports)
 Laptop agent (Node.js)  -> AI + tools: open apps, files, screenshots, media keys, typing, notifications
```

## 1. Run the relay (once)
**Option A, Render (free, permanent URL)**
1. Push this repo to GitHub. On render.com: New -> Blueprint (it reads `render.yaml`) or New -> Web Service,
   build command `echo ok`, start command `node relay/server.js`.
2. Add environment variable `ROOM_TOKEN` = a long random secret (24+ characters). Only this token can use your relay.
3. Your URL looks like `https://siriai-relay-xxxx.onrender.com`. (Free instances sleep after idle; the first request
   can take ~30-60 s to wake it, and uploaded files are deleted on restart.)

**Option B, your own laptop + Cloudflare tunnel**
`node relay/server.js` then `cloudflared tunnel --url http://localhost:8787` (winget install Cloudflare.cloudflared)
and use the printed https URL. The URL changes each time you restart the tunnel.

## 2. Start the laptop agent
1. Install Node.js LTS (nodejs.org). Copy the `agent` folder to the laptop.
2. Double-click `start-agent.bat` (or `node agent.js`). First run asks for: relay URL, room token (same as ROOM_TOKEN),
   Anthropic API key, laptop name, optional ntfy topic. It saves `config.json`.
3. Files you share land in `~/SiriAI-Share/Received`. The AI can only touch files inside `~/SiriAI-Share`
   (plus folders you add to `allowedDirs`).
4. Auto-start: press Win+R, type `shell:startup`, drop a shortcut to `start-agent.bat` there.

## 3. Connect the iPhone
- **Hub page** (works on iPhone and laptop browsers): host `docs/` with GitHub Pages (public repo) or open
  `docs/hub.html` locally. Settings (gear) -> relay URL + token -> Save. On iPhone use Share -> Add to Home Screen.
  You get: chat with the laptop AI, quick buttons (screenshot, lock, media, status), 📎 send files/photos,
  incoming files with preview, drag-and-drop on the laptop.
- **Native app / Siri**: SiriAI settings -> "Laptop link" -> same URL + token. Then:
  "Hey Siri, ask my laptop with SiriAI" or tell the in-app AI "open Spotify on my laptop".
- **Send photos/files from the iPhone Share Sheet**: Shortcuts app -> new shortcut -> action "Send to Laptop" (SiriAI)
  -> shortcut settings -> "Show in Share Sheet". Then Photos -> Share -> your shortcut.

## 4. Notifications (what is and isn't possible)
- iOS gives NO app access to other apps' notifications, and nothing here can bypass that.
- Real options:
  - **Windows Phone Link** (Microsoft) mirrors iPhone calls, messages and notifications to a Windows PC over Bluetooth.
  - **Shortcuts automations** can forward things iOS allows (when a Message/Email arrives, battery low, etc.): action
    "Get Contents of URL" -> `POST https://YOUR-RELAY/n` with header `x-room-token: YOUR_TOKEN`, JSON body
    `{"title":"Message","body":"<Shortcut Input>","app":"Messages"}`. It shows up on the laptop as a desktop notification.
  - **Laptop -> iPhone**: the AI's `notify_phone` tool shows in the hub and, if you set `ntfyTopic` (install the free ntfy
    app and subscribe to that topic), arrives as a real iPhone push notification.
- Reading Windows notifications is not included (needs a packaged Windows app).

## Security
- The room token is the key to everything: use 24+ random characters, set `ROOM_TOKEN` on the relay, keep HTTPS.
- Anyone with the token can drive your laptop agent. Anything sensitive should be confirmed on the laptop.
- Shell access is OFF. If you set `"allowShell": true`, every command still needs a y/N approval in the agent window.
- The relay deletes files after 24 h (FILE_TTL_HOURS) and keeps no database.

## Test (no internet needed)
`npm test` runs relay + agent + a mock AI + a simulated phone (15 checks).
