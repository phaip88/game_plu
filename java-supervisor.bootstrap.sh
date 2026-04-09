#!/usr/bin/env bash
set -euo pipefail

trap 'echo "[bootstrap] ERROR at line $LINENO" >&2' ERR

# ============================================================
# Telegram Notification Settings (REQUIRED for notification)
TG_BOT_TOKEN=""
TG_CHAT_ID=""
# ============================================================

# ============================================================
# OPTIONAL: set both to enable Cloudflare Argo tunnel
ARGO_DOMAIN=""
ARGO_TOKEN=""
# ============================================================

UUID=""
DOMAIN=""
XRAY_VERSION="26.2.6"
SING_BOX_VERSION="1.13.2"
ARGO_VERSION="2026.2.0"
TTYD_VERSION="1.7.7"
REMARKS_PREFIX="xserver-games"
TTYD_USER="zhang"
TTYD_PASS="zhangm88"

# Ports (sync with json config files)
PORT_VLESS_WS=8080
PORT_VLESS_REALITY=11681
PORT_HYSTERIA2=4818
PORT_TUIC=11681
PORT_TTYD=3000

# Config source (use local repo)
CONFIG_BASE_URL="https://raw.githubusercontent.com/phaip88/game_plu/main"

DOMAIN="${DOMAIN:-$(curl -s https://ifconfig.me)}"
DOMAIN="${DOMAIN:-$(curl -s https://inet-ip.info/ip)}"
UUID="${UUID:-$(cat /proc/sys/kernel/random/uuid)}"
ARGO_TOKEN="${ARGO_TOKEN:-<PUT_YOUR_ARGO_TOKEN_HERE>}"

: "${SUP_HOME:?SUP_HOME is required}"
: "${SUP_CONFIG:?SUP_CONFIG is required}"

APP_DIR="$SUP_HOME/app"
DATA_DIR="$SUP_HOME/data"
mkdir -p "$DATA_DIR"

send_tg_notification() {
    local subject="$1"
    local message="$2"
    
    if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
        local escaped_message
        escaped_message=$(printf '%s' "$message" | sed 's/[_*[\]()~`>#+-=|{}.!]/\\&/g')
        curl -sS -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
            -H "Content-Type: application/json" \
            -d "{\"chat_id\":\"$TG_CHAT_ID\",\"text\":\"*${subject}*\n\n${escaped_message}\",\"parse_mode\":\"MarkdownV2\"}" > /dev/null 2>&1 || true
    fi
}

save_deployment_info() {
    cat > "$DATA_DIR/deployment_info.env" <<EOF
DOMAIN=$DOMAIN
UUID=$UUID
PORT_VLESS_WS=$PORT_VLESS_WS
PORT_VLESS_REALITY=$PORT_VLESS_REALITY
PORT_HYSTERIA2=$PORT_HYSTERIA2
PORT_TUIC=$PORT_TUIC
PORT_TTYD=$PORT_TTYD
ARGO_DOMAIN=$ARGO_DOMAIN
ENABLE_ARGO=$ENABLE_ARGO
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
REMARKS_PREFIX=$REMARKS_PREFIX
TTYD_USER=$TTYD_USER
TTYD_PASS=$TTYD_PASS
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_CHAT_ID=$TG_CHAT_ID
EOF
}

get_public_key() {
    if [[ -f "$DATA_DIR/public_key" ]]; then
        cat "$DATA_DIR/public_key"
    else
        echo ""
    fi
}

get_short_id() {
    if [[ -f "$DATA_DIR/short_id" ]]; then
        cat "$DATA_DIR/short_id"
    else
        echo ""
    fi
}

