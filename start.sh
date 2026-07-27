#!/bin/sh
set -e

MC_VERSION="${MC_VERSION:-latest}"
MEMORY="${MEMORY:-7G}"
PORT="${PORT:-25565}"
API="https://api.papermc.io/v2/projects/paper"

command -v java >/dev/null 2>&1 || { apt-get update >/dev/null 2>&1 && apt-get install -y --no-install-recommends openjdk-21-jre-headless >/dev/null 2>&1; }

if [ "$MC_VERSION" = "latest" ]; then
    MC_VERSION=$(curl -fsSL "$API" | python3 -c "import sys,json;print(json.load(sys.stdin)['versions'][-1])")
fi

BUILD=$(curl -fsSL "$API/versions/$MC_VERSION" | python3 -c "import sys,json;print(json.load(sys.stdin)['builds'][-1])")
JAR_NAME="paper-$MC_VERSION-$BUILD.jar"

rm -f paper-*.jar
curl -fsSL -o "$JAR_NAME" "$API/versions/$MC_VERSION/builds/$BUILD/downloads/$JAR_NAME"

echo "eula=true" > eula.txt

[ -f server.properties ] || printf 'server-port=%s\nonline-mode=true\n' "$PORT" > server.properties

cat > run.sh <<EOF
#!/bin/sh
exec java -Xms$MEMORY -Xmx$MEMORY -jar $JAR_NAME --nogui
EOF

chmod +x run.sh
