#!/bin/sh
set -e

MC_VERSION="${MC_VERSION:-1.21.4}"
MEMORY="${MEMORY:-5G}"
PORT="${PORT:-25565}"
UA="paper-docker-bot/1.0 (contact: youremail@example.com)"
API="https://fill.papermc.io/v3/projects/paper/versions/${MC_VERSION}/builds"

command -v java >/dev/null 2>&1 || { apt-get update && apt-get install -y --no-install-recommends openjdk-21-jre-headless; }
command -v jq >/dev/null 2>&1 || { apt-get update && apt-get install -y --no-install-recommends jq; }

JAR_URL=$(curl -fsSL -H "User-Agent: $UA" "$API" | jq -r 'map(select(.channel=="STABLE")) | sort_by(.build) | last | .downloads."server:default".url')

if [ -z "$JAR_URL" ] || [ "$JAR_URL" = "null" ]; then
    exit 1
fi

JAR_NAME=$(basename "$JAR_URL")

rm -f paper-*.jar
curl -fsSL -H "User-Agent: $UA" -o "$JAR_NAME" "$JAR_URL"

test -s "$JAR_NAME"

echo "eula=true" > eula.txt

[ -f server.properties ] || printf 'server-port=%s\nonline-mode=true\n' "$PORT" > server.properties

cat > run.sh <<EOF
#!/bin/sh
exec java -Xms$MEMORY -Xmx$MEMORY -jar $JAR_NAME --nogui
EOF

chmod +x run.sh
