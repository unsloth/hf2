#!/bin/sh
set -e

PORT="${PORT:-7860}"

pip3 install --break-system-packages --no-cache-dir aiohttp >/dev/null

cat > server.py <<'PYEOF'
import asyncio, os, random, json
from aiohttp import web, WSMsgType

PORT = int(os.environ.get("PORT", 7860))

# Game state
players = {}
food = []
next_food_id = 0

def spawn_food():
    global next_food_id
    while len(food) < 35:
        next_food_id += 1
        food.append({
            "id": next_food_id,
            "x": random.randint(20, 780),
            "y": random.randint(20, 580),
            "color": f"hsl({random.randint(0, 360)}, 85%, 65%)"
        })

spawn_food()

HTML = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Multiplayer Arena</title>
  <style>
    :root { color-scheme: dark; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #0b0d12;
      color: #e6e8ee;
      font-family: ui-monospace, Menlo, Consolas, system-ui, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      overflow: hidden;
    }
    .header {
      margin-bottom: 12px;
      text-align: center;
    }
    .header h1 { font-size: 20px; font-weight: 700; color: #58a6ff; letter-spacing: -0.02em; }
    .header p { font-size: 13px; color: #8b949e; margin-top: 4px; }
    #game-container {
      position: relative;
      border: 1px solid #1f2430;
      border-radius: 16px;
      overflow: hidden;
      box-shadow: 0 20px 60px rgba(0,0,0,.5);
    }
    canvas { display: block; background: #11141c; }
    #leaderboard {
      position: absolute;
      top: 12px;
      right: 12px;
      background: rgba(17, 20, 28, 0.85);
      border: 1px solid #1f2430;
      border-radius: 8px;
      padding: 10px 14px;
      font-size: 12px;
      min-width: 150px;
      backdrop-filter: blur(6px);
    }
    #leaderboard h3 { font-size: 11px; text-transform: uppercase; color: #6b7280; margin-bottom: 6px; letter-spacing: 0.06em; }
    .p-row { display: flex; justify-content: space-between; margin-bottom: 4px; gap: 12px; }
    .p-row.me { font-weight: bold; color: #3fb950; }
    #status {
      position: absolute;
      top: 12px;
      left: 12px;
      font-size: 12px;
      background: rgba(17, 20, 28, 0.85);
      padding: 6px 10px;
      border-radius: 6px;
      border: 1px solid #1f2430;
      color: #6b7280;
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>Multiplayer Dot Arena</h1>
    <p>Use WASD / Arrow Keys or Mouse to move and collect dots!</p>
  </div>
  <div id="game-container">
    <canvas id="canvas" width="800" height="600"></canvas>
    <div id="status">Connecting...</div>
    <div id="leaderboard">
      <h3>Leaderboard</h3>
      <div id="p-list"></div>
    </div>
  </div>

  <script>
    const canvas = document.getElementById("canvas");
    const ctx = canvas.getContext("2d");
    const statusEl = document.getElementById("status");
    const pListEl = document.getElementById("p-list");

    const proto = location.protocol === "https:" ? "wss" : "ws";
    const ws = new WebSocket(proto + "://" + location.host + "/ws");

    let myId = null;
    let players = [];
    let food = [];

    let myPos = { x: 400, y: 300 };
    const keys = {};

    window.addEventListener("keydown", e => keys[e.key] = true);
    window.addEventListener("keyup", e => keys[e.key] = false);

    let mousePos = null;
    canvas.addEventListener("mousemove", e => {
      const rect = canvas.getBoundingClientRect();
      mousePos = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    });
    canvas.addEventListener("mouseleave", () => mousePos = null);

    ws.onopen = () => { statusEl.textContent = "Connected"; statusEl.style.color = "#3fb950"; };
    ws.onclose = () => { statusEl.textContent = "Disconnected"; statusEl.style.color = "#f85149"; };
    ws.onerror = () => { statusEl.textContent = "Error"; statusEl.style.color = "#f85149"; };

    ws.onmessage = e => {
      const msg = JSON.parse(e.data);
      if (msg.type === "init") {
        myId = msg.id;
        myPos.x = msg.x;
        myPos.y = msg.y;
      } else if (msg.type === "state") {
        players = msg.players;
        food = msg.food;
        updateLeaderboard();
      }
    };

    function updateLeaderboard() {
      const sorted = [...players].sort((a,b) => b.score - a.score);
      pListEl.innerHTML = sorted.map(p => `
        <div class="p-row ${p.id === myId ? 'me' : ''}">
          <span>${p.id === myId ? 'You' : p.id}</span>
          <span>${p.score}</span>
        </div>
      `).join('');
    }

    const speed = 4;

    function gameLoop() {
      // Input handling
      let dx = 0, dy = 0;
      if (keys["ArrowLeft"] || keys["a"] || keys["A"]) dx -= 1;
      if (keys["ArrowRight"] || keys["d"] || keys["D"]) dx += 1;
      if (keys["ArrowUp"] || keys["w"] || keys["W"]) dy -= 1;
      if (keys["ArrowDown"] || keys["s"] || keys["S"]) dy += 1;

      if (dx !== 0 || dy !== 0) {
        const len = Math.hypot(dx, dy);
        myPos.x += (dx / len) * speed;
        myPos.y += (dy / len) * speed;
      } else if (mousePos) {
        const pdx = mousePos.x - myPos.x;
        const pdy = mousePos.y - myPos.y;
        const dist = Math.hypot(pdx, pdy);
        if (dist > 5) {
          myPos.x += (pdx / dist) * Math.min(dist * 0.1, speed);
          myPos.y += (pdy / dist) * Math.min(dist * 0.1, speed);
        }
      }

      // Clamp position
      myPos.x = Math.max(15, Math.min(785, myPos.x));
      myPos.y = Math.max(15, Math.min(585, myPos.y));

      // Sync position to server
      if (ws.readyState === WebSocket.OPEN && myId) {
        ws.send(JSON.stringify({ type: "move", x: myPos.x, y: myPos.y }));
      }

      // Draw background
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.strokeStyle = "#1a1f2c";
      ctx.lineWidth = 1;
      for (let x = 0; x < canvas.width; x += 40) {
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, canvas.height); ctx.stroke();
      }
      for (let y = 0; y < canvas.height; y += 40) {
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(canvas.width, y); ctx.stroke();
      }

      // Draw Food
      for (const f of food) {
        ctx.beginPath();
        ctx.arc(f.x, f.y, 6, 0, Math.PI * 2);
        ctx.fillStyle = f.color;
        ctx.fill();
      }

      // Draw Players
      for (const p of players) {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fillStyle = p.color;
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = p.id === myId ? "#ffffff" : "rgba(255,255,255,0.3)";
        ctx.stroke();

        // Label
        ctx.font = "11px monospace";
        ctx.fillStyle = "#e6e8ee";
        ctx.textAlign = "center";
        ctx.fillText(p.id === myId ? "You" : p.id, p.x, p.y - p.size - 6);
      }

      requestAnimationFrame(gameLoop);
    }

    requestAnimationFrame(gameLoop);
  </script>
</body>
</html>"""

async def index(request):
    return web.Response(text=HTML, content_type="text/html")

connected_ws = set()

async def ws_handler(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    player_id = f"Player_{random.randint(100, 999)}"
    color = f"hsl({random.randint(0, 360)}, 85%, 55%)"
    
    player = {
        "id": player_id,
        "x": random.randint(100, 700),
        "y": random.randint(100, 500),
        "score": 0,
        "color": color,
        "size": 14
    }

    players[player_id] = player
    connected_ws.add(ws)

    # Send player initialization data
    await ws.send_json({"type": "init", "id": player_id, "x": player["x"], "y": player["y"]})

    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                data = json.loads(msg.data)
                if data.get("type") == "move":
                    player["x"] = max(15, min(785, data.get("x", player["x"])))
                    player["y"] = max(15, min(585, data.get("y", player["y"])))

                    # Food collision check
                    for f in food[:]:
                        dx = player["x"] - f["x"]
                        dy = player["y"] - f["y"]
                        if dx*dx + dy*dy < (player["size"] + 6) ** 2:
                            food.remove(f)
                            player["score"] += 10
                            player["size"] = min(35, 14 + player["score"] // 30)
                            spawn_food()
    finally:
        connected_ws.discard(ws)
        if player_id in players:
            del players[player_id]

    return ws

async def broadcast_loop(app):
    while True:
        await asyncio.sleep(0.03) # ~30 FPS server updates
        if connected_ws:
            state_msg = json.dumps({
                "type": "state",
                "players": list(players.values()),
                "food": food
            })
            for ws in list(connected_ws):
                try:
                    await ws.send_str(state_msg)
                except Exception:
                    pass

async def start_background_tasks(app):
    app['broadcast_task'] = asyncio.create_task(broadcast_loop(app))

async def cleanup_background_tasks(app):
    app['broadcast_task'].cancel()
    await app['broadcast_task']

app = web.Application()
app.on_startup.append(start_background_tasks)
app.on_cleanup.append(cleanup_background_tasks)
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
