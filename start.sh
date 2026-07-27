#!/bin/sh
set -e

PORT="${PORT:-7860}"

pip3 install --break-system-packages --no-cache-dir aiohttp >/dev/null

cat > server.py <<'PYEOF'
import asyncio, os, time
from aiohttp import web, WSMsgType

PORT = int(os.environ.get("PORT", 7860))

HTML = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ping</title>
<style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0b0d12;font-family:ui-monospace,Menlo,Consolas,monospace;color:#e6e8ee}
.card{width:min(420px,90vw);border:1px solid #1f2430;border-radius:16px;padding:32px;background:#11141c;box-shadow:0 20px 60px rgba(0,0,0,.4)}
.status{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#6b7280;margin-bottom:8px}
.now{font-size:64px;font-weight:700;line-height:1;display:flex;align-items:baseline;gap:8px}
.unit{font-size:20px;color:#6b7280;font-weight:400}
.dot{width:10px;height:10px;border-radius:50%;background:#3fb950;display:inline-block;margin-right:8px;box-shadow:0 0 8px #3fb950}
.dot.bad{background:#f85149;box-shadow:0 0 8px #f85149}
.dot.mid{background:#e3b341;box-shadow:0 0 8px #e3b341}
.grid{margin-top:24px;display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px;text-align:center}
.grid div span{display:block;font-size:11px;color:#6b7280;text-transform:uppercase;letter-spacing:.06em;margin-bottom:4px}
.grid div b{font-size:18px}
</style></head>
<body>
<div class="card">
  <div class="status"><span class="dot" id="dot"></span><span id="state">connecting</span></div>
  <div class="now"><span id="now">--</span><span class="unit">ms</span></div>
  <div class="grid">
    <div><span>min</span><b id="min">--</b></div>
    <div><span>avg</span><b id="avg">--</b></div>
    <div><span>max</span><b id="max">--</b></div>
  </div>
</div>
<script>
const proto = location.protocol === "https:" ? "wss" : "ws";
const ws = new WebSocket(proto + "://" + location.host + "/ws");
let samples = [];
const $ = id => document.getElementById(id);
ws.onopen = () => { $("state").textContent = "connected"; tick(); };
ws.onclose = () => { $("state").textContent = "disconnected"; $("dot").className = "dot bad"; };
ws.onerror = () => { $("state").textContent = "error"; $("dot").className = "dot bad"; };
ws.onmessage = e => {
  const rtt = performance.now() - Number(e.data);
  samples.push(rtt);
  if (samples.length > 30) samples.shift();
  $("now").textContent = rtt.toFixed(0);
  $("min").textContent = Math.min(...samples).toFixed(0);
  $("max").textContent = Math.max(...samples).toFixed(0);
  $("avg").textContent = (samples.reduce((a,b)=>a+b,0)/samples.length).toFixed(0);
  $("dot").className = "dot" + (rtt < 80 ? "" : rtt < 200 ? " mid" : " bad");
  setTimeout(tick, 500);
};
function tick(){ if (ws.readyState === 1) ws.send(String(performance.now())); }
</script>
</body></html>"""

async def index(request):
    return web.Response(text=HTML, content_type="text/html")

async def ws_handler(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    async for msg in ws:
        if msg.type == WSMsgType.TEXT:
            await ws.send_str(msg.data)
        elif msg.type == WSMsgType.ERROR:
            break
    return ws

app = web.Application()
app.router.add_get("/", index)
app.router.add_get("/ws", ws_handler)

if __name__ == "__main__":
    web.run_app(app, host="0.0.0.0", port=PORT)
PYEOF

cat > run.sh <<EOF
#!/bin/sh
exec python3 server.py
EOF

chmod +x run.sh