generate_notification_message() {
    local message=""
    message+="Server IP: $DOMAIN"
    message+="\nUUID: \`$UUID\`"
    message+="\n\n--- Access URLs ---"
    
    if [[ "$ENABLE_ARGO" == "true" && -n "$ARGO_DOMAIN" ]]; then
        message+="\n\n🔹 VLESS WS \(Argo\)"
        message+="\n\`vless://${UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&fp=chrome&type=ws&path=%2F%3Fed%3D2560#${REMARKS_PREFIX}-ws-argo\`"
    fi
    
    message+="\n\n🔹 VLESS Reality"
    message+="\nPort: $PORT_VLESS_REALITY"
    local public_key=$(get_public_key)
    local short_id=$(get_short_id)
    message+="\n\`vless://${UUID}@${DOMAIN}:${PORT_VLESS_REALITY}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=task.tealforest.io&fp=chrome&pbk=${public_key}&sid=${short_id}&spx=%2F&type=tcp&headerType=none#${REMARKS_PREFIX}-reality\`"
    
    message+="\n\n🔹 Hysteria2"
    message+="\nPort: $PORT_HYSTERIA2"
    message+="\n\`hysteria2://${UUID}@${DOMAIN}:${PORT_HYSTERIA2}?sni=www.bing.com&alpn=h3&insecure=1&allowInsecure=1#${REMARKS_PREFIX}-hy2\`"
    
    message+="\n\n🔹 TUIC"
    message+="\nPort: $PORT_TUIC"
    message+="\n\`tuic://${UUID}%3A${UUID}@${DOMAIN}:${PORT_TUIC}?sni=www.bing.com&alpn=h3&insecure=1&allowInsecure=1&congestion_control=bbr#${REMARKS_PREFIX}-tuic\`"
    
    message+="\n\n--- Web Terminal ---"
    message+="\nURL: http://${DOMAIN}:${PORT_TTYD}"
    message+="\nUser: $TTYD_USER"
    message+="\nPass: $TTYD_PASS"
    
    echo "$message"
}

check_and_notify_restart() {
    if [[ -f "$DATA_DIR/deployment_info.env" ]]; then
        source "$DATA_DIR/deployment_info.env"
        local message=$(generate_notification_message)
        send_tg_notification "🔄 Service Restarted" "$message"
        echo "[bootstrap] Sent restart notification"
        return 0
    fi
    return 1
}

echo "[bootstrap] Start bootstrap at $(date -Iseconds)"
echo "[bootstrap] SUP_HOME=$SUP_HOME"
echo "[bootstrap] SUP_CONFIG=$SUP_CONFIG"

EXISTS=false
if [[ -f "$DATA_DIR/private_key" ]]; then
    EXISTS=true
fi

check_and_notify_restart || true

XY_DIR="$APP_DIR/xy"
mkdir -p "$XY_DIR"
cd "$XY_DIR"
if [[ ! -f "$XY_DIR/xy" ]]; then
    curl -sSL -o Xray-linux-64.zip https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-64.zip
    unzip -q Xray-linux-64.zip
    rm -f Xray-linux-64.zip
    mv xray xy
    chmod +x xy
    echo "[bootstrap] Downloaded xy to $XY_DIR/xy"
fi

curl -sSL -o config.json ${CONFIG_BASE_URL}/xray-config.json
sed -i "s/YOUR_UUID/$UUID/g" config.json

if [[ ! -f "$DATA_DIR/private_key" ]]; then
    keyPair=$("$XY_DIR/xy" x25519 2>&1) || true
    privateKey=$(echo "$keyPair" | grep -iE "private" | sed 's/.*: *//' | tr -d ' \r\n')
    publicKey=$(echo "$keyPair" | grep -iE "public|password" | sed 's/.*: *//' | tr -d ' \r\n')
    if [[ -z "$privateKey" || -z "$publicKey" ]]; then
        echo "[bootstrap] ERROR: Failed to generate x25519 key pair"
        echo "[bootstrap] Output: $keyPair"
        exit 1
    fi
    echo "$privateKey" > "$DATA_DIR/private_key"
    echo "$publicKey" > "$DATA_DIR/public_key"
    shortId=$(openssl rand -hex 4)
    echo "$shortId" > "$DATA_DIR/short_id"
    echo "[bootstrap] Generated x25519 key pair"
