#!/bin/sh
set -e
apt-get update && apt-get install -y --no-install-recommends curl ca-certificates
curl -L -o jdk.tar.gz https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jre/hotspot/normal/eclipse
mkdir -p jdk21
tar -xzf jdk.tar.gz -C jdk21 --strip-components=1
rm jdk.tar.gz
export PATH="/app/jdk21/bin:$PATH"
B=$(curl -s https://api.papermc.io/v2/projects/paper/versions/1.21.1/builds | grep -o '"build":[0-9]*' | tail -1 | grep -o '[0-9]*')
curl -L -o server.jar "https://api.papermc.io/v2/projects/paper/versions/1.21.1/builds/${B}/downloads/paper-1.21.1-${B}.jar"
echo eula=true > eula.txt
cat > run.sh <<'EOF'
#!/bin/sh
export PATH="/app/jdk21/bin:$PATH"
exec java -Xms5G -Xmx5G -jar server.jar --nogui
EOF
chmod +x run.sh
