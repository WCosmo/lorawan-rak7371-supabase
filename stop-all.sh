#!/bin/bash
# =============================================================================
# stop-all.sh - Para TODOS os serviços LoRaWAN
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           🛑  Parando Rede LoRaWAN Completa                         ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# Para o Bridge Python
BRIDGE_PID=$(pgrep -f "python bridge.py" || true)
if [ -n "$BRIDGE_PID" ]; then
    echo -e "${BLUE}ℹ${NC} Parando Bridge Python (PID: $BRIDGE_PID)..."
    kill "$BRIDGE_PID" 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}✓${NC} Bridge Python parado."
else
    echo -e "${YELLOW}⚠${NC} Bridge Python não estava rodando."
fi

# Para o Packet Forwarder
echo -e "${BLUE}ℹ${NC} Parando Packet Forwarder..."
cd packet-forwarder
docker compose down 2>/dev/null || true
cd "$SCRIPT_DIR"
echo -e "${GREEN}✓${NC} Packet Forwarder parado."

# Para o ChirpStack
echo -e "${BLUE}ℹ${NC} Parando ChirpStack..."
docker compose down 2>/dev/null || true
echo -e "${GREEN}✓${NC} ChirpStack parado."

echo ""
echo -e "${GREEN}✓${NC} Todos os serviços foram encerrados."
echo ""
