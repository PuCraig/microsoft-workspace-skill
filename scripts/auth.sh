#!/bin/bash
# Microsoft Workspace Auth Setup
# Quick setup for credentials - stores them in ~/.hermes/
#
# Usage:
#   ./auth.sh --client-id YOUR_CLIENT_ID --client-secret YOUR_SECRET --tenant-id YOUR_TENANT
#   ./auth.sh --client-id YOUR_CLIENT_ID --client-secret YOUR_SECRET  (uses 'consumers' tenant)
#   ./auth.sh --check   (verify existing auth)
#   ./auth.sh --config --name "Your Name" --agent "AgentName"  (set display name for invites)
#   ./auth.sh --config --timezone "Australia/Sydney"      (default timezone for calendar ops)

set -e

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SECRET_FILE="$HERMES_HOME/microsoft_client_secret.json"
CONFIG_FILE="$HERMES_HOME/microsoft_config.json"

# Resolve a working Python interpreter (Windows Store stubs python3)
resolve_python() {
    for p in python3 python py; do
        if command -v "$p" >/dev/null 2>&1 && "$p" -c "import sys" >/dev/null 2>&1; then
            echo "$p"; return 0
        fi
    done
    echo "python3"
}
PY="$(resolve_python)"

# Ensure directory exists
mkdir -p "$HERMES_HOME"

ACTION="setup"
CLIENT_ID=""
CLIENT_SECRET=""
TENANT_ID="consumers"
SENDER_NAME=""
AGENT_NAME=""
TIMEZONE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --check) ACTION="check"; shift ;;
        --config) ACTION="config"; shift ;;
        --client-id) CLIENT_ID="$2"; shift 2 ;;
        --client-secret) CLIENT_SECRET="$2"; shift 2 ;;
        --tenant-id) TENANT_ID="$2"; shift 2 ;;
        --name) SENDER_NAME="$2"; shift 2 ;;
        --agent) AGENT_NAME="$2"; shift 2 ;;
        --timezone) TIMEZONE="$2"; shift 2 ;;
        -h|--help)
            echo "Microsoft Workspace Auth Setup"
            echo ""
            echo "Usage:"
            echo "  auth.sh --client-id ID --client-secret SECRET [--tenant-id TENANT]"
            echo "  auth.sh --check"
            echo "  auth.sh --config --name 'Your Name' --agent 'AgentName' [--timezone TZ]"
            echo ""
            echo "Options:"
            echo "  --client-id       Azure App Registration client ID"
            echo "  --client-secret   Azure App Registration client secret"
            echo "  --tenant-id       Azure tenant ID (default: 'consumers' for personal accounts)"
            echo "  --check           Verify existing auth is working"
            echo "  --config          Set sender name and agent name for calendar invites"
            echo "  --name            Your display name (used in invite sign-offs)"
            echo "  --agent           Your AI agent's name (used in invite footer)"
            echo "  --timezone        Default timezone for calendar ops (e.g. Australia/Sydney)"
            exit 0
            ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