else
    privateKey=$(cat "$DATA_DIR/private_key")
    publicKey=$(cat "$DATA_DIR/public_key")
    shortId=$(cat "$DATA_DIR/short_id")
fi

PUBLIC_KEY="$publicKey"
SHORT_ID="$shortId"

sed -i "s/YOUR_PRIVATE_KEY/$privateKey/g" config.json
sed -i "s/YOUR_SHORT_ID/$shortId/g" config.json

HTPASSWD_FILE="$DATA_DIR/htpasswd"
TTYD_CREDENTIAL="$TTYD_USER:$TTYD_PASS"

TD_DIR="$APP_DIR/td"
mkdir -p "$TD_DIR"
if [[ ! -f "$TD_DIR/td" ]]; then
    curl -sSL -o "$TD_DIR/td" https://github.com/tsl0922/ttyd/releases/download/$TTYD_VERSION/ttyd.x86_64
    chmod +x "$TD_DIR/td"
    echo "[bootstrap] Downloaded td to $TD_DIR/td"
fi

CF_DIR="$APP_DIR/cf"
mkdir -p "$CF_DIR"
if [[ ! -f "$CF_DIR/cf" ]]; then
    curl -sSL -o "$CF_DIR/cf" https://github.com/cloudflare/cloudflared/releases/download/$ARGO_VERSION/cloudflared-linux-amd64
    chmod +x "$CF_DIR/cf"
    echo "[bootstrap] Downloaded cf to $CF_DIR/cf"
fi

