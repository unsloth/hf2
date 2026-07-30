#!/bin/sh set -e

PORT="${PORT:-7860}"

pip3 install --break-system-packages --no-cache-dir aiohttp >/dev/null

cat > server.py <<'PYEOF' import asyncio, os, time from aiohttp import web,
WSMsgType

PORT = int(os.environ.get("PORT", 7860))

HTML = """<!doctype html>

async def index(request): return web.Response(text=HTML,
content_type="text/html")

async def ws_handler(request): ws = web.WebSocketResponse() await
ws.prepare(request) async for msg in ws: if msg.type == WSMsgType.TEXT: await
ws.send_str(msg.data) elif msg.type == WSMsgType.ERROR: break return ws

app = web.Application() app.router.add_get("/", index) app.router.add_get("/ws",
ws_handler)

if name == "main": web.run_app(app, host="0.0.0.0", port=PORT) PYEOF

cat > run.sh <<EOF #!/bin/sh exec python3 server.py EOF

chmod +x run.sh