if [[ "$ACTION" == "check" ]]; then
    echo "=== Microsoft Workspace Auth Check ==="
    echo ""

    if [[ -f "$SECRET_FILE" ]]; then
        echo "Credentials: $SECRET_FILE"
        CID=$($PY -c "import json; print(json.load(open('$SECRET_FILE'))['client_id'])" 2>/dev/null || echo "ERROR reading file")
        echo "  Client ID: ${CID:0:8}..."
    else
        echo "Credentials: NOT FOUND"
        echo "  Run: auth.sh --client-id YOUR_ID --client-secret YOUR_SECRET"
    fi

    echo ""

    TOKEN_FILE="$HERMES_HOME/microsoft_token.json"
    if [[ -f "$TOKEN_FILE" ]]; then
        echo "Token: $TOKEN_FILE"
        EXPIRES=$($PY -c "
import json, time
t = json.load(open('$TOKEN_FILE'))
exp = t.get('expires_at', 0)
if exp > time.time():
    mins = int((exp - time.time()) / 60)
    print(f'Valid (expires in {mins} min)')
else:
    print('EXPIRED')
" 2>/dev/null || echo "ERROR reading token")
        echo "  Status: $EXPIRES"
    else
        echo "Token: NOT FOUND"
        echo "  Run: $PY setup.py --auth-url"
    fi

    echo ""

    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Config: $CONFIG_FILE"
        $PY -c "import json; c=json.load(open('$CONFIG_FILE')); [print(f'  {k}: {v}') for k,v in c.items()]" 2>/dev/null
    else
        echo "Config: NOT SET (optional)"
        echo "  Run: auth.sh --config --name 'Your Name' --agent 'AgentName'"
    fi

    echo ""
    echo "Quick test:"
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    SCRIPT_DIR_NATIVE="$(cygpath -w "$SCRIPT_DIR" 2>/dev/null || echo "$SCRIPT_DIR")"
    "$PY" "$SCRIPT_DIR_NATIVE/microsoft_api.py" mail list --max 1 2>&1 | head -3
    exit 0
fi

if [[ "$ACTION" == "config" ]]; then
    if [[ -z "$SENDER_NAME" && -z "$AGENT_NAME" && -z "$TIMEZONE" ]]; then
        echo "Current config:"
        if [[ -f "$CONFIG_FILE" ]]; then
            cat "$CONFIG_FILE"
        else
            echo "  (none set)"
        fi
        echo ""
        echo "Set with: auth.sh --config --name 'Your Name' --agent 'AgentName' [--timezone TZ]"
        exit 0
    fi

    # Merge with existing config
    EXISTING="{}"
    if [[ -f "$CONFIG_FILE" ]]; then
        EXISTING=$(cat "$CONFIG_FILE")
    fi

    $PY -c "
import json
c = json.loads('''$EXISTING''') if '''$EXISTING''' != '{}' else {}
if '$SENDER_NAME': c['sender_name'] = '$SENDER_NAME'
if '$AGENT_NAME': c['agent_name'] = '$AGENT_NAME'
if '$TIMEZONE': c['timezone'] = '$TIMEZONE'
with open('$CONFIG_FILE', 'w') as f:
    json.dump(c, f, indent=2)
print('Config saved to $CONFIG_FILE')
print(json.dumps(c, indent=2))
"
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
    exit 0
fi

# Setup credentials
if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
    echo "ERROR: --client-id and --client-secret are required"
    echo ""
    echo "Usage: auth.sh --client-id YOUR_ID --client-secret YOUR_SECRET [--tenant-id TENANT]"
    echo ""
    echo "To get these values, see README.md for Azure App Registration setup."
    exit 1
fi

echo "=== Saving Microsoft credentials ==="
python3 -c "
import json
data = {
    'client_id': '$CLIENT_ID',
    'client_secret': '$CLIENT_SECRET',
    'tenant_id': '$TENANT_ID'
}
with open('$SECRET_FILE', 'w') as f:
    json.dump(data, f, indent=2)
print(f'Saved to: $SECRET_FILE')
"
chmod 600 "$SECRET_FILE" 2>/dev/null || true

echo ""
echo "Credentials saved. Next step: authorize your account."
echo ""
echo "Run these commands:"
echo ""
echo "  1. Get auth URL:"
echo "     $PY $(dirname "$0")/setup.py --auth-url"
echo ""
echo "  2. Open the URL in your browser, sign in, and copy the redirect URL"
echo ""
echo "  3. Paste the redirect URL:"
echo "     $PY $(dirname "$0")/setup.py --auth-code 'PASTE_URL_HERE'"
echo ""
echo "  4. (Optional) Set your display name for invites:"
echo "     $(dirname "$0")/auth.sh --config --name 'Your Name' --agent 'AgentName'"
