#!/bin/sh
set -e
echo "== apt =="
apt-get update && apt-get install -y --no-install-recommends curl ca-certificates python3 python3-pip
echo "== pip =="
pip3 install --break-system-packages --no-cache-dir aiohttp
echo "== jdk =="
curl -fL -o jdk.tar.gz https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jre/hotspot/normal/eclipse
mkdir -p jdk21
tar -xzf jdk.tar.gz -C jdk21 --strip-components=1
rm jdk.tar.gz
export PATH="/app/jdk21/bin:$PATH"
java -version

echo "== paper version lookup =="
VJSON=$(curl -fsS https://fill.papermc.io/v3/projects/paper) || { echo "FATAL: version lookup request failed"; exit 1; }
MCVER=$(echo "$VJSON" | grep -o '"[0-9]*\.[0-9]*\.[0-9]*"' | tail -1 | tr -d '"')
if [ -z "$MCVER" ]; then echo "FATAL: could not parse mc version. Raw response:"; echo "$VJSON"; exit 1; fi
echo "mcver=$MCVER"

echo "== paper build lookup =="
BJSON=$(curl -fsS "https://fill.papermc.io/v3/projects/paper/versions/${MCVER}/builds") || { echo "FATAL: build lookup request failed"; exit 1; }
BUILD=$(echo "$BJSON" | grep -o '"id":[0-9]*' | tail -1 | grep -o '[0-9]*')
if [ -z "$BUILD" ]; then echo "FATAL: could not parse build. Raw response:"; echo "$BJSON"; exit 1; fi
echo "build=$BUILD"

echo "== paper jar download =="
DLURL="https://fill.papermc.io/v3/projects/paper/versions/${MCVER}/builds/${BUILD}/downloads/paper-${MCVER}-${BUILD}.jar"
echo "url=$DLURL"
curl -fL -o server.jar "$DLURL"
ls -la server.jar
echo eula=true > eula.txt

echo "== writing panel.py =="
cat > panel.py <<'PYEOF'
import os, subprocess, threading, collections
from aiohttp import web

PORT = int(os.environ.get("PORT", 7860))
LOG = collections.deque(maxlen=500)
proc = None
lock = threading.Lock()

def read_output():
    for line in proc.stdout:
        LOG.append(line.rstrip())

def start_server():
    global proc
    with lock:
        if proc and proc.poll() is None:
            return
        proc = subprocess.Popen(
            ["java", "-Xms5G", "-Xmx5G", "-jar", "server.jar", "--nogui"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1
        )
        threading.Thread(target=read_output, daemon=True).start()

def stop_server():
    with lock:
        if proc and proc.poll() is None:
            try:
                proc.stdin.write("stop\n")
                proc.stdin.flush()
            except Exception:
                proc.terminate()

HTML = """<!doctype html>
<html><head><title>Panel</title>
<style>body{background:#111;color:#0f0;font-family:monospace}pre{white-space:pre-wrap;height:400px;overflow-y:scroll;background:#000;padding:10px}input,button{padding:6px;margin:4px}</style>
</head><body>
<h2>Minecraft Panel</h2>
<button onclick="fetch('/start',{method:'POST'})">Start</button>
<button onclick="fetch('/stop',{method:'POST'})">Stop</button>
<span id="status"></span>
<pre id="log"></pre>
<input id="cmd" placeholder="command" onkeydown="if(event.key==='Enter')sendCmd()">
<button onclick="sendCmd()">Send</button>
<script>
function sendCmd(){
  const c=document.getElementById('cmd');
  fetch('/cmd',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'cmd='+encodeURIComponent(c.value)});
  c.value='';
}
async function refresh(){
  const l=await fetch('/logs'); document.getElementById('log').textContent=await l.text();
  document.getElementById('log').scrollTop=document.getElementById('log').scrollHeight;
  const s=await fetch('/status'); const j=await s.json();
  document.getElementById('status').textContent=j.running?'RUNNING':'STOPPED';
}
setInterval(refresh,2000);
refresh();
</script>
</body></html>"""

async def index(request):
    return web.Response(text=HTML, content_type="text/html")

async def logs(request):
    return web.Response(text="\n".join(LOG))

async def status(request):
    running = proc is not None and proc.poll() is None
    return web.json_response({"running": running})

async def send_cmd(request):
    data = await request.post()
    cmd = data.get("cmd", "")
    with lock:
        if proc and proc.poll() is None and cmd:
            proc.stdin.write(cmd + "\n")
            proc.stdin.flush()
    return web.Response(text="ok")

async def start_route(request):
    start_server()
    return web.Response(text="ok")

async def stop_route(request):
    stop_server()
    return web.Response(text="ok")

app = web.Application()
app.router.add_get("/", index)
app.router.add_get("/logs", logs)
app.router.add_get("/status", status)
app.router.add_post("/cmd", send_cmd)
app.router.add_post("/start", start_route)
app.router.add_post("/stop", stop_route)

if __name__ == "__main__":
    start_server()
    web.run_app(app, host="0.0.0.0", port=PORT)
PYEOF
cat > run.sh <<'EOF'
#!/bin/sh
export PATH="/app/jdk21/bin:$PATH"
exec python3 panel.py
EOF
chmod +x run.sh
echo "== start.sh complete =="