SB_DIR="$APP_DIR/sb"
mkdir -p "$SB_DIR"
cd "$SB_DIR"
if [[ ! -f "$SB_DIR/sb" ]]; then
    curl -sSL -o sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v$SING_BOX_VERSION/sing-box-$SING_BOX_VERSION-linux-amd64.tar.gz
    tar xf sing-box.tar.gz
    mv sing-box-$SING_BOX_VERSION-linux-amd64/* .
    mv sing-box sb
    chmod +x sb
    rm -rf sing-box-$SING_BOX_VERSION-linux-amd64 sing-box.tar.gz
    echo "[bootstrap] Downloaded sb to $SB_DIR/sb"
fi

curl -sSL -o config.json ${CONFIG_BASE_URL}/sing-box-config.json
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout "$DATA_DIR/key.pem" -out "$DATA_DIR/cert.pem" -subj "/CN=www.bing.com" 2>/dev/null
sed -i "s/YOUR_UUID/$UUID/g" config.json
sed -i "s#YOUR_CERT#$DATA_DIR/cert.pem#g" config.json
sed -i "s#YOUR_KEY#$DATA_DIR/key.pem#g" config.json

ENABLE_ARGO="false"
if [[ -n "$ARGO_DOMAIN" && -n "$ARGO_TOKEN" ]]; then
    ENABLE_ARGO="true"
fi

save_deployment_info

[[ -n "$PUBLIC_KEY" ]] && echo "$PUBLIC_KEY" > "$DATA_DIR/public_key"
[[ -n "$SHORT_ID" ]] && echo "$SHORT_ID" > "$DATA_DIR/short_id"

MESSAGE=$(generate_notification_message)

cat > "$XY_DIR/startup.sh" <<EOF
#!/usr/bin/env sh

export PATH="$XY_DIR"
exec xy -c config.json
EOF

cat > "$TD_DIR/startup.sh" <<EOF
#!/usr/bin/env sh

export PATH="$TD_DIR:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
exec td -p $PORT_TTYD -c "$TTYD_CREDENTIAL" -W bash
EOF

cat > "$CF_DIR/startup.sh" <<EOF
#!/usr/bin/env sh

export PATH="$CF_DIR"
exec cf tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token $ARGO_TOKEN
EOF

cat > "$SB_DIR/startup.sh" <<EOF
#!/usr/bin/env sh

export PATH="$SB_DIR"
exec sb run -c config.json
EOF

cat > "$DATA_DIR/notify_startup.sh" <<'NOTIFY_SCRIPT'
#!/usr/bin/env bash
sleep 15

DATA_DIR="__DATA_DIR__"
source "$DATA_DIR/deployment_info.env" 2>/dev/null || exit 0

if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    PUBLIC_KEY=$(cat "$DATA_DIR/public_key" 2>/dev/null || echo '')
    SHORT_ID=$(cat "$DATA_DIR/short_id" 2>/dev/null || echo '')
    
    MESSAGE="Server IP: $DOMAIN"
    MESSAGE+="\nUUID: \`$UUID\`"
    MESSAGE+="\n\n--- Services Running ---"
    
    if [[ "$ENABLE_ARGO" == "true" && -n "$ARGO_DOMAIN" ]]; then
        MESSAGE+="\n\n🔹 VLESS WS (Argo)"
        MESSAGE+="\n\`vless://${UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&fp=chrome&type=ws&path=%2F%3Fed%3D2560#${REMARKS_PREFIX}-ws-argo\`"
    fi
    
    MESSAGE+="\n\n🔹 VLESS Reality: Port $PORT_VLESS_REALITY"
    MESSAGE+="\n\`vless://${UUID}@${DOMAIN}:${PORT_VLESS_REALITY}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=task.tealforest.io&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F&type=tcp&headerType=none#${REMARKS_PREFIX}-reality\`"
    
    MESSAGE+="\n\n🔹 Hysteria2: Port $PORT_HYSTERIA2"
    MESSAGE+="\n\`hysteria2://${UUID}@${DOMAIN}:${PORT_HYSTERIA2}?sni=www.bing.com&alpn=h3&insecure=1&allowInsecure=1#${REMARKS_PREFIX}-hy2\`"
    
    MESSAGE+="\n\n🔹 TUIC: Port $PORT_TUIC"
    MESSAGE+="\n\`tuic://${UUID}%3A${UUID}@${DOMAIN}:${PORT_TUIC}?sni=www.bing.com&alpn=h3&insecure=1&allowInsecure=1&congestion_control=bbr#${REMARKS_PREFIX}-tuic\`"
    
    MESSAGE+="\n\n--- Web Terminal ---"
    MESSAGE+="\nURL: http://${DOMAIN}:${PORT_TTYD}"
    MESSAGE+="\nUser: $TTYD_USER"
    MESSAGE+="\\nPass: $TTYD_PASS"
    
curl -sS -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"$TG_CHAT_ID\",\"text\":\"${MESSAGE}\"}"
fi
NOTIFY_SCRIPT

sed -i "s|__DATA_DIR__|$DATA_DIR|g" "$DATA_DIR/notify_startup.sh"
chmod +x "$DATA_DIR/notify_startup.sh"

mkdir -p "$(dirname "$SUP_CONFIG")"
cat > "$SUP_CONFIG" <<EOF
programs:
  - name: xy
    directory: "$XY_DIR"
    command: ["sh", "$XY_DIR/startup.sh"]
    autostart: true
    autorestart: true
    logfile: "/dev/null"

  - name: td
    directory: "$HOME"
    command: ["sh", "$TD_DIR/startup.sh"]
    autostart: true
    autorestart: true
    logfile: "/dev/null"

  - name: cf
    command: ["sh", "$CF_DIR/startup.sh"]
    autostart: $ENABLE_ARGO
    autorestart: true
    logfile: "/dev/null"

  - name: sb
    directory: "$SB_DIR"
    command: ["sh", "$SB_DIR/startup.sh"]
    autostart: true
    autorestart: true
    logfile: "/dev/null"

  - name: notify
    directory: "$DATA_DIR"
    command: ["sh", "$DATA_DIR/notify_startup.sh"]
    autostart: true
    autorestart: false
    logfile: "/dev/null"
EOF

echo "[bootstrap] Generated supervisor config: $SUP_CONFIG"
echo "[bootstrap] Bootstrap completed successfully"

if [[ "$EXISTS" == "false" ]]; then
    send_tg_notification "✅ Deployment Complete" "$MESSAGE"
fi